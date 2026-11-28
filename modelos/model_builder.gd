extends RefCounted
## Construye un modelo 3D a partir de un JSON de pivotes y piezas, y aplica poses.
##
## Formato del JSON:
##   "materiales": { "id": {"color": "#rrggbb", "emision": "#rrggbb" (opcional),
##                          "zona": "armadura" (opcional: se puede teñir, p. ej. con el color del jugador),
##                          "sombra": 0.7 (opcional: qué tan oscuro queda el tinte en este material)} }
##   "pivotes":    [ {"id", "padre" (por defecto "raiz"), "pos": [x,y,z], "rot": [x,y,z] grados} ]
##                 (un pivote debe aparecer después de su padre)
##   "piezas":     [ {"forma": "caja"|"esfera"|"cono"|"cilindro", "mat", "pivote",
##                    "tam": [x,y,z] (caja), "radio", "alto", "pos", "rot", "escala",
##                    "grupo": "casco" (opcional: pieza de equipo, se puede mostrar u ocultar)} ]
##   "variantes":  { "soldado": ["armadura", "casco"] }  (opcional: combinaciones de grupos que el
##                 horneador saca como hojas aparte, <modelo>_<variante>_bake.png)
##   "animaciones": { "nombre": {"frames", "fps", "bucle", "pistas": [...]} }
##   pista: {"pivote", "prop": "rot_x|rot_y|rot_z|pos_x|pos_y|pos_z",
##           "expr": "sin(ph)*30"  ó  "frames": [v0, v1, v2...]}
##   En "expr" hay tres variables: ph (fase 0..TAU), f (frame actual), n (total de frames).
##   Los valores se SUMAN a la pose base del pivote. Rotaciones en grados.

static var _cache_expr: Dictionary = {}


static func construir(datos: Dictionary) -> Dictionary:
	var raiz := Node3D.new()
	raiz.name = str(datos.get("nombre", "modelo"))
	var pivotes := {"raiz": raiz}
	var base := {}

	for p in datos.get("pivotes", []):
		var n := Node3D.new()
		n.name = str(p["id"])
		n.position = _v3(p.get("pos", [0, 0, 0]))
		n.rotation_degrees = _v3(p.get("rot", [0, 0, 0]))
		var padre: Node3D = pivotes.get(str(p.get("padre", "raiz")), raiz)
		padre.add_child(n)
		pivotes[str(p["id"])] = n
		base[str(p["id"])] = {"pos": n.position, "rot": n.rotation_degrees}

	var mats := {}
	var defs: Dictionary = datos.get("materiales", {})
	for id in defs:
		mats[id] = _material(defs[id])

	var grupos := {}
	for pieza in datos.get("piezas", []):
		var mi := MeshInstance3D.new()
		mi.mesh = _malla(pieza)
		mi.material_override = mats.get(str(pieza.get("mat", "")), _material({"color": "#ff00ff"}))
		mi.position = _v3(pieza.get("pos", [0, 0, 0]))
		mi.rotation_degrees = _v3(pieza.get("rot", [0, 0, 0]))
		mi.scale = _v3(pieza.get("escala", [1, 1, 1]))
		var destino: Node3D = pivotes.get(str(pieza.get("pivote", "raiz")), raiz)
		destino.add_child(mi)
		if pieza.has("grupo"):
			var g := str(pieza["grupo"])
			if not grupos.has(g):
				grupos[g] = []
			grupos[g].append(mi)

	return {"nodo": raiz, "pivotes": pivotes, "base": base, "materiales": mats, "grupos": grupos}


# Muestra solo las piezas de equipo de los grupos indicados (las piezas sin grupo siempre se ven)
static func mostrar_grupos(m: Dictionary, activos: Array) -> void:
	var grupos: Dictionary = m.get("grupos", {})
	for g in grupos:
		for mi in grupos[g]:
			mi.visible = g in activos


static func aplicar_pose(m: Dictionary, anim: Dictionary, f: int) -> void:
	var n := int(anim.get("frames", 1))
	var ph := float(f) / float(n) * TAU
	var base: Dictionary = m["base"]
	var pivotes: Dictionary = m["pivotes"]
	for id in base:
		var pv: Node3D = pivotes[id]
		pv.position = base[id]["pos"]
		pv.rotation_degrees = base[id]["rot"]

	for pista in anim.get("pistas", []):
		var p: Node3D = pivotes.get(str(pista.get("pivote", "")))
		if p == null:
			push_warning("ModelBuilder: pivote desconocido '%s'" % pista.get("pivote", ""))
			continue
		var v := 0.0
		if pista.has("frames"):
			var vals: Array = pista["frames"]
			v = float(vals[f % vals.size()])
		else:
			v = _evaluar(str(pista.get("expr", "0")), ph, f, n)
		match str(pista.get("prop", "")):
			"rot_x": p.rotation_degrees.x += v
			"rot_y": p.rotation_degrees.y += v
			"rot_z": p.rotation_degrees.z += v
			"pos_x": p.position.x += v
			"pos_y": p.position.y += v
			"pos_z": p.position.z += v
			_: push_warning("ModelBuilder: propiedad desconocida '%s'" % pista.get("prop", ""))


# Lo mismo que aplicar_pose, pero sin tocar el modelo y en cualquier momento de la
# animación (t de 0 a 1, no solo en cuadros enteros). Devuelve cuánto se mueve cada
# pivote respecto a su pose base:  { id: [Vector3 posición, Vector3 rotación en grados] }.
# Lo usa la vista 3D del juego para animar los modelos en vivo.
static func delta_en(anim: Dictionary, t: float) -> Dictionary:
	var n := maxi(int(anim.get("frames", 1)), 1)
	var x := t * float(n)
	var f := int(floor(x + 0.00001))
	var resto := clampf(x - float(f), 0.0, 1.0)
	var bucle := bool(anim.get("bucle", true))
	var out := {}
	for pista in anim.get("pistas", []):
		var id := str(pista.get("pivote", ""))
		var v := 0.0
		if pista.has("frames"):
			var vals: Array = pista["frames"]
			if vals.is_empty():
				continue
			var a := float(vals[f % vals.size()])
			var sig := (f + 1) % vals.size() if bucle else mini(f + 1, vals.size() - 1)
			v = lerpf(a, float(vals[sig]), resto)
		else:
			v = _evaluar(str(pista.get("expr", "0")), t * TAU, f, n)
		if not out.has(id):
			out[id] = [Vector3.ZERO, Vector3.ZERO]
		var d: Array = out[id]
		match str(pista.get("prop", "")):
			"rot_x": d[1].x += v
			"rot_y": d[1].y += v
			"rot_z": d[1].z += v
			"pos_x": d[0].x += v
			"pos_y": d[0].y += v
			"pos_z": d[0].z += v
	return out


static func _evaluar(texto: String, ph: float, f: int, n: int) -> float:
	var e: Expression = _cache_expr.get(texto)
	if e == null:
		e = Expression.new()
		if e.parse(texto, PackedStringArray(["ph", "f", "n"])) != OK:
			push_warning("ModelBuilder: expresión inválida '%s': %s" % [texto, e.get_error_text()])
			return 0.0
		_cache_expr[texto] = e
	var r = e.execute([ph, f, n], null, false)
	if e.has_execute_failed():
		return 0.0
	return float(r)


static func _malla(pieza: Dictionary) -> Mesh:
	var radio := float(pieza.get("radio", 0.5))
	var alto := float(pieza.get("alto", 1.0))
	match str(pieza.get("forma", "caja")):
		"esfera":
			var s := SphereMesh.new()
			s.radius = radio
			s.height = radio * 2.0
			s.radial_segments = 10
			s.rings = 6
			return s
		"cono":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = radio
			c.height = alto
			c.radial_segments = 6
			return c
		"cilindro":
			var c2 := CylinderMesh.new()
			c2.top_radius = radio
			c2.bottom_radius = radio
			c2.height = alto
			c2.radial_segments = 8
			return c2
		_:
			var b := BoxMesh.new()
			b.size = _v3(pieza.get("tam", [1, 1, 1]))
			return b


static func _material(d: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(str(d.get("color", "#ffffff")))
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.0
	if d.has("emision"):
		m.emission_enabled = true
		m.emission = Color(str(d["emision"]))
	return m


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
