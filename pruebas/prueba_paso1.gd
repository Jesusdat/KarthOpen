extends Node
## Prueba automática del paso 1 (sin ventana):
##   godot --headless res://pruebas/prueba_paso1.tscn
## Carga la escena de prueba, mueve al jugador con acciones simuladas y revisa
## que camine sobre el terreno, corra, salte, esquive y gaste estamina.

var fallos := 0


func _ok(cond: bool, texto: String) -> void:
	print(("  OK   " if cond else "  FALLA ") + texto)
	if not cond:
		fallos += 1


func _esperar(cuadros: int) -> void:
	for i in cuadros:
		await get_tree().physics_frame


func _ready() -> void:
	_correr.call_deferred()


func _correr() -> void:
	var t0 := Time.get_ticks_msec()
	var escena: Node = load("res://mundo/prueba.tscn").instantiate()
	add_child(escena)
	var t_armado := Time.get_ticks_msec() - t0
	await _esperar(30)
	var terreno: TerrenoKarth = escena.get_node("Terreno")
	var jugador: Jugador = escena.get_node("Jugador")
	var props: Node3D = escena.get_node("Props")
	print("Terreno: %d m por lado, armado en %d ms; props: %d" % [terreno.lado, t_armado, props.get_child_count()])
	_ok(terreno.lado == 512, "el terreno mide 512 m")
	_ok(props.get_child_count() > 100, "hay props repartidos")
	_ok(jugador.is_on_floor(), "el jugador está en el suelo al empezar")
	var suelo := terreno.altura_en(jugador.global_position.x, jugador.global_position.z)
	_ok(absf(jugador.global_position.y - suelo) < 0.3, "el jugador pisa la altura del terreno (%.2f vs %.2f)" % [jugador.global_position.y, suelo])

	# caminar
	var p0 := jugador.global_position
	Input.action_press("adelante")
	await _esperar(60)
	var caminado := Vector2(jugador.global_position.x - p0.x, jugador.global_position.z - p0.z).length()
	_ok(caminado > 3.0, "camina hacia adelante (%.2f m en 1 s)" % caminado)
	_ok(jugador.estamina >= jugador.estamina_max - 0.5, "caminar no gasta estamina")

	# correr
	p0 = jugador.global_position
	Input.action_press("correr")
	await _esperar(60)
	var corrido := Vector2(jugador.global_position.x - p0.x, jugador.global_position.z - p0.z).length()
	_ok(corrido > caminado * 1.4, "correr es más rápido (%.2f m en 1 s)" % corrido)
	_ok(jugador.estamina < jugador.estamina_max - 10.0, "correr gasta estamina (%.0f)" % jugador.estamina)
	Input.action_release("correr")
	Input.action_release("adelante")
	await _esperar(30)

	# saltar
	var y0 := jugador.global_position.y
	Input.action_press("saltar")
	await _esperar(2)
	Input.action_release("saltar")
	var y_max := y0
	for i in 40:
		await get_tree().physics_frame
		y_max = maxf(y_max, jugador.global_position.y)
	_ok(y_max - y0 > 0.5, "salta (%.2f m)" % (y_max - y0))
	await _esperar(40)
	_ok(jugador.is_on_floor(), "vuelve a caer al suelo")

	# esquivar
	await _esperar(90)
	var e0 := jugador.estamina
	p0 = jugador.global_position
	Input.action_press("esquivar")
	await _esperar(2)
	Input.action_release("esquivar")
	_ok(jugador.estado == Jugador.Estado.ESQUIVANDO and jugador.invulnerable, "esquiva con invulnerabilidad")
	await _esperar(40)
	var esquivado := Vector2(jugador.global_position.x - p0.x, jugador.global_position.z - p0.z).length()
	_ok(esquivado > 2.0, "la esquiva desplaza (%.2f m)" % esquivado)
	_ok(jugador.estamina < e0, "la esquiva gasta estamina")
	_ok(jugador.estado == Jugador.Estado.NORMAL and not jugador.invulnerable, "la esquiva termina")

	# HUD enlazado
	_ok(UIBuilder.estado.leer("jugador.estamina") == roundi(jugador.estamina), "el HUD recibe la estamina")
	_ok(UIBuilder.obtener("res://ui/hud.json") != null, "el HUD está abierto")

	print("RESULTADO: %s (%d fallos)" % ["TODO BIEN" if fallos == 0 else "HAY FALLOS", fallos])
	get_tree().quit(1 if fallos else 0)
