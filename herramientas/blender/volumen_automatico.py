"""Volumen automático para modelos de Karth: pinta en cada vértice las sombras de los huecos
(oclusión ambiental) y un degradado de arriba a abajo, y exporta el .glb con eso.

Es la «trampa» para que un modelo simple se vea con volumen sin pintar texturas: axilas, entre
las piernas, bajo el casco y los pies quedan más oscuros; hombros y cabeza, más claros.
El juego lo multiplica sobre los colores del modelo (en los estilos pixel y liso, y al hornear).

Uso desde Blender (con tu archivo abierto): pestaña Scripting → abre este archivo → Run Script.
Calcula el volumen y exporta a la ruta de EXPORTAR_A (relativa al .blend).
Sin abrir Blender:
    blender --background tu_modelo.blend --python volumen_automatico.py -- ../../modelos/colono.glb

Puedes volver a correrlo cuantas veces quieras: recalcula todo. Si después quieres retocar a mano,
en Blender pinta sobre el atributo de color «volumen» (modo Vertex Paint).
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# --- Ajustes (puedes cambiarlos) ---
EXPORTAR_A = "//../../modelos/colono.glb"   # // = la carpeta del .blend
RAYOS = 32               # más rayos = sombras más parejas (y más lento)
ALCANCE = 0.30           # metros: qué tan lejos busca lo que tapa la luz
FUERZA_HUECOS = 0.65     # 0 = sin sombras en huecos, 1 = huecos casi negros
DEGRADADO = 0.30         # cuánto más oscuro queda abajo (pies) que arriba (cabeza)
NOMBRE = "volumen"       # atributo de color que lee el juego


def mallas_del_modelo():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and o.visible_get()]


def arbol_de_choques(objetos, dg):
    """Todas las mallas juntas (en reposo y en el mundo), para lanzar rayos contra ellas."""
    vertices, caras = [], []
    for o in objetos:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        base = len(vertices)
        vertices += [o.matrix_world @ v.co for v in me.vertices]
        caras += [[base + i for i in p.vertices] for p in me.polygons]
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(vertices, caras, epsilon=0.0)


def direcciones_hemisferio(n):
    """Direcciones repartidas sobre medio globo (más hacia arriba que a los lados)."""
    al_azar = random.Random(7)
    dirs = []
    for i in range(n):
        u, v = (i + al_azar.random()) / n, al_azar.random()
        r, ang = math.sqrt(u), 2 * math.pi * v
        dirs.append(Vector((r * math.cos(ang), r * math.sin(ang), math.sqrt(max(0.0, 1 - u)))))
    return dirs


def calcular():
    objetos = mallas_del_modelo()
    if not objetos:
        print("volumen: no hay mallas visibles")
        return
    # En reposo: si hay esqueleto, se calcula con la pose de reposo
    esqueletos = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    antes = {a: a.data.pose_position for a in esqueletos}
    for a in esqueletos:
        a.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    arbol = arbol_de_choques(objetos, dg)
    alto_min = min((o.matrix_world @ Vector(c)).z for o in objetos for c in o.bound_box)
    alto_max = max((o.matrix_world @ Vector(c)).z for o in objetos for c in o.bound_box)
    alto = max(alto_max - alto_min, 0.01)
    hemisferio = direcciones_hemisferio(RAYOS)

    for o in objetos:
        me = o.data
        normales = o.matrix_world.to_3x3().inverted().transposed()
        valores = []
        for v in me.vertices:
            p = o.matrix_world @ v.co
            n = (normales @ v.normal).normalized()
            # base ortonormal alrededor de la normal
            t = n.orthogonal().normalized()
            b = n.cross(t)
            tapados = 0
            origen = p + n * 0.004
            for d in hemisferio:
                rayo = t * d.x + b * d.y + n * d.z
                golpe = arbol.ray_cast(origen, rayo, ALCANCE)
                if golpe[0] is not None:
                    tapados += 1
            huecos = 1.0 - FUERZA_HUECOS * (tapados / RAYOS)
            altura = (p.z - alto_min) / alto
            degradado = 1.0 - DEGRADADO * (1.0 - altura)
            valores.append(max(0.0, min(1.0, huecos * degradado)))
        attr = me.color_attributes.get(NOMBRE)
        if attr is not None and (attr.domain != "POINT" or attr.data_type != "FLOAT_COLOR"):
            me.color_attributes.remove(attr)
            attr = None
        if attr is None:
            attr = me.color_attributes.new(NOMBRE, "FLOAT_COLOR", "POINT")
        for i, val in enumerate(valores):
            attr.data[i].color = (val, val, val, 1.0)
        me.color_attributes.active_color = attr
        print("volumen: %s (%d vértices)" % (o.name, len(valores)))

    for a, pos in antes.items():
        a.data.pose_position = pos
    bpy.context.view_layer.update()


def exportar(ruta):
    ruta = bpy.path.abspath(ruta)
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=ruta, export_format="GLB", export_extras=True, export_yup=True, export_apply=True,
        export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
        export_skins=True, export_def_bones=False,
        export_vertex_color="NAME", export_vertex_color_name=NOMBRE,
    )
    print("volumen: exportado a", ruta)


if __name__ == "__main__":
    destino = EXPORTAR_A
    if "--" in sys.argv and len(sys.argv) > sys.argv.index("--") + 1:
        destino = sys.argv[sys.argv.index("--") + 1]
    calcular()
    if destino:
        exportar(destino)
