extends Node
## Prueba automática del paso 2, el combate (sin ventana):
##   godot --headless res://pruebas/prueba_paso2.tscn

var fallos := 0
var escena: Node
var jugador: Jugador


func _ok(cond: bool, texto: String) -> void:
	print(("  OK   " if cond else "  FALLA ") + texto)
	if not cond:
		fallos += 1


func _esperar(cuadros: int) -> void:
	for i in cuadros:
		await get_tree().physics_frame


func _segundos(s: float) -> void:
	await _esperar(int(s * 60.0))


func _ready() -> void:
	_correr.call_deferred()


## Pone un nidal frente al jugador, quieto (sin IA) si se pide.
func _nidal_enfrente(distancia: float, con_ia := false) -> Criatura:
	var c := Criatura.new()
	c.configurar("nidal", jugador.global_position)
	escena.add_child(c)
	var f := jugador.frente()
	c.global_position = jugador.global_position + f * distancia
	if not con_ia:
		c.set_physics_process(false)
	return c


func _tocar(accion: String, cuadros := 2) -> void:
	Input.action_press(accion)
	await _esperar(cuadros)
	Input.action_release(accion)


func _correr() -> void:
	escena = load("res://mundo/prueba.tscn").instantiate()
	add_child(escena)
	await _esperar(20)
	jugador = escena.get_node("Jugador")
	# aparta las guaridas de prueba para que no estorben
	for g in get_tree().get_nodes_in_group("guaridas_prueba"):
		for c in (g as Guarida).vivas:
			c.queue_free()
		g.queue_free()
	await _esperar(5)
	_ok(get_tree().get_nodes_in_group("criaturas").is_empty(), "arranca sin criaturas")

	# --- ataque ligero y combo
	var n := _nidal_enfrente(1.6)
	await _esperar(2)
	var v0 := n.vida
	await _tocar("atacar")
	await _segundos(0.4)
	_ok(n.vida < v0, "el ataque ligero hace daño (%.0f → %.0f)" % [v0, n.vida])
	var d1 := v0 - n.vida
	var e_antes := jugador.estamina
	_ok(jugador.estamina < jugador.estamina_max, "atacar gasta estamina")
	# 2º y 3º golpe del combo, encadenados
	var v1 := n.vida
	await _tocar("atacar")
	await _segundos(0.25)
	await _tocar("atacar")
	await _segundos(0.9)
	_ok(n.vida < v1 - d1 * 1.5, "el combo encadena dos golpes más (%.0f → %.0f)" % [v1, n.vida])
	n.vida = n.vida_max
	n.aguante = n.aguante_max

	# --- ataque pesado (mantener)
	await _segundos(1.0)
	n.global_position = jugador.global_position + jugador.frente() * 1.6
	v0 = n.vida
	Input.action_press("atacar")
	await _segundos(0.5)
	Input.action_release("atacar")
	await _segundos(0.6)
	var d_pesado := v0 - n.vida
	_ok(d_pesado >= 30.0, "el ataque pesado pega fuerte (%.0f)" % d_pesado)
	_ok(n.estado == Criatura.Estado.ATURDIDA or n.aguante < n.aguante_max, "el pesado baja el aguante")

	# --- fijar objetivo
	await _segundos(1.0)
	await _tocar("fijar")
	_ok(jugador.fijado == n, "Q fija al nidal")
	_ok(UIBuilder.estado.leer("objetivo.visible") == true, "el HUD muestra al objetivo")
	_ok(UIBuilder.estado.leer("objetivo.nombre") == "Nidal", "con su nombre (de monstruos.cfg)")
	await _tocar("fijar")
	_ok(jugador.fijado == null, "Q otra vez lo suelta")

	# --- matar
	n.vida = 5.0
	n.global_position = jugador.global_position + jugador.frente() * 1.6
	await _esperar(2)
	await _tocar("atacar")
	await _segundos(0.5)
	_ok(not n.vivo, "el nidal muere")
	await _segundos(1.5)
	_ok(not is_instance_valid(n), "y desaparece")

	# --- recibir, bloquear, esquivar
	await _segundos(1.0)
	var golpe := {"dano": 20.0, "empuje": 3.0, "origen": null}
	var atacante := Node3D.new()
	escena.add_child(atacante)
	atacante.global_position = jugador.global_position + jugador.frente() * 2.0
	golpe["origen"] = atacante
	var vida0 := jugador.vida
	var r := jugador.recibir_golpe(golpe)
	_ok(r == "dano" and jugador.vida == vida0 - 20.0, "recibe daño de frente sin bloquear")
	_ok(jugador.estado == Jugador.Estado.ATURDIDO, "queda aturdido un momento")
	_ok(jugador.recibir_golpe(golpe) == "", "invulnerable justo después de un golpe")
	await _segundos(1.0)
	Input.action_press("bloquear")
	await _esperar(3)
	atacante.global_position = jugador.global_position + jugador.frente() * 2.0
	vida0 = jugador.vida
	var est0 := jugador.estamina
	r = jugador.recibir_golpe(golpe)
	_ok(r == "bloqueado", "bloquea de frente")
	_ok(jugador.vida > vida0 - 20.0 * 0.5 and jugador.estamina < est0, "bloquear reduce el daño y cobra estamina")
	Input.action_release("bloquear")
	await _segundos(1.0)
	# esquiva: durante la ventana no recibe daño
	await _tocar("esquivar")
	vida0 = jugador.vida
	r = jugador.recibir_golpe(golpe)
	_ok(r == "esquivado" and jugador.vida == vida0, "la esquiva evita el golpe")
	await _segundos(1.0)

	# --- la IA del nidal ataca sola
	jugador.vida = jugador.vida_max
	var nia := _nidal_enfrente(6.0, true)
	vida0 = jugador.vida
	var t := 0.0
	while t < 6.0 and jugador.vida == vida0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_ok(jugador.vida < vida0, "el nidal persigue y ataca (%.1f s)" % t)

	# --- muerte y reaparición
	jugador.vida = 1.0
	jugador._inv_golpe = 0.0
	atacante.global_position = jugador.global_position + Vector3.FORWARD
	jugador.recibir_golpe(golpe)
	_ok(not jugador.vivo and jugador.estado == Jugador.Estado.MUERTO, "el jugador cae")
	_ok(UIBuilder.estado.leer("aviso.visible") == true, "aparece 'Has caído'")
	nia.queue_free()
	await _segundos(3.5)
	_ok(jugador.vivo and jugador.vida == jugador.vida_max, "reaparece con vida completa")

	# --- guarida: repone criaturas
	var gu := Guarida.new()
	gu.cantidad = 2
	gu.reaparicion = 0.5
	escena.add_child(gu)
	gu.global_position = jugador.global_position + Vector3(30, 0, 0)
	await _esperar(5)
	_ok(gu.vivas.size() == 2, "la guarida crea sus criaturas")
	var primera := gu.vivas[0]
	primera.recibir_golpe({"dano": 999.0, "origen": jugador})
	await _segundos(1.0)
	_ok(gu.vivas.size() == 2 and not gu.vivas.has(primera), "y repone la que muere")

	print("RESULTADO: %s (%d fallos)" % ["TODO BIEN" if fallos == 0 else "HAY FALLOS", fallos])
	get_tree().quit(1 if fallos else 0)
