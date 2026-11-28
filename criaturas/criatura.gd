class_name Criatura
extends CharacterBody3D
## Criatura enemiga en tiempo real. Todo sale de datos/criaturas.cfg (y el nombre de
## datos/monstruos.cfg). Ciclo: ronda cerca de su guarida → te ve → te persigue →
## elige un ataque según la distancia → aviso (preparación) → golpe → recuperación.
## Si le bajas el aguante queda aturdida; si se aleja mucho de su guarida, regresa y se cura.

signal murio(criatura: Criatura)
signal herida(criatura: Criatura)

const DATOS := "res://datos/criaturas.cfg"
const MONSTRUOS := "res://datos/monstruos.cfg"

enum Estado { RONDA, PERSIGUE, PREPARA, ATACA, RECUPERA, ATURDIDA, REGRESA, MUERTA }

var tipo := "nidal"
var nombre := "Nidal"
var vivo := true
var vida := 60.0
var vida_max := 60.0
var aguante := 40.0
var aguante_max := 40.0
var estado := Estado.RONDA
var guarida := Vector3.ZERO      # su punto de origen
var radio_golpe := 0.6           # lo usa Golpe.aplicar_en_area
var alto_golpe := 1.1

var _d: Dictionary
var _ataques: Array = []         # [{nombre, datos}]
var _ataque: Dictionary = {}     # ataque en curso
var _t := 0.0                    # tiempo en el estado actual
var _esperas := {}               # ataque -> segundos para poder repetirlo
var _ya_golpeados := {}
var _objetivo: Node3D
var _modelo: ModeloPiezas
var _destino_ronda := Vector3.ZERO
var _sin_golpes := 0.0
var _dir_ataque := Vector3.FORWARD
var _gravedad := 16.0


## Prepara la criatura desde los datos. Llamar antes de añadirla al árbol.
func configurar(tipo_criatura: String, punto_guarida: Vector3) -> void:
	tipo = tipo_criatura
	guarida = punto_guarida
	_d = DatosCfg.seccion(DATOS, tipo)
	var base := String(_d.get("base", tipo))
	nombre = String(DatosCfg.valor(MONSTRUOS, base, "name", tipo.capitalize()))
	vida_max = float(_d.get("vida", 60.0))
	vida = vida_max
	aguante_max = float(_d.get("aguante", 40.0))
	aguante = aguante_max
	radio_golpe = float(_d.get("radio", 0.6))
	alto_golpe = float(_d.get("alto", 1.1))
	_ataques.clear()
	for a in _d.get("ataques", []):
		_ataques.append({"nombre": String(a), "datos": DatosCfg.seccion(DATOS, String(a))})


func _ready() -> void:
	add_to_group("criaturas")
	collision_layer = 4          # capa 3: criaturas
	collision_mask = 1 | 4       # mundo y otras criaturas (al jugador lo empujan los golpes, no el cuerpo)
	floor_snap_length = 0.4
	var forma := CapsuleShape3D.new()
	forma.radius = radio_golpe
	forma.height = maxf(alto_golpe, radio_golpe * 2.0)
	var col := CollisionShape3D.new()
	col.shape = forma
	col.position.y = forma.height * 0.5
	add_child(col)
	_modelo = ModeloPiezas.crear(String(_d.get("modelo", "res://modelos/nidal.json")), float(_d.get("escala", 1.9)))
	if _modelo:
		_modelo.rotation_degrees.y = float(_d.get("giro_modelo", 180.0))
		var pivote := Node3D.new()
		pivote.name = "Giro"
		add_child(pivote)
		pivote.add_child(_modelo)
	_nuevo_destino_ronda()


func _physics_process(delta: float) -> void:
	_t += delta
	for k in _esperas.keys():
		_esperas[k] = maxf(_esperas[k] - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravedad * delta
	if _objetivo == null or not is_instance_valid(_objetivo):
		_objetivo = get_tree().get_first_node_in_group("jugador") as Node3D

	# el aguante vuelve si no le pegan
	_sin_golpes += delta
	if _sin_golpes > 1.5 and estado != Estado.ATURDIDA:
		aguante = minf(aguante + float(_d.get("recupera_aguante", 12.0)) * delta, aguante_max)

	match estado:
		Estado.RONDA: _ronda(delta)
		Estado.PERSIGUE: _persigue(delta)
		Estado.PREPARA: _prepara(delta)
		Estado.ATACA: _ataca(delta)
		Estado.RECUPERA: _recupera(delta)
		Estado.ATURDIDA: _aturdida(delta)
		Estado.REGRESA: _regresa(delta)
		Estado.MUERTA:
			velocity.x = move_toward(velocity.x, 0, 20 * delta)
			velocity.z = move_toward(velocity.z, 0, 20 * delta)
	move_and_slide()


# ================================================================ estados

func _ronda(delta: float) -> void:
	if _ve_al_objetivo():
		_cambiar(Estado.PERSIGUE)
		return
	var hacia := _destino_ronda - global_position
	hacia.y = 0
	if hacia.length() < 0.8 or _t > 8.0:
		_frenar(delta)
		if _t > 2.5:
			_nuevo_destino_ronda()
			_t = 0.0
		_anim("quieto")
	else:
		_caminar_hacia(hacia.normalized(), float(_d.get("velocidad_patrulla", 1.1)), delta)
		_anim("caminar", 0.7)


func _persigue(delta: float) -> void:
	if not _objetivo_vivo():
		_cambiar(Estado.REGRESA)
		return
	if _lejos_de_casa():
		_cambiar(Estado.REGRESA)
		return
	var hacia := _objetivo.global_position - global_position
	hacia.y = 0
	var dist := hacia.length()
	var ataque := _elegir_ataque(dist)
	if not ataque.is_empty():
		_ataque = ataque
		_dir_ataque = hacia.normalized() if dist > 0.01 else -global_basis.z
		_cambiar(Estado.PREPARA)
		Efectos.sonido("aviso", global_position + Vector3.UP)
		return
	var dir := hacia.normalized() + _separacion() * 0.6
	_caminar_hacia(dir.normalized(), float(_d.get("velocidad", 3.4)), delta)
	_anim("caminar", 1.3)


func _prepara(delta: float) -> void:
	_frenar(delta)
	var a: Dictionary = _ataque["datos"]
	var prep := float(a.get("preparacion", 0.6))
	# sigue apuntando al jugador durante el aviso, pero cada vez más lento
	if _objetivo_vivo():
		var hacia := _objetivo.global_position - global_position
		hacia.y = 0
		if hacia.length() > 0.1:
			_dir_ataque = _dir_ataque.slerp(hacia.normalized(), clampf(delta * 6.0 * (1.0 - _t / prep), 0.0, 1.0)).normalized()
	_mirar(_dir_ataque, delta, 3.0)
	if _modelo:
		_modelo.congelar("atacar", 0.33 * clampf(_t / prep, 0.0, 1.0))
	if _t >= prep:
		_ya_golpeados.clear()
		var avance := float(a.get("avance", 3.0))
		velocity.x = _dir_ataque.x * avance
		velocity.z = _dir_ataque.z * avance
		if a.has("salto"):
			velocity.y = float(a["salto"])
		_cambiar(Estado.ATACA)
		if _modelo:
			_modelo.reproducir("atacar", 2.0, true)


func _ataca(delta: float) -> void:
	var a: Dictionary = _ataque["datos"]
	if not a.has("salto"):
		velocity.x = move_toward(velocity.x, 0, 10 * delta)
		velocity.z = move_toward(velocity.z, 0, 10 * delta)
	var centro := global_position + Vector3.UP * alto_golpe * 0.5 + _dir_ataque * float(a.get("alcance", 1.2))
	var golpe := {"dano": float(a.get("dano", 10.0)), "aturdir": 0.0, "empuje": 5.0,
			"origen": self, "fuerte": a.has("salto")}
	var res := Golpe.aplicar_en_area(get_tree(), "jugador", centro, float(a.get("radio", 1.0)), golpe, _ya_golpeados)
	for r in res:
		if r["resultado"] in ["dano", "muerto"]:
			Efectos.sonido("golpe_enjambre", r["punto"])
			Efectos.efecto("golpe_enjambre", r["punto"])
		elif r["resultado"] in ["bloqueado", "guardia_rota"]:
			# rebota en el bloqueo: recupera más largo
			_t = 0.0
			_esperas[_ataque["nombre"]] = float(a.get("espera", 0.0))
			_cambiar(Estado.RECUPERA)
			_t = -0.3
			return
	if _t >= float(a.get("activo", 0.15)) and (is_on_floor() or _t > 1.5):
		_esperas[_ataque["nombre"]] = float(a.get("espera", 0.0))
		_cambiar(Estado.RECUPERA)


func _recupera(delta: float) -> void:
	_frenar(delta)
	_anim("quieto")
	if _t >= float(_ataque.get("datos", {}).get("recuperacion", 0.7)):
		_cambiar(Estado.PERSIGUE)


func _aturdida(delta: float) -> void:
	_frenar(delta * 0.5)
	if _modelo:
		_modelo.reproducir("quieto", 0.3)
	if _t >= float(_d.get("aturdido", 1.2)):
		aguante = aguante_max
		_cambiar(Estado.PERSIGUE)


func _regresa(delta: float) -> void:
	var hacia := guarida - global_position
	hacia.y = 0
	vida = minf(vida + vida_max * 0.25 * delta, vida_max)
	herida.emit(self)
	if hacia.length() < 2.0:
		vida = vida_max
		_cambiar(Estado.RONDA)
		return
	_caminar_hacia(hacia.normalized(), float(_d.get("velocidad", 3.4)), delta)
	_anim("caminar", 1.3)


# ================================================================ recibir golpes

func recibir_golpe(golpe: Dictionary) -> String:
	if not vivo:
		return ""
	vida -= float(golpe.get("dano", 0.0))
	_sin_golpes = 0.0
	herida.emit(self)
	if _modelo:
		_modelo.destellar()
	var origen := golpe.get("origen") as Node3D
	var empuje := Vector3.ZERO
	if origen:
		empuje = global_position - origen.global_position
		empuje.y = 0
		empuje = empuje.normalized() * float(golpe.get("empuje", 1.0))
	if vida <= 0.0:
		_morir(empuje)
		return "muerto"
	velocity.x += empuje.x
	velocity.z += empuje.z
	# si estaba tranquila o regresando, ahora te persigue
	if estado in [Estado.RONDA, Estado.REGRESA]:
		_cambiar(Estado.PERSIGUE)
	aguante -= float(golpe.get("aturdir", 0.0))
	if aguante <= 0.0 and estado != Estado.ATURDIDA:
		_cambiar(Estado.ATURDIDA)
		Efectos.numero("¡Aturdido!", global_position + Vector3.UP * (alto_golpe + 0.6), Color(1, 0.85, 0.3))
	return "dano"


func _morir(empuje: Vector3) -> void:
	vivo = false
	vida = 0.0
	velocity = empuje * 1.5 + Vector3.UP * 2.0
	_cambiar(Estado.MUERTA)
	collision_layer = 0
	Efectos.sonido("muerte_enjambre", global_position)
	Efectos.efecto("muerte_enjambre", global_position + Vector3.UP * 0.5)
	murio.emit(self)
	if _modelo:
		_modelo.reproducir("quieto", 0.0)
		var t := create_tween()
		t.tween_interval(0.6)
		t.tween_property(_modelo, "scale", Vector3(1.2, 0.05, 1.2), 0.5).set_ease(Tween.EASE_IN)
		t.tween_callback(queue_free)
	else:
		queue_free()


# ================================================================ ayudas

func _cambiar(nuevo: Estado) -> void:
	estado = nuevo
	_t = 0.0


func _elegir_ataque(dist: float) -> Dictionary:
	var opciones := []
	var total := 0
	for a in _ataques:
		var d: Dictionary = a["datos"]
		if _esperas.get(a["nombre"], 0.0) > 0.0:
			continue
		if dist >= float(d.get("distancia_min", 0.0)) and dist <= float(d.get("distancia_max", 2.0)):
			opciones.append(a)
			total += int(d.get("peso", 1))
	if opciones.is_empty():
		return {}
	var r := randi() % total
	for a in opciones:
		r -= int(a["datos"].get("peso", 1))
		if r < 0:
			return a
	return opciones[0]


func _ve_al_objetivo() -> bool:
	if not _objetivo_vivo():
		return false
	return global_position.distance_to(_objetivo.global_position) <= float(_d.get("vision", 15.0)) \
			and guarida.distance_to(_objetivo.global_position) <= float(_d.get("correa", 30.0))


func _objetivo_vivo() -> bool:
	return _objetivo != null and is_instance_valid(_objetivo) and bool(_objetivo.get("vivo"))


func _lejos_de_casa() -> bool:
	return Vector2(global_position.x - guarida.x, global_position.z - guarida.z).length() > float(_d.get("correa", 30.0))


func _caminar_hacia(dir: Vector3, vel: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, dir.x * vel, 20.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * vel, 20.0 * delta)
	_mirar(dir, delta, float(_d.get("giro", 8.0)))


func _frenar(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 18.0 * delta)
	velocity.z = move_toward(velocity.z, 0, 18.0 * delta)


func _mirar(dir: Vector3, delta: float, rapidez: float) -> void:
	if dir.length() < 0.01:
		return
	var angulo := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, angulo, 1.0 - exp(-rapidez * delta))


## Empuje suave para que no se encimen varias criaturas.
func _separacion() -> Vector3:
	var s := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("criaturas"):
		if n == self or not is_instance_valid(n):
			continue
		var d: Vector3 = global_position - (n as Node3D).global_position
		d.y = 0
		var l := d.length()
		if l > 0.01 and l < radio_golpe * 3.0:
			s += d / l * (1.0 - l / (radio_golpe * 3.0))
	return s


func _nuevo_destino_ronda() -> void:
	var a := randf() * TAU
	var r := randf_range(2.0, 7.0)
	_destino_ronda = guarida + Vector3(cos(a) * r, 0, sin(a) * r)


func _anim(nombre_anim: String, vel := 1.0) -> void:
	if _modelo:
		_modelo.reproducir(nombre_anim, vel)
