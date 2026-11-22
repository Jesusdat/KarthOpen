extends Node3D
## Probador de FXForge: abre kit/fx/probador.tscn y pulsa F6.
## - Clic en un efecto: sale en el centro (los proyectiles van de izquierda a derecha).
## - "Repetir": lo lanza una y otra vez, para ajustar con calma.
## - Al guardar el JSON se recarga solo (o pulsa "Recargar").
## - Arrastra con el botón derecho para girar la cámara; la rueda acerca y aleja.

@export_file("*.json") var ruta := "res://datos/efectos.json"

var banco: FxBanco
var camara: Camera3D
var lista: VBoxContainer
var filtro: LineEdit
var info: Label
var repetir: CheckBox
var tinte: ColorPickerButton
var usar_tinte: CheckBox
var _actual := ""
var _espera := 0.0
var _mtime := 0
var _giro := 0.6
var _incl := 0.75
var _dist := 6.0

func _ready() -> void:
	_armar_escena()
	banco = FxBanco.new()
	add_child(banco)
	banco.raiz = self
	_armar_interfaz()
	_cargar()

func _armar_escena() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.4)
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-55, -30, 0)
	sol.light_energy = 0.5
	add_child(sol)
	var piso := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(12, 12)
	piso.mesh = plano
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.17, 0.16)
	piso.material_override = mat
	add_child(piso)
	for i in range(-5, 6):   # cuadrícula: una casilla = 1
		for eje in 2:
			var l := MeshInstance3D.new()
			var caja := BoxMesh.new()
			caja.size = Vector3(12, 0.005, 0.01) if eje == 0 else Vector3(0.01, 0.005, 12)
			l.mesh = caja
			var ml := StandardMaterial3D.new()
			ml.albedo_color = Color(0.3, 0.3, 0.3)
			ml.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			l.material_override = ml
			l.position = Vector3(0, 0.003, i) if eje == 0 else Vector3(i, 0.003, 0)
			add_child(l)
	var muneco := MeshInstance3D.new()   # referencia de tamaño: un personaje mide ~1
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 0.95
	muneco.mesh = cap
	muneco.position = Vector3(-1.5, 0.475, 1.5)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.45, 0.45, 0.5)
	muneco.material_override = mm
	add_child(muneco)
	camara = Camera3D.new()
	camara.fov = 40
	add_child(camara)
	_colocar_camara()

func _armar_interfaz() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	panel.custom_minimum_size = Vector2(300, 0)
	capa.add_child(panel)
	var caja := VBoxContainer.new()
	panel.add_child(caja)
	filtro = LineEdit.new()
	filtro.placeholder_text = "Filtrar (golpe, antiguos…)"
	filtro.text_changed.connect(func(_t): _armar_lista())
	caja.add_child(filtro)
	var fila := HBoxContainer.new()
	caja.add_child(fila)
	var recargar := Button.new()
	recargar.text = "Recargar"
	recargar.pressed.connect(_cargar)
	fila.add_child(recargar)
	repetir = CheckBox.new()
	repetir.text = "Repetir"
	fila.add_child(repetir)
	var fila2 := HBoxContainer.new()
	caja.add_child(fila2)
	usar_tinte = CheckBox.new()
	usar_tinte.text = "Teñir"
	fila2.add_child(usar_tinte)
	tinte = ColorPickerButton.new()
	tinte.color = Color(1.0, 0.35, 0.15)
	tinte.custom_minimum_size = Vector2(60, 24)
	fila2.add_child(tinte)
	info = Label.new()
	caja.add_child(info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	caja.add_child(scroll)
	lista = VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lista)

func _cargar() -> void:
	banco.limpiar()
	banco.cargar(ruta)
	_mtime = FileAccess.get_modified_time(ruta)
	_armar_lista()

func _armar_lista() -> void:
	for c in lista.get_children():
		c.queue_free()
	var nombres: Array = banco.efectos.keys()
	nombres.sort()
	var f := filtro.text.strip_edges().to_lower()
	var n := 0
	for nombre in nombres:
		if f != "" and not str(nombre).contains(f):
			continue
		n += 1
		var b := Button.new()
		var e: Dictionary = banco.efectos[nombre]
		b.text = str(nombre) + ("  →" if e.has("proyectil") else "") + ("  = " + str(e["igual_a"]) if e.has("igual_a") else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _lanzar(nombre))
		lista.add_child(b)
	info.text = "%d efectos · %d vivos" % [n, banco.vivos()]

func _lanzar(nombre: String) -> void:
	_actual = nombre
	_espera = maxf(banco.duracion(nombre), 0.6) + 0.3
	var op := {"color": tinte.color} if usar_tinte.button_pressed else {}
	var e: Dictionary = banco.efectos.get(banco.resolver(nombre), {})
	if e.has("proyectil"):
		banco.proyectil(nombre, Vector3(-2.5, 0, 0), Vector3(2.5, 0, 0), op)
		_espera = 1.0
	else:
		banco.lanzar(nombre, Vector3.ZERO, op)

func _process(delta: float) -> void:
	if FileAccess.get_modified_time(ruta) != _mtime:
		_cargar()   # guardaste el JSON: recarga sola
	if repetir.button_pressed and _actual != "":
		_espera -= delta
		if _espera <= 0.0:
			_lanzar(_actual)
	info.text = "%d efectos · %d vivos" % [lista.get_child_count(), banco.vivos()]

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		_giro -= ev.relative.x * 0.01
		_incl = clampf(_incl + ev.relative.y * 0.01, 0.15, 1.4)
		_colocar_camara()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(2.0, _dist * 0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(20.0, _dist * 1.1)
		_colocar_camara()

func _colocar_camara() -> void:
	var foco := Vector3(0, 0.5, 0)
	camara.position = foco + Vector3(sin(_giro) * cos(_incl), sin(_incl), cos(_giro) * cos(_incl)) * _dist
	camara.look_at(foco)
