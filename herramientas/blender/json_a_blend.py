"""Convierte un modelo de piezas de SpriteBaker (.json) en un archivo de Blender listo para editar.

Sirve como plantilla: sale el mismo personaje (huesos con los nombres que espera Karth, piezas
pegadas a su hueso, equipo marcado con su grupo y las acciones quieto / caminar / golpe / apuntar),
para que en Blender solo haya que darle mejor forma, pintarlo y ajustar las animaciones.

Uso (con Blender instalado):
    blender --background --python json_a_blend.py -- colono_piezas.json plantilla_colono.blend
Con un tercer nombre también exporta el .glb:
    blender --background --python json_a_blend.py -- colono_piezas.json plantilla_colono.blend ../../modelos/colono.glb

Convenciones (las mismas que lee el juego, ver LEEME.md de esta carpeta):
  - 1 casilla = 1.9 m. El personaje mira hacia -Y (se ve de frente en la vista Front) y pisa en Z = 0.
  - Objetos de equipo: propiedad personalizada "grupo" (armadura, casco, botas, arma).
  - Materiales que empiezan con "armadura": se tiñen con el color del jugador (blanco = color pleno).
"""
import json
import math
import sys

import bpy
from mathutils import Euler, Matrix, Vector

METROS_POR_CASILLA = 1.9
FPS = 24
# JSON (Y arriba, mira a +Z)  ->  Blender (Z arriba, mira a -Y)
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
C_INV = C.inverted()


def a_blender(m):
    return C @ m @ C_INV


def matriz_local(pos, rot_grados, escala=(1, 1, 1)):
    # Godot gira en orden YXZ
    r = Euler([math.radians(v) for v in rot_grados], "YXZ").to_matrix().to_4x4()
    s = Matrix.Diagonal((escala[0], escala[1], escala[2], 1.0))
    return Matrix.Translation(Vector(pos)) @ r @ s


def evaluar(expr, ph, f, n):
    entorno = {k: getattr(math, k) for k in ("sin", "cos", "tan", "sqrt", "floor", "ceil", "pow")}
    entorno.update({"abs": abs, "max": max, "min": min, "PI": math.pi, "TAU": math.tau, "ph": ph, "f": f, "n": n})
    return float(eval(expr, {"__builtins__": {}}, entorno))


def deltas(anim, t):
    """Lo mismo que ModelBuilder.delta_en: cuánto se mueve cada pivote en el momento t (0 a 1)."""
    n = max(int(anim.get("frames", 1)), 1)
    x = t * n
    f = int(math.floor(x + 1e-5))
    resto = min(max(x - f, 0.0), 1.0)
    bucle = bool(anim.get("bucle", True))
    out = {}
    for pista in anim.get("pistas", []):
        if "frames" in pista:
            vals = pista["frames"]
            sig = (f + 1) % len(vals) if bucle else min(f + 1, len(vals) - 1)
            v = vals[f % len(vals)] * (1 - resto) + vals[sig] * resto
        else:
            v = evaluar(pista.get("expr", "0"), t * math.tau, f, n)
        d = out.setdefault(pista["pivote"], [[0, 0, 0], [0, 0, 0]])
        eje = "xyz".index(pista["prop"][-1])
        d[0 if pista["prop"].startswith("pos") else 1][eje] += v
    return out


def mundos(datos, delta=None):
    """Matriz en el mundo (coordenadas del JSON) de cada pivote, con o sin una pose encima."""
    delta = delta or {}
    out = {"raiz": Matrix.Identity(4)}
    for p in datos.get("pivotes", []):
        d = delta.get(p["id"], [[0, 0, 0], [0, 0, 0]])
        pos = [a + b for a, b in zip(p.get("pos", [0, 0, 0]), d[0])]
        rot = [a + b for a, b in zip(p.get("rot", [0, 0, 0]), d[1])]
        out[p["id"]] = out[p.get("padre", "raiz")] @ matriz_local(pos, rot)
    return out


def malla(pieza, nombre):
    forma = pieza.get("forma", "caja")
    radio = float(pieza.get("radio", 0.5))
    alto = float(pieza.get("alto", 1.0))
    if forma == "esfera":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=7, radius=radio)
    elif forma == "cono":
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=radio, radius2=0.0, depth=alto)
    elif forma == "cilindro":
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radio, depth=alto)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        t = pieza.get("tam", [1, 1, 1])
        for v in bpy.context.active_object.data.vertices:
            v.co = Vector((v.co.x * t[0], v.co.y * t[2], v.co.z * t[1]))
    obj = bpy.context.active_object
    obj.name = nombre
    obj.data.name = nombre
    if forma == "esfera":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def material(ident, d):
    zona = d.get("zona")
    nombre = ident
    color = [int(d.get("color", "#ffffff")[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    if zona:
        # Los que se tiñen van en grises: blanco = color pleno del jugador
        sombra = float(d.get("sombra", 1.0))
        nombre = zona if sombra >= 1.0 else "%s_oscura" % zona
        color = [sombra ** 2.2] * 3
    else:
        color = [c ** 2.2 for c in color]   # a lineal, como lo espera Blender
    mat = bpy.data.materials.new(nombre)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    if "emision" in d:
        e = [(int(d["emision"][i:i + 2], 16) / 255.0) ** 2.2 for i in (1, 3, 5)]
        bsdf.inputs["Emission Color"].default_value = (*e, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    mat.diffuse_color = (*color, 1.0)
    return mat


def convertir(ruta_json, ruta_blend, ruta_glb=None):
    datos = json.load(open(ruta_json, encoding="utf-8"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    escena = bpy.context.scene
    escena.render.fps = FPS
    escena.unit_settings.system = "METRIC"
    escala = METROS_POR_CASILLA / float(datos.get("escala_camara", 2.7))
    S = Matrix.Scale(escala, 4)
    nombre = datos.get("nombre", "modelo")
    reposo = mundos(datos)
    pivotes = datos.get("pivotes", [])
    piezas = datos.get("piezas", [])

    # --- Esqueleto: un hueso por pivote, de la articulación hacia la siguiente ---
    arm_data = bpy.data.armatures.new("Esqueleto")
    arm = bpy.data.objects.new("Esqueleto", arm_data)
    escena.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.show_in_front = True
    bpy.ops.object.mode_set(mode="EDIT")
    hijos = {}
    for p in pivotes:
        hijos.setdefault(p.get("padre", "raiz"), []).append(p["id"])
    for p in pivotes:
        pid = p["id"]
        cabeza = (S @ a_blender(reposo[pid])).translation
        cola = None
        for h in hijos.get(pid, []):
            c = (S @ a_blender(reposo[h])).translation
            if abs(c.x - cabeza.x) < 0.02 * escala * 10 and (c - cabeza).length > 0.08:
                cola = c
                break
        if cola is None:
            # Hueso final: apunta hacia donde están sus piezas
            centro = Vector((0, 0, 0))
            cuantas = 0
            for pz in piezas:
                if pz.get("pivote") == pid and "grupo" not in pz:
                    centro += Vector(pz.get("pos", [0, 0, 0]))
                    cuantas += 1
            if cuantas and (centro / cuantas).length > 0.05:
                lejos = max(Vector(pz.get("pos", [0, 0, 0])).length for pz in piezas if pz.get("pivote") == pid and "grupo" not in pz)
                dir_local = (centro / cuantas).normalized() * max(lejos, 0.2)
            else:
                dir_local = Vector((0, 0.25, 0))
            cola = (S @ a_blender(reposo[pid] @ Matrix.Translation(dir_local))).translation
        hueso = arm_data.edit_bones.new(pid)
        hueso.head = cabeza
        hueso.tail = cola
        if p.get("padre", "raiz") != "raiz":
            hueso.parent = arm_data.edit_bones[p["padre"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    reposo_hueso = {b.name: b.matrix_local.copy() for b in arm_data.bones}

    # --- Piezas: cada una es un objeto pegado a su hueso ---
    mats = {k: material(k, v) for k, v in datos.get("materiales", {}).items()}
    cuenta = {}
    for pz in piezas:
        base = pz.get("grupo") or pz.get("pivote", "pieza")
        cuenta[base] = cuenta.get(base, 0) + 1
        obj = malla(pz, "%s_%d" % (base, cuenta[base]))
        if pz.get("mat") in mats:
            obj.data.materials.append(mats[pz["mat"]])
        if "grupo" in pz:
            obj["grupo"] = pz["grupo"]
        m = reposo[pz.get("pivote", "raiz")] @ matriz_local(pz.get("pos", [0, 0, 0]), pz.get("rot", [0, 0, 0]), pz.get("escala", [1, 1, 1]))
        mundo = S @ a_blender(m)
        if pz.get("pivote", "raiz") in reposo_hueso:
            obj.parent = arm
            obj.parent_type = "BONE"
            obj.parent_bone = pz["pivote"]
            bpy.context.view_layer.update()
        obj.matrix_world = mundo
    bpy.context.view_layer.update()

    # --- Acciones ---
    anims = datos.get("animaciones", {})
    arm.animation_data_create()
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    def posar(delta):
        con_pose = mundos(datos, delta)
        for p in pivotes:   # padres antes que hijos
            pid = p["id"]
            cambio = S @ a_blender(con_pose[pid] @ reposo[pid].inverted()) @ S.inverted()
            arm.pose.bones[pid].matrix = cambio @ reposo_hueso[pid]
            bpy.context.view_layer.update()

    def accion(nombre_accion, cuadros):
        """cuadros: lista de (número de cuadro, delta)"""
        act = bpy.data.actions.new(nombre_accion)
        act.use_fake_user = True
        arm.animation_data.action = act
        for cuadro, delta in cuadros:
            posar(delta)
            for pb in arm.pose.bones:
                pb.keyframe_insert("location", frame=cuadro)
                pb.keyframe_insert("rotation_quaternion", frame=cuadro)
        pista = arm.animation_data.nla_tracks.new()
        pista.name = nombre_accion
        tira = pista.strips.new(nombre_accion, 1, act)
        tira.name = nombre_accion
        try:
            tira.action_slot = act.slots[0]
        except Exception:
            pass
        pista.mute = True
        arm.animation_data.action = None
        posar({})

    if "quieto" in anims:
        accion("quieto", [(1 + i * 6, deltas(anims["quieto"], (i % 8) / 8.0)) for i in range(9)])
    if "caminar" in anims:
        accion("caminar", [(1 + i * 2, deltas(anims["caminar"], (i % 12) / 12.0)) for i in range(13)])
    if "atacar" in anims:
        n = max(int(anims["atacar"].get("frames", 3)), 3)
        accion("golpe", [(1, {}), (6, deltas(anims["atacar"], 1.0 / n))])
        accion("apuntar", [(1, {}), (6, deltas(anims["atacar"], 2.0 / n))])
    escena.frame_start = 1
    escena.frame_end = 49
    escena.frame_set(1)

    arm["karth_modelo"] = nombre
    # Grupos de la paleta oficial que usa el horneador para este modelo (vacío = toda la paleta)
    arm["grupos_paleta"] = ",".join(datos.get("grupos_paleta", []))
    bpy.ops.wm.save_as_mainfile(filepath=ruta_blend)
    print("guardado:", ruta_blend)
    if ruta_glb:
        exportar(ruta_glb)


def exportar(ruta_glb):
    """Exporta la escena como la espera Karth (lo mismo que File > Export > glTF con estas opciones)."""
    bpy.ops.export_scene.gltf(
        filepath=ruta_glb, export_format="GLB", export_extras=True, export_yup=True, export_apply=True,
        export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
        export_skins=True, export_def_bones=False,
        export_vertex_color="NAME", export_vertex_color_name="volumen",
    )
    print("exportado:", ruta_glb)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    convertir(args[0], args[1], args[2] if len(args) > 2 else None)
