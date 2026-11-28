class_name Jugador
extends CharacterBody3D
## Jugador en tercera persona: moverse, correr, saltar, esquivar y pelear cuerpo a cuerpo
## (combo ligero, ataque pesado cargado, bloqueo y fijar objetivo), con vida y estamina.
## Los números salen de datos/movimiento.cfg y datos/combate.cfg. Publica su estado en
## UIBuilder (jugador.*, objetivo.*, aviso.*) para que el HUD se actualice solo.

signal esquivo
signal aterrizo(velocidad_caida: float)
signal golpeo(resultado: Dictionary)
signal murio
signal revivio

const DATOS := "res://datos/movimiento.cfg"
const COMBATE := "res://datos/combate.cfg"

enum Estado { NORMAL, ESQUIVANDO, ATACANDO, ATURDIDO, MUERTO }

@export var camara: CamaraOrbital

var estado := Estado.NORMAL
var vivo := true
var vida := 100.0
var vida_max := 100.0
var estamina := 100.0
var estamina_max := 100.0
var corriendo := false
var bloqueando := false
var invulnerable := false        # ventana de la esquiva
var fijado: Node3D               # enemigo fijado (o null)
var radio_golpe := 0.35          # para Golpe.aplicar_en_area
var alto_golpe := 1.8

# movimiento
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
var _agotado := false            # sin estamina: no corre hasta soltar Shift

# combate
var _c: Dictionary               # secciones de combate.cfg
var _ataque := {}                # {tipo, datos, t, dir, combo, ya}
var _cargando := false
var _t_carga := 0.0
var _combo_pedido := false
var _combo := 0                  # golpe del combo que sigue (0, 1, 2)
var _t_desde_ataque := 99.0
var _t_aturdido := 0.0
var _inv_golpe := 0.0
var _t_muerto := 0.0
var _ultimo_golpeado: Node3D
var _t_mostrar_objetivo := 0.0

@onready var modelo: Node3D = $Modelo
var _anim: AnimationPlayer


func _ready() -> void:
	add_to_group("jugador")
	collision_layer = 2          # capa 2: jugador
	collision_mask = 1 | 4       # choca con el mundo y con las criaturas
	# Animaciones del colono de Karth (quieto, caminar, golpe, apuntar)
	var lista := modelo.find_children("*", "AnimationPlayer", true, false)
	if not lista.is_empty():
		_anim = lista[0]
		for nombre in ["quieto", "caminar", "apuntar"]:
			if _anim.has_animation(nombre):
				_anim.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
	_m = DatosCfg.seccion(DATOS, "jugador")
	_e = DatosCfg.seccion(DATOS, "esquiva")
	_s = DatosCfg.seccion(DATOS, "estamina")
	for sec in ["jugador", "ataque_ligero", "ataque_pesado", "bloqueo", "fijar", "sensacion"]:
		_c[sec] = DatosCfg.seccion(COMBATE, sec)
	estamina_max = float(_s.get("maxima", 100.0))
	estamina = estamina_max
	vida_max = float(_c["jugador"].get("vida", 100.0))
	vida = vida_max
	_inicio = global_position
	_publicar()


## Coloca al jugador y recuerda ese punto como inicio (para cuando cae o muere).
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
	_revisar_fijado()
	if estado != Estado.MUERTO and Input.is_action_just_pressed("fijar"):
		alternar_fijar()

	bloqueando = estado == Estado.NORMAL and Input.is_action_pressed("bloquear") and is_on_floor()

	match estado:
		Estado.NORMAL:
			_mover(dir, delta)
			_entrada_ataque(delta)
			if estado == Estado.NORMAL and Input.is_action_just_pressed("esquivar"):
				_intentar_esquiva(dir)
		Estado.ESQUIVANDO:
			_esquivando(delta)
		Estado.ATACANDO:
			_entrada_ataque(delta)
			_atacando(delta, dir)
		Estado.ATURDIDO:
			_frenar(delta, 12.0)
			_t_aturdido -= delta
			if _t_aturdido <= 0.0:
				estado = Estado.NORMAL
		Estado.MUERTO:
			_frenar(delta, 20.0)
			_t_muerto += delta
			if _t_muerto >= float(_c["jugador"].get("reaparecer", 3.0)):
				revivir()

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


# ================================================================ movimiento

func _mover(dir: Vector3, delta: float) -> void:
	var en_suelo := is_on_floor()
	var quiere_correr := Input.is_action_pressed("correr") and dir.length() > 0.1 and not bloqueando
	if not Input.is_action_pressed("correr"):
		_agotado = false
	if quiere_correr and not corriendo and estamina < float(_s.get("minima_correr", 5.0)):
		quiere_correr = false
	corriendo = quiere_correr and not _agotado and estamina > 0.0

	var vel_max := float(_m.get("velocidad_correr" if corriendo else "velocidad_caminar", 4.0))
	if bloqueando:
		vel_max *= float(_c["bloqueo"].get("velocidad", 0.45))
	var objetivo := dir * vel_max
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var acel := float(_m.get("aceleracion", 40.0)) if dir.length() > 0.05 else float(_m.get("frenado", 50.0))
	if not en_suelo:
		acel *= float(_m.get("control_en_aire", 0.3))
	horizontal = horizontal.move_toward(objetivo, acel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Con un enemigo fijado (y sin correr) se camina de lado mirándolo.
	if fijado and not corriendo:
		_girar_hacia(_hacia_fijado(), delta)
	elif dir.length() > 0.05:
		_girar_hacia(dir, delta)

	# salto con coyote y buffer
	if Input.is_action_just_pressed("saltar") and not bloqueando:
		_buffer_salto = float(_m.get("buffer_salto", 0.12))
	if _buffer_salto > 0.0 and _coyote > 0.0 and estamina >= float(_s.get("salto", 10.0)) * 0.5:
		velocity.y = float(_m.get("salto", 5.2))
		_gastar(float(_s.get("salto", 10.0)))
		_buffer_salto = 0.0
		_coyote = 0.0


func _intentar_esquiva(dir: Vector3) -> bool:
	if _recarga_esquiva > 0.0 or not is_on_floor():
		return false
	var costo := float(_s.get("esquiva", 22.0))
	if estamina < costo * 0.5:
		return false
	_gastar(costo)
	# sin dirección: paso hacia atrás, como en los souls
	_esquiva_atras = dir.length() <= 0.1
	_dir_esquiva = modelo.global_basis.z.normalized() if _esquiva_atras else dir.normalized()
	_t_esquiva = float(_e.get("duracion", 0.45))
	estado = Estado.ESQUIVANDO
	invulnerable = true
	_ataque = {}
	Efectos.sonido("esquive_colonos", global_position)
	esquivo.emit()
	return true


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


func _girar_hacia(dir: Vector3, delta: float, rapidez := -1.0) -> void:
	if dir.length() < 0.01:
		return
	# El modelo mira hacia -Z: el ángulo objetivo apunta su frente a dir.
	var angulo := atan2(-dir.x, -dir.z)
	var r := float(_m.get("giro", 12.0)) if rapidez < 0.0 else rapidez
	modelo.rotation.y = lerp_angle(modelo.rotation.y, angulo, 1.0 - exp(-r * delta))


func _frenar(delta: float, fuerza: float) -> void:
	velocity.x = move_toward(velocity.x, 0, fuerza * delta)
	velocity.z = move_toward(velocity.z, 0, fuerza * delta)


## Hacia dónde mira el modelo (en el plano).
func frente() -> Vector3:
	var f := -modelo.global_basis.z
	f.y = 0
	return f.normalized()


# ================================================================ ataques

func _entrada_ataque(delta: float) -> void:
	if Input.is_action_just_pressed("atacar"):
		_cargando = true
		_t_carga = 0.0
	if _cargando:
		if Input.is_action_pressed("atacar"):
			_t_carga += delta
			if _t_carga >= float(_c["ataque_pesado"].get("carga", 0.35)) and estado == Estado.NORMAL:
				_cargando = false
				_empezar_ataque("pesado")
		else:
			_cargando = false
			if estado == Estado.NORMAL:
				_empezar_ataque("ligero")
			elif estado == Estado.ATACANDO:
				_combo_pedido = true


func _empezar_ataque(tipo: String) -> void:
	if estamina <= 0.0 or not is_on_floor():
		return
	var datos: Dictionary = _c["ataque_" + tipo]
	if tipo == "ligero":
		var ventana := float(datos.get("ventana_combo", 0.3))
		if _t_desde_ataque > ventana + 0.15:
			_combo = 0
	else:
		_combo = 0
	_gastar(float(datos.get("estamina", 12.0)))
	# dirección: al fijado, si no hacia donde empujas el stick, si no al frente
	var entrada := Input.get_vector("izquierda", "derecha", "adelante", "atras")
	var dir := frente()
	if fijado:
		dir = _hacia_fijado()
	elif entrada.length() > 0.2 and camara:
		dir = (camara.base_plana() * Vector3(entrada.x, 0, entrada.y)).normalized()
	modelo.rotation.y = atan2(-dir.x, -dir.z)
	_ataque = {"tipo": tipo, "datos": datos, "t": 0.0, "dir": dir, "combo": _combo, "ya": {}}
	_combo_pedido = false
	estado = Estado.ATACANDO
	corriendo = false
	if _anim and _anim.has_animation("golpe"):
		var total := float(datos.get("preparacion", 0.1)) + float(datos.get("activo", 0.1)) + float(datos.get("recuperacion", 0.3)) * 0.5
		_anim.play("golpe", 0.05)
		_anim.seek(0.0, true)
		_anim.speed_scale = _anim.get_animation("golpe").length / maxf(total, 0.05)


func _atacando(delta: float, dir_entrada: Vector3) -> void:
	var a: Dictionary = _ataque["datos"]
	var t: float = _ataque["t"] + delta
	_ataque["t"] = t
	var prep := float(a.get("preparacion", 0.12))
	var activo := float(a.get("activo", 0.12))
	var rec := float(a.get("recuperacion", 0.3))
	var dir: Vector3 = _ataque["dir"]

	# avance: un impulso hacia adelante que se apaga al terminar la fase activa
	if t < prep + activo:
		var fuerza := float(a.get("avance", 2.5)) * (1.0 - t / (prep + activo))
		velocity.x = dir.x * fuerza
		velocity.z = dir.z * fuerza
	else:
		_frenar(delta, 30.0)

	if t >= prep and t < prep + activo:
		_golpear(a)

	var fin := prep + activo + rec
	# Al final de la recuperación se puede esquivar o encadenar el combo.
	if t >= prep + activo + rec * 0.4:
		if Input.is_action_just_pressed("esquivar"):
			estado = Estado.NORMAL
			if _intentar_esquiva(dir_entrada):
				return
			estado = Estado.ATACANDO
		var ventana := float(a.get("ventana_combo", 0.0))
		if _combo_pedido and _ataque["tipo"] == "ligero" and t >= fin - ventana:
			var combos: Array = a.get("combo", [1.0])
			_combo = (int(_ataque["combo"]) + 1) % combos.size()
			_t_desde_ataque = 0.0
			estado = Estado.NORMAL
			_empezar_ataque("ligero")
			return
	if t >= fin:
		if _ataque["tipo"] == "ligero":
			var combos: Array = a.get("combo", [1.0])
			_combo = (int(_ataque["combo"]) + 1) % combos.size()
		_t_desde_ataque = 0.0
		_ataque = {}
		estado = Estado.NORMAL
		if _combo_pedido:
			_combo_pedido = false
			_empezar_ataque("ligero")


func _golpear(a: Dictionary) -> void:
	var dir: Vector3 = _ataque["dir"]
	var combos: Array = a.get("combo", [1.0])
	var mult := float(combos[int(_ataque["combo"]) % combos.size()]) if not combos.is_empty() else 1.0
	var fuerte: bool = _ataque["tipo"] == "pesado"
	var golpe := {
		"dano": float(a.get("dano", 10.0)) * mult,
		"aturdir": float(a.get("aturdir", 10.0)) * mult,
		"empuje": float(a.get("empuje", 1.5)),
		"origen": self, "fuerte": fuerte,
	}
	var centro := global_position + Vector3.UP * 1.0 + dir * float(a.get("alcance", 1.3))
	var res := Golpe.aplicar_en_area(get_tree(), "criaturas", centro, float(a.get("radio", 1.2)), golpe, _ataque["ya"])
	var sens: Dictionary = _c["sensacion"]
	for r in res:
		if r["resultado"] == "":
			continue
		var punto: Vector3 = r["punto"]
		Efectos.sonido("impacto_fuerte" if fuerte else "golpe_colonos", punto)
		Efectos.efecto("golpe_colonos", punto)
		Efectos.numero(str(roundi(golpe["dano"])), punto + Vector3.UP * 0.5,
				Color(1, 0.75, 0.3) if fuerte else Color.WHITE, fuerte)
		Efectos.pausa_golpe(float(sens.get("pausa_pesado" if fuerte else "pausa_golpe", 0.05)))
		Efectos.sacudir.emit(float(sens.get("sacudida", 0.18)) * (1.6 if fuerte else 1.0))
		_ultimo_golpeado = r["cuerpo"]
		_t_mostrar_objetivo = float(sens.get("mostrar_objetivo", 4.0))
		golpeo.emit(r)


# ================================================================ recibir golpes

func recibir_golpe(golpe: Dictionary) -> String:
	if not vivo:
		return ""
	var punto: Vector3 = golpe.get("punto", global_position + Vector3.UP)
	if invulnerable:
		Efectos.numero("Esquivado", punto + Vector3.UP * 0.4, Color(0.7, 0.9, 1.0))
		return "esquivado"
	if _inv_golpe > 0.0:
		return ""
	var dano := float(golpe.get("dano", 0.0))
	var origen := golpe.get("origen") as Node3D
	var desde := origen.global_position if origen else punto
	var bl: Dictionary = _c["bloqueo"]
	var cj: Dictionary = _c["jugador"]

	if bloqueando and Golpe.de_frente(global_position, frente(), desde, float(bl.get("angulo", 120.0))):
		var reduccion := float(bl.get("reduccion", 0.8))
		_gastar(dano * reduccion * float(bl.get("estamina_por_dano", 1.3)))
		_empujar(desde, float(golpe.get("empuje", 4.0)) * 0.4)
		if estamina <= 0.0:
			_aplicar_dano(dano * (1.0 - reduccion))
			_aturdir(float(bl.get("guardia_rota", 0.9)))
			Efectos.numero("¡Guardia rota!", punto + Vector3.UP * 0.4, Color(1, 0.5, 0.3))
			Efectos.sonido("impacto_fuerte", punto)
			return "muerto" if not vivo else "guardia_rota"
		_aplicar_dano(dano * (1.0 - reduccion))
		Efectos.sonido("escudo_colonos", punto)
		Efectos.efecto("escudo_colonos", punto)
		Efectos.numero("Bloqueado", punto + Vector3.UP * 0.4, Color(0.75, 0.8, 0.9))
		return "muerto" if not vivo else "bloqueado"

	_aplicar_dano(dano)
	Efectos.sonido("herido_colonos", punto)
	Efectos.efecto("herido_colonos", punto)
	Efectos.numero(str(roundi(dano)), punto + Vector3.UP * 0.4, Color(1, 0.35, 0.3))
	Efectos.sacudir.emit(float(_c["sensacion"].get("sacudida_recibir", 0.3)))
	if not vivo:
		return "muerto"
	_inv_golpe = float(cj.get("invulnerable_tras_golpe", 0.45))
	_empujar(desde, float(golpe.get("empuje", float(cj.get("empuje_recibido", 5.0)))))
	_aturdir(float(cj.get("aturdido", 0.35)))
	return "dano"


func _aplicar_dano(dano: float) -> void:
	vida = maxf(vida - dano, 0.0)
	if vida <= 0.0 and vivo:
		_morir()


func _aturdir(segundos: float) -> void:
	if estado == Estado.MUERTO:
		return
	_ataque = {}
	_cargando = false
	estado = Estado.ATURDIDO
	_t_aturdido = segundos


func _empujar(desde: Vector3, fuerza: float) -> void:
	var d := global_position - desde
	d.y = 0
	if d.length() > 0.01:
		d = d.normalized() * fuerza
		velocity.x = d.x
		velocity.z = d.z


func _morir() -> void:
	vivo = false
	estado = Estado.MUERTO
	_t_muerto = 0.0
	_ataque = {}
	fijado = null
	if camara:
		camara.fijado = null
	Efectos.sonido("muerte_colonos", global_position)
	Efectos.efecto("muerte_colonos", global_position + Vector3.UP * 0.8)
	UIBuilder.estado.fusionar("aviso", {"visible": true, "texto": "Has caído"})
	modelo.rotation.x = deg_to_rad(-80.0)
	murio.emit()


func revivir() -> void:
	vivo = true
	vida = vida_max
	estamina = estamina_max
	estado = Estado.NORMAL
	_inv_golpe = 1.5
	modelo.rotation.x = 0.0
	colocar(_inicio)
	UIBuilder.estado.fusionar("aviso", {"visible": false, "texto": ""})
	revivio.emit()


# ================================================================ fijar objetivo

## Fija el enemigo más adecuado frente a la cámara, o suelta el que estaba fijado.
func alternar_fijar() -> void:
	if fijado:
		fijado = null
	else:
		fijado = buscar_objetivo()
	if camara:
		camara.fijado = fijado


func buscar_objetivo() -> Node3D:
	var cf: Dictionary = _c["fijar"]
	var max_d := float(cf.get("distancia", 22.0))
	var angulo := float(cf.get("angulo", 75.0))
	var adelante := -(camara.base_plana().z) if camara else frente()
	var mejor: Node3D = null
	var mejor_puntaje := INF
	for n in get_tree().get_nodes_in_group("criaturas"):
		var c := n as Node3D
		if c == null or not c.get("vivo"):
			continue
		var d := global_position.distance_to(c.global_position)
		if d > max_d:
			continue
		var hacia := c.global_position - global_position
		hacia.y = 0
		var ang := rad_to_deg(adelante.angle_to(hacia.normalized())) if hacia.length() > 0.01 else 0.0
		if ang > angulo:
			continue
		var puntaje := d + ang * 0.15     # cerca y de frente
		if puntaje < mejor_puntaje:
			mejor_puntaje = puntaje
			mejor = c
	return mejor


func _revisar_fijado() -> void:
	if fijado == null:
		return
	var soltar := float(_c["fijar"].get("soltar", 32.0))
	if not is_instance_valid(fijado) or not fijado.get("vivo"):
		fijado = buscar_objetivo()        # murió: pasa al siguiente enemigo cercano
	elif global_position.distance_to(fijado.global_position) > soltar:
		fijado = null                     # se alejó demasiado
	else:
		return
	if camara:
		camara.fijado = fijado


func _hacia_fijado() -> Vector3:
	if fijado == null or not is_instance_valid(fijado):
		return frente()
	var h := fijado.global_position - global_position
	h.y = 0
	return h.normalized() if h.length() > 0.01 else frente()


# ================================================================ tiempos y estamina

func _timers(delta: float) -> void:
	if is_on_floor():
		_coyote = float(_m.get("coyote", 0.12))
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	_buffer_salto = maxf(_buffer_salto - delta, 0.0)
	_recarga_esquiva = maxf(_recarga_esquiva - delta, 0.0)
	_inv_golpe = maxf(_inv_golpe - delta, 0.0)
	_t_desde_ataque += delta
	_t_mostrar_objetivo = maxf(_t_mostrar_objetivo - delta, 0.0)


func _estamina(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if corriendo and horizontal > 0.5 and is_on_floor():
		_gastar(float(_s.get("correr", 16.0)) * delta)
		if estamina <= 0.0:
			_agotado = true
			corriendo = false
	elif _espera_estamina > 0.0:
		_espera_estamina -= delta
	elif estado != Estado.ATACANDO:
		var regen := float(_s.get("regeneracion", 28.0))
		if bloqueando:
			regen *= 0.4
		estamina = minf(estamina + regen * delta, estamina_max)


func _gastar(cantidad: float) -> void:
	estamina = maxf(estamina - cantidad, 0.0)
	_espera_estamina = float(_s.get("espera", 0.8))


# ================================================================ animación y HUD

func _animar() -> void:
	if _anim == null or estado == Estado.ATACANDO:
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var nombre := "quieto"
	if bloqueando and _anim.has_animation("apuntar"):
		nombre = "apuntar"
	elif horizontal > 0.3 or estado == Estado.ESQUIVANDO:
		nombre = "caminar"
	if _anim.has_animation(nombre) and _anim.current_animation != nombre:
		_anim.play(nombre, 0.15)
	_anim.speed_scale = clampf(horizontal / float(_m.get("velocidad_caminar", 4.0)), 0.6, 2.2) if nombre == "caminar" else 1.0


func _publicar() -> void:
	UIBuilder.estado.fusionar("jugador", {
		"vida": roundi(vida), "vida_max": roundi(vida_max),
		"estamina": roundi(estamina), "estamina_max": roundi(estamina_max),
	})
	var obj: Node3D = fijado
	if obj == null and _t_mostrar_objetivo > 0.0 and is_instance_valid(_ultimo_golpeado):
		obj = _ultimo_golpeado
	if obj and is_instance_valid(obj):
		UIBuilder.estado.fusionar("objetivo", {
			"visible": true, "nombre": str(obj.get("nombre")),
			"vida": roundi(maxf(float(obj.get("vida")), 0.0)), "vida_max": roundi(float(obj.get("vida_max"))),
		})
	else:
		UIBuilder.estado.fusionar("objetivo", {"visible": false})
