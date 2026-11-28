extends Node
## Autoload "Efectos": sonidos (SfxBanco), efectos visuales (FxBanco), números de daño,
## pausa al golpear (hitstop) y sacudida de cámara. Todo con los datos de Karth.

const SONIDOS := "res://datos/sonidos.cfg"
const VISUALES := "res://datos/efectos.json"

signal sacudir(fuerza: float)

var sfx: SfxBanco
var fx: FxBanco
var _fin_pausa := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Musica", "Efectos"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	sfx = SfxBanco.new()
	sfx.bus_defecto = "Efectos"
	sfx.metros_por_casilla = 1.9   # el alcance del .cfg está en casillas de Karth
	add_child(sfx)
	sfx.cargar(SONIDOS)
	fx = FxBanco.new()
	add_child(fx)
	fx.cargar(VISUALES)


## El mundo 3D actual (donde se cuelgan sonidos y efectos) y quién escucha.
func usar_mundo(raiz: Node3D, oido: Node3D) -> void:
	sfx.raiz_3d = raiz
	sfx.oido = oido
	fx.raiz = raiz


func sonido(nombre: String, punto = null) -> void:
	if punto is Vector3:
		sfx.tocar_en_3d(nombre, punto)
	else:
		sfx.tocar(nombre)


func efecto(nombre: String, punto: Vector3, opciones := {}) -> void:
	if fx.raiz != null and is_instance_valid(fx.raiz):
		fx.lanzar(nombre, punto, opciones)


## Número que sube y se desvanece sobre el punto (daño, "Bloqueado", etc.).
func numero(texto: String, punto: Vector3, color := Color.WHITE, grande := false) -> void:
	if fx.raiz == null or not is_instance_valid(fx.raiz):
		return
	var l := Label3D.new()
	l.text = texto
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011 if grande else 0.0008
	l.font_size = 48
	l.outline_size = 12
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.8)
	fx.raiz.add_child(l)
	l.global_position = punto + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position:y", l.global_position.y + 1.2, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)


## Congela el juego un instante para que el golpe se sienta (hitstop).
func pausa_golpe(segundos: float) -> void:
	if segundos <= 0.0:
		return
	Engine.time_scale = 0.02
	_fin_pausa = Time.get_ticks_msec() + int(segundos * 1000.0)


func _process(_delta: float) -> void:
	if _fin_pausa > 0 and Time.get_ticks_msec() >= _fin_pausa:
		_fin_pausa = 0
		Engine.time_scale = 1.0
