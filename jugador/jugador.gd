class_name Jugador
extends CharacterBody3D
## Jugador en tercera persona: caminar, correr, saltar y esquivar, con estamina.
## Todos los números salen de datos/movimiento.cfg. Escribe su estado en UIBuilder
## (jugador.vida, jugador.estamina...) para que el HUD se actualice solo.

signal esquivo
signal aterrizo(velocidad_caida: float)

const DATOS := "res://datos/movimiento.cfg"

enum Estado { NORMAL, ESQUIVANDO }

@export var camara: CamaraOrbital

var estado := Estado.NORMAL
var vida := 100.0
var vida_max := 100.0
var estamina := 100.0
var estamina_max := 100.0
var corriendo := false
var invulnerable := false     # lo usará el combate (ventana de la esquiva)

var _m: Dictionary
var _e: Dictionary
var _s: Dictionary
var _inicio := Vector3.ZERO
var _coyote := 0.0
var _buffer_salto := 0.0
var _espera_estamina := 0.0
var _t_esquiva := 0.0
var _recarga_esquiva := 0.0
var _dir_esquiva := Vector3.ZERO
var _esquiva_atras := false
var _vel_y_previa := 0.0
var _agotado := false         # sin estamina: no corre hasta soltar Shift

@onready var modelo: Node3D = $Modelo
var _anim: AnimationPlayer


func _ready() -> void:
	# Animaciones del colono de Karth (quieto, caminar, golpe, apuntar)
	var lista := modelo.find_children("*", "AnimationPlayer", true, false)
	if not lista.is_empty():
		_anim = lista[0]
		for nombre in ["quieto", "caminar"]:
			if _anim.has_animation(nombre):
				_anim.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	_m = DatosCfg.seccion(DATOS, "jugador")
	_e = DatosCfg.seccion(DATOS, "esquiva")
	_s = DatosCfg.seccion(DATOS, "estamina")
	estamina_max = float(_s.get("maxima", 100.0))
	estamina = estamina_max
	_inicio = global_position
	_publicar()


## Coloca al jugador y recuerda ese punto como inicio (para cuando cae del mapa).
func colocar(punto: Vector3) -> void:
	global_position = punto
	_inicio = punto
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	if camara:
		camara.saltar_a_objetivo()


func _physics_process(delta: float) -> void:
	var entrada := Input.get_vector("izquierda", "derecha", "adelante", "atras")
	var base := camara.base_plana() if camara else Basis.IDENTITY
	var dir := (base * Vector3(entrada.x, 0, entrada.y))
	if dir.length() > 1.0:
		dir = dir.normalized()

	_timers(delta)

	match estado:
		Estado.NORMAL:
			_mover(dir, delta)
			if Input.is_action_just_pressed("esquivar"):
				_intentar_esquiva(dir)
		Estado.ESQUIVANDO:
			_esquivando(delta)

	# gravedad
	if not is_on_floor():
		velocity.y -= float(_m.get("gravedad", 16.0)) * delta

	_vel_y_previa = velocity.y
	var estaba_en_aire := not is_on_floor()
	move_and_slide()
	if estaba_en_aire and is_on_floor():
		aterrizo.emit(-_vel_y_previa)

	if global_position.y < float(_m.get("caida_reinicio", -60.0)):
		colocar(_inicio)

	_estamina(delta)
	_animar()
	_publicar()


func _animar() -> void:
	if _anim == null:
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var nombre := "caminar" if horizontal > 0.3 or estado == Estado.ESQUIVANDO else "quieto"
	if _anim.has_animation(nombre) and _anim.current_animation != nombre:
		_anim.play(nombre, 0.15)
	_anim.speed_scale = clampf(horizontal / float(_m.get("velocidad_caminar", 4.0)), 0.6, 2.2) if nombre == "caminar" else 1.0


func _mover(dir: Vector3, delta: float) -> void:
	var en_suelo := is_on_floor()
	var quiere_correr := Input.is_action_pressed("correr") and dir.length() > 0.1
	if not Input.is_action_pressed("correr"):
		_agotado = false
	if quiere_correr and not corriendo and estamina < float(_s.get("minima_correr", 5.0)):
		quiere_correr = false
	corriendo = quiere_correr and not _agotado and estamina > 0.0

	var vel_max := float(_m.get("velocidad_correr" if corriendo else "velocidad_caminar", 4.0))
	var objetivo := dir * vel_max
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var acel := float(_m.get("aceleracion", 40.0)) if dir.length() > 0.05 else float(_m.get("frenado", 50.0))
	if not en_suelo:
		acel *= float(_m.get("control_en_aire", 0.3))
	horizontal = horizontal.move_toward(objetivo, acel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if dir.length() > 0.05:
		_girar_hacia(dir, delta)

	# salto con coyote y buffer
	if Input.is_action_just_pressed("saltar"):
		_buffer_salto = float(_m.get("buffer_salto", 0.12))
	if _buffer_salto > 0.0 and _coyote > 0.0 and estamina >= float(_s.get("salto", 10.0)) * 0.5:
		velocity.y = float(_m.get("salto", 5.2))
		_gastar(float(_s.get("salto", 10.0)))
		_buffer_salto = 0.0
		_coyote = 0.0


func _intentar_esquiva(dir: Vector3) -> void:
	if _recarga_esquiva > 0.0 or not is_on_floor():
		return
	var costo := float(_s.get("esquiva", 22.0))
	if estamina < costo * 0.5:
		return
	_gastar(costo)
	# sin dirección: esquiva hacia atrás, como en los souls
	_esquiva_atras = dir.length() <= 0.1
	_dir_esquiva = modelo.global_basis.z.normalized() if _esquiva_atras else dir.normalized()
	_t_esquiva = float(_e.get("duracion", 0.45))
	estado = Estado.ESQUIVANDO
	invulnerable = true
	esquivo.emit()


func _esquivando(delta: float) -> void:
	var dur := float(_e.get("duracion", 0.45))
	var avance := 1.0 - _t_esquiva / dur          # 0 → 1
	var vel := float(_e.get("velocidad", 10.0)) * (1.0 - avance * avance * 0.7)
	velocity.x = _dir_esquiva.x * vel
	velocity.z = _dir_esquiva.z * vel
	invulnerable = (dur - _t_esquiva) < float(_e.get("invulnerable", 0.3))
	if not _esquiva_atras:
		_girar_hacia(_dir_esquiva, delta)
	_t_esquiva -= delta
	if _t_esquiva <= 0.0:
		estado = Estado.NORMAL
		invulnerable = false
		_recarga_esquiva = float(_e.get("recarga", 0.15))


func _girar_hacia(dir: Vector3, delta: float) -> void:
	# El modelo mira hacia -Z: el ángulo objetivo apunta su frente a dir.
	var angulo := atan2(-dir.x, -dir.z)
	modelo.rotation.y = lerp_angle(modelo.rotation.y, angulo, 1.0 - exp(-float(_m.get("giro", 12.0)) * delta))


func _timers(delta: float) -> void:
	if is_on_floor():
		_coyote = float(_m.get("coyote", 0.12))
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	_buffer_salto = maxf(_buffer_salto - delta, 0.0)
	_recarga_esquiva = maxf(_recarga_esquiva - delta, 0.0)


func _estamina(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if corriendo and horizontal > 0.5 and is_on_floor():
		_gastar(float(_s.get("correr", 16.0)) * delta)
		if estamina <= 0.0:
			_agotado = true
			corriendo = false
	elif _espera_estamina > 0.0:
		_espera_estamina -= delta
	else:
		estamina = minf(estamina + float(_s.get("regeneracion", 28.0)) * delta, estamina_max)


func _gastar(cantidad: float) -> void:
	estamina = maxf(estamina - cantidad, 0.0)
	_espera_estamina = float(_s.get("espera", 0.8))


func _publicar() -> void:
	UIBuilder.estado.fusionar("jugador", {
		"vida": roundi(vida), "vida_max": roundi(vida_max),
		"estamina": roundi(estamina), "estamina_max": roundi(estamina_max),
	})
