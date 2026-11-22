class_name CamaraOrbital
extends Node3D
## Cámara en tercera persona sobre el hombro: gira con el ratón o el stick derecho,
## se acerca/aleja con la rueda y no atraviesa el terreno ni los objetos (SpringArm3D).
## Va como nodo aparte (top_level) que sigue al objetivo con suavizado.

const DATOS := "res://datos/movimiento.cfg"

@export var objetivo: Node3D

var giro := 0.0          # yaw (radianes)
var inclinacion := -0.3 # pitch (radianes)
var distancia := 4.5

var _c: Dictionary
var _brazo: SpringArm3D
var _camara: Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # se mueve en _process
	_c = DatosCfg.seccion(DATOS, "camara")
	distancia = float(_c.get("distancia", 4.5))
	_brazo = $Brazo
	_camara = $Brazo/Camara
	_brazo.spring_length = distancia
	if objetivo is CollisionObject3D:
		_brazo.add_excluded_object((objetivo as CollisionObject3D).get_rid())
	if objetivo:
		giro = objetivo.rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Pone la cámara de golpe detrás del objetivo (al empezar o al reaparecer).
func saltar_a_objetivo() -> void:
	if objetivo:
		global_position = _foco()
		_brazo.spring_length = distancia


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := float(_c.get("sensibilidad", 0.0025))
		giro -= evento.relative.x * s
		inclinacion -= evento.relative.y * s
		_limitar()
	elif evento.is_action_pressed("acercar"):
		_zoom(-0.5)
	elif evento.is_action_pressed("alejar"):
		_zoom(0.5)
	elif evento.is_action_pressed("soltar_raton"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif evento is InputEventMouseButton and evento.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not UIBuilder.raton_sobre_ui():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# Stick derecho del control
	var sx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var sy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var sc := float(_c.get("sensibilidad_control", 2.6))
	if absf(sx) > 0.15:
		giro -= sx * sc * delta
	if absf(sy) > 0.15:
		inclinacion -= sy * sc * delta
	_limitar()
	if objetivo:
		var suav := float(_c.get("suavizado", 14.0))
		global_position = global_position.lerp(_foco(), 1.0 - exp(-suav * delta))
	rotation = Vector3(inclinacion, giro, 0)
	_brazo.spring_length = lerpf(_brazo.spring_length, distancia, 1.0 - exp(-10.0 * delta))
	_brazo.position.x = float(_c.get("desplazamiento_lateral", 0.45))


## Base de la cámara (sin inclinación) para mover al jugador relativo a la vista.
func base_plana() -> Basis:
	return Basis(Vector3.UP, giro)


func _foco() -> Vector3:
	# La posición interpolada del jugador: así la cámara no tiembla con la interpolación física.
	return objetivo.get_global_transform_interpolated().origin + Vector3.UP * float(_c.get("altura", 1.55))


func _limitar() -> void:
	inclinacion = clampf(inclinacion, deg_to_rad(float(_c.get("inclinacion_min", -70.0))),
			deg_to_rad(float(_c.get("inclinacion_max", 55.0))))


func _zoom(paso: float) -> void:
	distancia = clampf(distancia + paso, float(_c.get("distancia_min", 1.8)), float(_c.get("distancia_max", 9.0)))
