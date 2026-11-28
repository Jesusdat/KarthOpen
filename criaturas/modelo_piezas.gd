class_name ModeloPiezas
extends Node3D
## Modelo de piezas de Karth (los mismos .json de SpriteBaker: nidal, corredor, guardián...)
## armado con ModelBuilder y animado en vivo con sus animaciones (quieto, caminar, atacar).

const ModelBuilder := preload("res://modelos/model_builder.gd")
const ESCALA_CAMARA := 2.7

static var _datos := {}     # ruta -> JSON ya leído (compartido entre criaturas del mismo tipo)
static var _destello: ShaderMaterial

var animacion := "quieto"
var velocidad_anim := 1.0

var _pivotes := {}
var _base := {}
var _anims := {}
var _t := 0.0                # 0..1 dentro de la animación actual
var _congelada := -1.0       # si >= 0, la animación se queda en ese punto (aviso de ataque)
var _mallas: Array = []
var _fin_destello := 0.0


static func crear(ruta: String, escala: float) -> ModeloPiezas:
	if not _datos.has(ruta):
		var d = JSON.parse_string(FileAccess.get_file_as_string(ruta)) if FileAccess.file_exists(ruta) else null
		_datos[ruta] = d if d is Dictionary else {}
	var datos: Dictionary = _datos[ruta]
	if datos.is_empty():
		push_warning("ModeloPiezas: no se pudo leer %s" % ruta)
		return null
	var m := ModeloPiezas.new()
	var armado := ModelBuilder.construir(datos)
	var raiz: Node3D = armado["nodo"]
	raiz.scale = Vector3.ONE * escala / float(datos.get("escala_camara", ESCALA_CAMARA))
	m.add_child(raiz)
	m._pivotes = armado["pivotes"]
	m._base = armado["base"]
	m._anims = datos.get("animaciones", {})
	m._mallas = raiz.find_children("*", "MeshInstance3D", true, false)
	return m


## Cambia de animación (si ya está en esa, no la reinicia salvo que se pida).
func reproducir(nombre: String, velocidad := 1.0, reiniciar := false) -> void:
	velocidad_anim = velocidad
	_congelada = -1.0
	if nombre != animacion or reiniciar:
		animacion = nombre
		_t = 0.0


## Deja la animación quieta en un punto (0..1); sirve para el aviso antes de atacar.
func congelar(nombre: String, t: float) -> void:
	animacion = nombre
	_congelada = clampf(t, 0.0, 1.0)


## Destello blanco breve al recibir un golpe.
func destellar(segundos := 0.1) -> void:
	if _destello == null:
		_destello = ShaderMaterial.new()
		var s := Shader.new()
		s.code = "shader_type spatial;\nrender_mode unshaded, blend_add;\nvoid fragment() { ALBEDO = vec3(0.9, 0.85, 0.8); ALPHA = 0.7; }"
		_destello.shader = s
	for mi in _mallas:
		(mi as MeshInstance3D).material_overlay = _destello
	_fin_destello = segundos


func _process(delta: float) -> void:
	if _fin_destello > 0.0:
		_fin_destello -= delta
		if _fin_destello <= 0.0:
			for mi in _mallas:
				(mi as MeshInstance3D).material_overlay = null
	var anim: Dictionary = _anims.get(animacion, {})
	if anim.is_empty():
		return
	var duracion := maxf(float(anim.get("frames", 1)) / maxf(float(anim.get("fps", 1)), 0.01), 0.05)
	if _congelada >= 0.0:
		_t = _congelada
	else:
		_t += delta * velocidad_anim / duracion
		if bool(anim.get("bucle", true)):
			_t = fposmod(_t, 1.0)
		else:
			_t = minf(_t, 0.999)
	var deltas := ModelBuilder.delta_en(anim, _t)
	for id in _base:
		var pv: Node3D = _pivotes[id]
		var d: Array = deltas.get(id, [Vector3.ZERO, Vector3.ZERO])
		pv.position = _base[id]["pos"] + d[0]
		pv.rotation_degrees = _base[id]["rot"] + d[1]
