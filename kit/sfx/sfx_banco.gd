class_name SfxBanco
extends Node
## Banco de sonidos del kit (SFXForge). Lee el .cfg que genera kit/sfx/sfx_forge.py
## y toca cada evento con una variante al azar (sin repetir la anterior), tono un
## poco distinto cada vez, límite de voces y espera mínima entre repeticiones.
##
##   var sfx := SfxBanco.new()
##   add_child(sfx)
##   sfx.cargar("res://datos/sonidos.cfg")
##   sfx.tocar("monedas")                        # sin posición (interfaz, el propio jugador)
##   sfx.tocar_en_3d("golpe_enjambre", punto)     # desde un punto del mundo 3D
##   sfx.tocar_lejos("muerte_colonos", 6.0)       # mundo 2D: baja con la distancia
##
## Nombres con sufijo: si "golpe_fisura" no existe se prueba "golpe", y si un
## nombre no es evento pero hay un archivo suelto (carpeta_suelta % nombre), se toca ese.

const AJUSTES := {"vol_db": 0.0, "tono": [0.96, 1.04], "voces": 4, "espera": 0.03, "alcance": 12.0, "bus": "Master"}

## Carpeta de los .wav sueltos que no están en el .cfg (sonidos viejos o de interfaz).
var carpeta_suelta := "res://sounds/%s.wav"
## Nodo 3D al que se cuelgan los sonidos con posición (por ejemplo, la vista 3D).
var raiz_3d: Node3D
## Desde dónde se mide el alcance en 3D (por ejemplo, el oído junto al jugador).
var oido: Node3D
## Apagado: no carga ni toca nada (servidor sin pantalla, pruebas).
var apagado := false
## Bus que se usa si el evento no dice otro.
var bus_defecto := "Master"
## Tamaño de "una casilla" en metros para el 3D; el alcance del .cfg va en casillas.
var metros_por_casilla := 1.0

var eventos := {}            # nombre -> {archivos, vol_db, tono, voces, espera, alcance, bus}
var _streams := {}           # ruta -> AudioStream
var _ultima_variante := {}   # nombre -> índice
var _ultimo_ms := {}         # nombre -> ms del último inicio
var _sonando := {}           # nombre -> Array de reproductores vivos
var _resuelto := {}          # nombre pedido -> {"evento": ...} o {"suelto": ruta} o {}

func cargar(ruta_cfg: String) -> int:
	var cfg := ConfigFile.new()
	var err := cfg.load(ruta_cfg)
	if err != OK:
		push_warning("SfxBanco: no se pudo leer %s (%d)" % [ruta_cfg, err])
		return err
	for nombre in cfg.get_sections():
		var e := {}
		for k in AJUSTES:
			e[k] = cfg.get_value(nombre, k, AJUSTES[k])
		if not cfg.has_section_key(nombre, "bus"):
			e["bus"] = bus_defecto
		e["archivos"] = cfg.get_value(nombre, "archivos", [])
		eventos[nombre] = e
	_resuelto.clear()
	return OK

func existe(nombre: String) -> bool:
	return eventos.has(nombre)

## Qué se va a tocar para un nombre: el evento, una versión sin sufijo o un archivo suelto.
func resolver(nombre: String) -> Dictionary:
	if _resuelto.has(nombre):
		return _resuelto[nombre]
	var r := {}
	var n := nombre
	while n != "":
		if eventos.has(n):
			r = {"evento": n}
			break
		var suelto := carpeta_suelta % n
		if ResourceLoader.exists(suelto):
			r = {"suelto": suelto}
			break
		var corte := n.rfind("_")
		n = n.substr(0, corte) if corte > 0 else ""
	_resuelto[nombre] = r
	return r

func tocar(nombre: String, vol_db := 0.0) -> Node:
	var plan := _preparar(nombre)
	if plan.is_empty():
		return null
	var p := AudioStreamPlayer.new()
	_configurar(p, plan, vol_db)
	add_child(p)
	return _arrancar(p, plan)

func tocar_en_3d(nombre: String, punto: Vector3, vol_db := 0.0) -> Node:
	if raiz_3d == null or not is_instance_valid(raiz_3d) or not raiz_3d.is_inside_tree():
		return tocar(nombre, vol_db)
	var plan := _preparar(nombre)
	if plan.is_empty():
		return null
	var alcance_m: float = float(plan["alcance"]) * metros_por_casilla
	if oido != null and is_instance_valid(oido) and oido.global_position.distance_to(punto) > alcance_m:
		return null
	var p := AudioStreamPlayer3D.new()
	_configurar(p, plan, vol_db)
	p.max_distance = alcance_m
	p.unit_size = alcance_m * 0.35
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.panning_strength = 0.7
	raiz_3d.add_child(p)
	p.global_position = punto
	return _arrancar(p, plan)

## Sin 3D: el volumen baja con la distancia (en casillas) hasta el alcance del evento.
func tocar_lejos(nombre: String, distancia: float, vol_db := 0.0) -> Node:
	var plan := _preparar(nombre)
	if plan.is_empty():
		return null
	var alcance: float = float(plan["alcance"])
	if distancia > alcance:
		return null
	var k := clampf(distancia / maxf(alcance, 0.01), 0.0, 1.0)
	var p := AudioStreamPlayer.new()
	_configurar(p, plan, vol_db + linear_to_db(maxf(pow(1.0 - k, 1.6), 0.02)))
	add_child(p)
	return _arrancar(p, plan)

func detener_todo() -> void:
	for lista in _sonando.values():
		for p in lista:
			if is_instance_valid(p):
				p.queue_free()
	_sonando.clear()

## Variante siguiente sin repetir la última (público para las pruebas).
func elegir_variante(nombre: String, cuantas: int) -> int:
	if cuantas <= 1:
		return 0
	var antes: int = _ultima_variante.get(nombre, -1)
	var i := randi() % (cuantas - 1 if antes >= 0 else cuantas)
	if antes >= 0 and i >= antes:
		i += 1
	_ultima_variante[nombre] = i
	return i

# --- interno
func _preparar(nombre: String) -> Dictionary:
	if apagado or not is_inside_tree():
		return {}
	var r := resolver(nombre)
	if r.is_empty():
		return {}
	if r.has("suelto"):
		var s = _stream(r["suelto"])
		if s == null:
			return {}
		return {"clave": nombre, "stream": s, "vol_db": 0.0, "tono": [1.0, 1.0], "voces": 4, "espera": 0.0, "alcance": AJUSTES["alcance"], "bus": bus_defecto}
	var ev: String = r["evento"]
	var e: Dictionary = eventos[ev]
	var ahora := Time.get_ticks_msec()
	if ahora - int(_ultimo_ms.get(ev, -100000)) < int(float(e["espera"]) * 1000.0):
		return {}
	var archivos: Array = e["archivos"]
	if archivos.is_empty():
		return {}
	var s = _stream(str(archivos[elegir_variante(ev, archivos.size())]))
	if s == null:
		return {}
	_ultimo_ms[ev] = ahora
	var plan := e.duplicate()
	plan["clave"] = ev
	plan["stream"] = s
	return plan

func _stream(ruta: String):
	if not _streams.has(ruta):
		_streams[ruta] = load(ruta) if ResourceLoader.exists(ruta) else null
	return _streams[ruta]

func _configurar(p: Node, plan: Dictionary, vol_db: float) -> void:
	p.stream = plan["stream"]
	var bus := str(plan["bus"])
	p.bus = bus if AudioServer.get_bus_index(bus) != -1 else "Master"
	p.volume_db = float(plan["vol_db"]) + vol_db
	var tono: Array = plan["tono"]
	p.pitch_scale = randf_range(float(tono[0]), float(tono[1]))
	p.process_mode = Node.PROCESS_MODE_ALWAYS

func _arrancar(p: Node, plan: Dictionary) -> Node:
	var clave: String = plan["clave"]
	var lista: Array = _sonando.get(clave, [])
	lista = lista.filter(func(x): return is_instance_valid(x))
	while lista.size() >= int(plan["voces"]):
		var viejo = lista.pop_front()
		viejo.queue_free()   # roba la voz más vieja
	lista.append(p)
	_sonando[clave] = lista
	p.finished.connect(p.queue_free)
	p.play()
	return p
