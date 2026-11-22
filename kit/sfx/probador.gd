extends Control
## Probador de SFXForge: abre esta escena (F6 sobre kit/sfx/probador.tscn) para
## escuchar cada evento del .cfg. Clic = una variante; "×4" = varias seguidas para
## oír cómo cambian. Si regeneras los sonidos, pulsa "Recargar".

@export_file("*.cfg") var ruta_cfg := "res://datos/sonidos.cfg"

var banco: SfxBanco
var lista: VBoxContainer
var filtro: LineEdit
var info: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	banco = SfxBanco.new()
	add_child(banco)
	var fondo := ColorRect.new()
	fondo.color = Color(0.08, 0.08, 0.1)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)
	var caja := VBoxContainer.new()
	caja.set_anchors_preset(Control.PRESET_FULL_RECT)
	caja.offset_left = 16
	caja.offset_top = 12
	caja.offset_right = -16
	caja.offset_bottom = -12
	add_child(caja)
	var arriba := HBoxContainer.new()
	caja.add_child(arriba)
	filtro = LineEdit.new()
	filtro.placeholder_text = "Filtrar (golpe, enjambre, muerte…)"
	filtro.custom_minimum_size.x = 320
	filtro.text_changed.connect(func(_t): _armar())
	arriba.add_child(filtro)
	var recargar := Button.new()
	recargar.text = "Recargar"
	recargar.pressed.connect(_cargar)
	arriba.add_child(recargar)
	info = Label.new()
	arriba.add_child(info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caja.add_child(scroll)
	lista = VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lista)
	_cargar()

func _cargar() -> void:
	banco.eventos.clear()
	banco._streams.clear()
	banco.cargar(ruta_cfg)
	_armar()

func _armar() -> void:
	for c in lista.get_children():
		c.queue_free()
	var nombres: Array = banco.eventos.keys()
	nombres.sort()
	var f := filtro.text.strip_edges().to_lower()
	var cuantos := 0
	for nombre in nombres:
		if f != "" and not str(nombre).contains(f):
			continue
		cuantos += 1
		var e: Dictionary = banco.eventos[nombre]
		var fila := HBoxContainer.new()
		lista.add_child(fila)
		var b := Button.new()
		b.text = str(nombre)
		b.custom_minimum_size.x = 260
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _tocar(nombre))
		fila.add_child(b)
		var varias := Button.new()
		varias.text = "×4"
		varias.pressed.connect(func(): _varias(nombre))
		fila.add_child(varias)
		var d := Label.new()
		d.text = "  %d variantes · %+.0f dB · voces %d · alcance %.0f" % [e["archivos"].size(), float(e["vol_db"]), int(e["voces"]), float(e["alcance"])]
		d.modulate = Color(0.7, 0.7, 0.75)
		fila.add_child(d)
	info.text = "  %d eventos" % cuantos

func _tocar(nombre: String) -> void:
	banco._ultimo_ms.erase(nombre)
	banco.tocar(nombre)

func _varias(nombre: String) -> void:
	for i in 4:
		_tocar(nombre)
		await get_tree().create_timer(0.7).timeout
