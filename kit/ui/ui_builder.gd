extends Node
## UIBuilder v2 — interfaces a partir de JSON, enlazadas al estado del juego.
## Registrar como Autoload con el nombre "UIBuilder".
## Necesita junto a él: ui_vista.gd y ui_estado.gd.
##
##   UIBuilder.cargar_tema("res://ui/tema.json")
##   UIBuilder.cargar_plantillas("res://ui/plantillas.json")
##   UIBuilder.estado.poner("jugador.vida", 70)          # la UI se actualiza sola
##   var mochila := UIBuilder.abrir("res://ui/mochila.json")
##   mochila.accion.connect(_on_mochila)                 # señal propia de esa vista

const RANGO := {"hud": 0, "ventana": 1, "modal": 2}

const POSICIONES := {
	"centro": [Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_CENTER],
	"arriba": [Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN],
	"abajo": [Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_END],
	"izq": [Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_CENTER],
	"der": [Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_CENTER],
	"arriba_izq": [Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN],
	"arriba_der": [Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_BEGIN],
	"abajo_izq": [Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_END],
	"abajo_der": [Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_END],
	"completo": [Control.SIZE_FILL, Control.SIZE_FILL],
}

# Tipos de propiedad para validar: texto, numero, bool, color, tamano, dic,
# spec, specs, enlace, opciones, enum:a|b, cualquiera. El "*" final indica que
# admite un enlace ("@ruta"). Los textos siempre admiten "{ruta}".
const PROPS_COMUNES := {
	"tipo": "texto", "id": "texto", "tamano": "tamano", "tooltip": "texto",
	"visible": "bool*", "expandir": "bool", "expandir_v": "bool",
}
const PROPS_RAIZ := {
	"posicion": "enum:centro|arriba|abajo|izq|der|arriba_izq|arriba_der|abajo_izq|abajo_der|completo",
	"margen": "numero", "capa": "enum:hud|ventana|modal", "cerrar_con_esc": "bool",
	"movible": "bool",
}
const PROPS_HIJOS := {"hijos": "specs", "repetir": "enlace", "elemento": "spec", "como": "texto"}
const PROPS_ACCION := {"accion": "texto", "datos": "dic"}
const PROPS_ARRASTRE := {"arrastrable": "bool", "al_soltar": "texto", "grupo": "texto", "acepta": "dic", "intercambio": "bool"}

## Estado global al que se enlazan las interfaces.
var estado := UIEstado.new()
## Tema compartido. Se modifica en el sitio: cambiarlo actualiza lo que ya está en pantalla.
var tema := Theme.new()
## Capa donde se dibujan las vistas (por encima del juego).
var lienzo: CanvasLayer
## Vuelve a cargar los JSON al guardarlos. Solo en modo depuración.
var recarga_en_caliente := OS.is_debug_build()

var paleta := {
	"fondo": Color("1e1e24"),
	"borde": Color("5a5a6e"),
	"texto": Color("e8e8f0"),
	"texto_tenue": Color("9a9aa6"),
	"acento": Color("e0782a"),
	"boton": Color("2e2e38"),
	"boton_hover": Color("3c3c4a"),
	"ranura": Color("15151a"),
	"barra_fondo": Color("101014"),
	"velo": Color(0, 0, 0, 0.55),
	"error": Color("e04848"),
}
var rarezas := {
	"comun": Color("9a9aa6"),
	"poco_comun": Color("4fbf5a"),
	"raro": Color("3f8fe0"),
	"epico": Color("a052e0"),
	"legendario": Color("f0a020"),
}
var radio := 6
var grosor_borde := 2
var tam_fuente := 16
var fuente: Font

## Nombres de rareza que se muestran en los tooltips.
var nombres_rareza := {
	"comun": "Común", "poco_comun": "Poco común", "raro": "Raro",
	"epico": "Épico", "legendario": "Legendario",
}
## Notificaciones: esquina, cuántas a la vez y cuánto duran (segundos).
var esquina_avisos := "arriba_der"
var max_avisos := 5
var duracion_avisos := 3.0
## Para que un juego dibuje sus propios tooltips de objetos: func(objeto: Dictionary) -> Control
var tooltip_objeto: Callable

## Para que un juego dibuje marcas propias en las ranuras (mejora, favorito...):
##   func(ranura: Control, marcas: Control, objeto: Dictionary) -> void
## "marcas" es una capa del tamaño de la ranura que se vacía en cada repintado.
var decorar_ranura: Callable
## Animación al abrir una ventana o modal: func(contenido: Control, vista: UIVista) -> void
## Si no se define, la ventana aparece con un desvanecido corto.
var al_abrir: Callable
## Se llama al pulsar cualquier botón o casilla del kit (para un sonido de clic): func() -> void
var al_clic: Callable
## Tema del propio juego: sus estilos de paneles, botones, textos y fuentes se usan
## por encima de los del kit. Tras cambiarlo (por ejemplo, al cambiar de bando),
## llama a UIBuilder.refrescar_tema().
var tema_base: Theme
## Fuente de los títulos (Font o ruta). Vacía = la normal.
var fuente_titulo: Font

var lienzo_avisos: CanvasLayer
var _menu: UIVista
var _raton := Vector2(-1, -1)        # última posición del ratón vista en _input
var _avisos: VBoxContainer
var _componentes: Dictionary = {}    # tipo -> {"crear": Callable, "props": Dictionary o null}
var _plantillas: Dictionary = {}     # nombre -> {"parametros": {}, "cuerpo": {}}
var _vistas: Array[UIVista] = []
var _archivos: Dictionary = {}       # ruta -> fecha de modificación vista por última vez
var _rutas_plantillas: PackedStringArray = []
var _ruta_tema := ""
var _posiciones: Dictionary = {}     # ruta -> dónde dejó el jugador esa ventana
var _arrastre_origen: Control        # ranura de la que salió el objeto arrastrado
var _arrastre_destino: Control       # ranura resaltada como destino


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	lienzo = CanvasLayer.new()
	lienzo.name = "UILienzo"
	lienzo.layer = 100
	add_child(lienzo)
	_crear_avisos()
	_registrar_basicos()
	_rellenar_tema()
	var reloj := Timer.new()
	reloj.wait_time = 0.5
	reloj.autostart = true
	reloj.timeout.connect(_vigilar_archivos)
	add_child(reloj)


# ================================================================ API

## Abre una interfaz. origen: ruta de un JSON o un Dictionary.
## Si ese JSON ya está abierto, lo trae al frente en vez de duplicarlo.
func abrir(origen: Variant, estado_propio: UIEstado = null) -> UIVista:
	if origen is String:
		var ya := obtener(origen)
		if ya:
			_al_frente(ya)
			return ya
	var vista := UIVista.new()
	vista.theme = tema
	vista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vista.conectar_estado(estado_propio if estado_propio else estado)
	if origen is String:
		vista.ruta = origen
		vista.desplazamiento = _posiciones.get(origen, Vector2.ZERO)
		vista.name = String(origen).get_file().get_basename().validate_node_name()
	elif origen is Dictionary:
		vista.spec_origen = origen
	lienzo.add_child(vista)
	vista.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vistas.append(vista)
	vista.tree_exited.connect(func() -> void: _vistas.erase(vista))
	_montar(vista)
	_ordenar()
	return vista


## Abre el JSON si está cerrado y lo cierra si está abierto (para teclas como I o M).
## Devuelve la vista si quedó abierta, o null si se cerró.
func alternar(ruta: String, estado_propio: UIEstado = null) -> UIVista:
	var ya := obtener(ruta)
	if ya:
		ya.cerrar()
		return null
	return abrir(ruta, estado_propio)


## La vista abierta desde ese JSON, o null.
func obtener(ruta: String) -> UIVista:
	for v in _vistas:
		if v.ruta == ruta and not v.is_queued_for_deletion():
			return v
	return null


func cerrar_todo(incluir_hud := false) -> void:
	for v in _vistas.duplicate():
		if incluir_hud or v.capa != "hud":
			v.cerrar()


## Diálogo modal que espera la respuesta:
##   var r := await UIBuilder.preguntar("Herrero", "¿Mejorar por 50?", ["Sí", "No"])
## Devuelve el índice elegido, o -1 si se cerró con Esc.
func preguntar(titulo: String, texto: String, opciones: Array = ["Aceptar"]) -> int:
	var v := abrir({
		"tipo": "dialogo", "capa": "modal", "posicion": "centro",
		"titulo": titulo, "texto": texto, "opciones": opciones, "accion": "respuesta",
	})
	v.accion.connect(func(_n: String, d: Dictionary) -> void: v.resolver(int(d.get("indice", -1))))
	var r: int = await v.resuelta
	return r


## true si el ratón está encima de una interfaz del kit (o hay un modal abierto).
## Úsalo si tu juego lee clics con _input() o Input.is_action_just_pressed():
##   if UIBuilder.raton_sobre_ui(): return
## Con _unhandled_input() no hace falta: esos clics ya no llegan al juego.
func raton_sobre_ui() -> bool:
	return hay_modal() or _vista_bajo_raton() != null


## true si hay alguna ventana o modal abierto (útil para no abrir la pausa con Esc).
func hay_ventanas() -> bool:
	return _vista_superior() != null


func hay_modal() -> bool:
	for v in _vistas:
		if v.capa == "modal" and not v.is_queued_for_deletion():
			return true
	return false


## true si el jugador está escribiendo en un campo de texto. Úsalo si tu juego
## lee el teclado con Input.is_action_pressed() (por ejemplo, moverse con WASD):
##   if UIBuilder.escribiendo(): return
func escribiendo() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Aviso breve en una esquina que desaparece solo.
##   UIBuilder.notificar("Botiquín x2", {"titulo": "Objeto obtenido", "icono": "res://...", "rareza": "comun"})
## opciones: titulo, icono, rareza, color (nombre del tema o "#rrggbb"), duracion (segundos).
func notificar(texto: String, opciones: Dictionary = {}) -> Control:
	var color: Color = paleta.acento
	if rarezas.has(opciones.get("rareza")):
		color = rarezas[opciones.rareza]
	if opciones.has("color"):
		color = _color(opciones.color)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caja := _caja(paleta.fondo, color, 8)
	caja.border_width_left = maxi(grosor_borde, 4)
	p.add_theme_stylebox_override("panel", caja)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var textura := _textura(opciones.get("icono"))
	if textura:
		var t := TextureRect.new()
		t.texture = textura
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(32, 32)
		h.add_child(t)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	if opciones.has("titulo"):
		var tl := Label.new()
		tl.text = str(opciones.titulo)
		tl.add_theme_color_override("font_color", color)
		tl.add_theme_font_size_override("font_size", maxi(tam_fuente - 2, 8))
		v.add_child(tl)
	var l := Label.new()
	l.text = texto
	v.add_child(l)
	for n in p.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avisos.add_child(p)
	while _avisos.get_child_count() > max_avisos:
		var viejo := _avisos.get_child(0)
		_avisos.remove_child(viejo)
		viejo.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(float(opciones.get("duracion", duracion_avisos)))
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
	return p


## El tooltip que se muestra al pasar el ratón sobre un objeto en una ranura.
## Campos que usa: nombre, rareza, tipo, descripcion, stats ({"Daño": 12, "Defensa": "+3"}), pie.
## Para dibujarlo a tu manera: UIBuilder.tooltip_objeto = func(objeto): return mi_control
func crear_tooltip(objeto: Dictionary) -> Control:
	if tooltip_objeto.is_valid():
		return tooltip_objeto.call(objeto)
	var v := VBoxContainer.new()
	v.theme = tema
	v.add_theme_constant_override("separation", 4)
	var rareza: Variant = objeto.get("rareza")
	var nombre := Label.new()
	nombre.text = _txt(objeto.get("nombre"))
	nombre.theme_type_variation = "Titulo"
	if rarezas.has(rareza):
		nombre.add_theme_color_override("font_color", rarezas[rareza])
	v.add_child(nombre)
	var linea: PackedStringArray = []
	if rarezas.has(rareza):
		linea.append(nombres_rareza.get(rareza, String(rareza).capitalize()))
	if objeto.get("tipo"):
		linea.append(_txt(objeto.tipo))
	if not linea.is_empty():
		var l := Label.new()
		l.text = " · ".join(linea)
		l.theme_type_variation = "Texto_texto_tenue"
		v.add_child(l)
	var stats: Variant = objeto.get("stats")
	if stats is Dictionary and not stats.is_empty():
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 16)
		g.add_theme_constant_override("v_separation", 0)
		for k: Variant in stats:
			var a := Label.new()
			a.text = _txt(k)
			a.theme_type_variation = "Texto_texto_tenue"
			g.add_child(a)
			var b := Label.new()
			b.text = _txt(stats[k])
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if b.text.begins_with("+"):
				b.add_theme_color_override("font_color", rarezas.get("poco_comun", paleta.texto))
			elif b.text.begins_with("-"):
				b.add_theme_color_override("font_color", paleta.error)
			g.add_child(b)
		v.add_child(g)
	for campo in ["descripcion", "pie"]:
		if objeto.get(campo):
			var d := Label.new()
			d.text = _txt(objeto[campo])
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size.x = 240
			if campo == "pie":
				d.theme_type_variation = "Texto_texto_tenue"
			v.add_child(d)
	return v


## Menú de clic derecho junto al ratón. Cada opción es uno de:
##   {"titulo": "Rifle", "color": Color(...)}             encabezado
##   {"texto": "¿Seguro?"}                                 texto sin acción
##   {"texto": "Equipar", "accion": func(): ..., "desactivada": false, "cierra": true}
## Un clic fuera o Esc lo cierran. Para pedir confirmación, una opción con
## "cierra": false puede llamar otra vez a UIBuilder.menu(...) con las nuevas opciones.
func menu(opciones: Array, posicion: Variant = null) -> UIVista:
	cerrar_menu()
	var vista := UIVista.new()
	vista.theme = tema
	vista.capa = "modal"
	vista.name = "Menu"
	vista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vista.conectar_estado(estado)
	lienzo.add_child(vista)
	vista.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fondo := Control.new()      # transparente: un clic fuera del menú lo cierra
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	vista.add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			vista.cerrar())
	var p := PanelContainer.new()
	p.theme_type_variation = "PanelMenu"
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 2)
	p.add_child(caja)
	for op: Variant in opciones:
		if not (op is Dictionary):
			continue
		if op.has("titulo"):
			var t := Label.new()
			t.text = _txt(op.titulo)
			t.theme_type_variation = "Titulo"
			if op.has("color"):
				t.add_theme_color_override("font_color", _color(op.color))
			caja.add_child(t)
		elif op.has("accion"):
			var b := Button.new()
			b.text = _txt(op.get("texto", ""))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = op.get("desactivada", false)
			b.focus_mode = Control.FOCUS_NONE
			var accion: Callable = op.accion
			var cierra: bool = op.get("cierra", true)
			b.pressed.connect(func() -> void:
				if cierra:
					vista.cerrar()
				if accion.is_valid():
					accion.call())
			caja.add_child(b)
		else:
			var l := Label.new()
			l.text = _txt(op.get("texto", ""))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 200
			caja.add_child(l)
	vista.add_child(p)
	_conectar_clics(p)
	var raton := _raton if _raton.x >= 0 else get_viewport().get_mouse_position()
	var pos: Vector2 = posicion if posicion is Vector2 else raton + Vector2(6, 6)
	p.reset_size()
	var lim := get_viewport().get_visible_rect().size
	p.position = Vector2(clampf(pos.x, 4, maxf(lim.x - p.size.x - 4, 4)), clampf(pos.y, 4, maxf(lim.y - p.size.y - 4, 4)))
	_vistas.append(vista)
	vista.tree_exited.connect(func() -> void: _vistas.erase(vista))
	_ordenar()
	_menu = vista
	return vista


func cerrar_menu() -> void:
	if is_instance_valid(_menu):
		_menu.cerrar()
	_menu = null


## Registra un componente propio del juego.
##   UIBuilder.registrar_componente("minimapa", func(spec, ctx):
##       var m := Minimapa.new()
##       ctx.enlazar(m, spec, "zoom", func(v): m.zoom = float(v))
##       return m
##   , {"zoom": "numero*"})
## props: propiedades que acepta (para validar el JSON); null = no validar.
func registrar_componente(tipo: String, crear: Callable, props: Variant = null) -> void:
	_componentes[tipo] = {"crear": crear, "props": props}


## Registra una plantilla reutilizable. definicion:
##   {"parametros": {"titulo": "", "hijos": []}, "cuerpo": { ...spec con "$titulo" y "$hijos"... }}
func registrar_plantilla(nombre: String, definicion: Dictionary) -> void:
	if definicion.has("cuerpo"):
		_plantillas[nombre] = {"parametros": definicion.get("parametros", {}), "cuerpo": definicion.cuerpo}
	else:
		_plantillas[nombre] = {"parametros": {}, "cuerpo": definicion}


## Carga un JSON con varias plantillas: {"ventana": {...}, "fila_tienda": {...}}
func cargar_plantillas(ruta: String) -> void:
	var errores: PackedStringArray = []
	var datos: Variant = _leer_json(ruta, errores)
	_seguir_archivo(ruta)
	if not _rutas_plantillas.has(ruta):
		_rutas_plantillas.append(ruta)
	if datos is Dictionary:
		for nombre: String in datos:
			if datos[nombre] is Dictionary:
				registrar_plantilla(nombre, datos[nombre])
			else:
				errores.append("%s → %s: la plantilla debe ser un objeto {...}" % [ruta, nombre])
	elif errores.is_empty():
		errores.append("%s: se esperaba un objeto {...} con las plantillas" % ruta)
	for e in errores:
		push_error("UIBuilder: " + e)


## Cambia el aspecto, también de lo que ya está en pantalla.
##   UIBuilder.aplicar_tema({"colores": {"acento": "#ff5522", "vida": "#c0392b"}, "radio": 2})
## Los colores nuevos (como "vida") se pueden usar por nombre en "color".
func aplicar_tema(datos: Dictionary) -> void:
	for k: String in datos.get("colores", {}):
		paleta[k] = _color(datos.colores[k])
	for k: String in datos.get("rarezas", {}):
		rarezas[k] = _color(datos.rarezas[k])
	radio = int(datos.get("radio", radio))
	grosor_borde = int(datos.get("grosor_borde", grosor_borde))
	tam_fuente = int(datos.get("tam_fuente", tam_fuente))
	if datos.has("fuente"):
		var f: String = str(datos.fuente)
		fuente = load(f) as Font if ResourceLoader.exists(f) else null
		if f != "" and fuente == null:
			push_error("UIBuilder: no se encontró la fuente " + f)
	if datos.has("fuente_titulo"):
		var ft: Variant = datos.fuente_titulo
		if ft is Font:
			fuente_titulo = ft
		else:
			fuente_titulo = load(str(ft)) as Font if ResourceLoader.exists(str(ft)) else null
			if str(ft) != "" and fuente_titulo == null:
				push_error("UIBuilder: no se encontró la fuente " + str(ft))
	for k: String in datos:
		if k not in ["colores", "rarezas", "radio", "grosor_borde", "tam_fuente", "fuente", "fuente_titulo"]:
			push_warning("UIBuilder: el tema no usa la clave \"%s\"" % k)
	_rellenar_tema()


## Vuelve a armar el tema (por ejemplo, después de cambiar tema_base).
func refrescar_tema() -> void:
	_rellenar_tema()


func cargar_tema(ruta: String) -> void:
	var errores: PackedStringArray = []
	var datos: Variant = _leer_json(ruta, errores)
	_ruta_tema = ruta
	_seguir_archivo(ruta)
	if datos is Dictionary:
		aplicar_tema(datos)
	for e in errores:
		push_error("UIBuilder: " + e)


## Revisa una especificación sin abrirla. Devuelve la lista de errores (vacía si está bien).
func validar(spec: Dictionary) -> PackedStringArray:
	var errores: PackedStringArray = []
	var expandida: Variant = _expandir(spec, "raíz", errores, 0)
	if expandida is Dictionary:
		_validar(expandida, "raíz", errores, true)
	return errores


## Vuelve a construir una vista desde su origen (lo hace solo la recarga en caliente).
func recargar(vista: UIVista) -> void:
	vista.limpiar()
	vista.recargando = true
	_montar(vista)
	vista.recargando = false
	_ordenar()


# ================================================================ MONTAJE

func _montar(vista: UIVista) -> void:
	var errores: PackedStringArray = []
	var origen := "interfaz"
	var spec: Variant = vista.spec_origen
	if vista.ruta != "":
		origen = vista.ruta.get_file()
		spec = _leer_json(vista.ruta, errores)
		_seguir_archivo(vista.ruta)
		if spec != null and not (spec is Dictionary):
			errores.append("se esperaba un objeto {...} en la raíz")
			spec = null
	if spec is Dictionary:
		spec = _expandir(spec, "raíz", errores, 0)
	if spec is Dictionary:
		_validar(spec, "raíz", errores, true)
	if not errores.is_empty() or not (spec is Dictionary):
		vista.errores = errores
		for e in errores:
			push_error("UIBuilder: %s → %s" % [origen, e])
		_mostrar_errores(vista, origen, errores)
		return

	vista.capa = spec.get("capa", "ventana")
	vista.cerrar_con_esc = spec.get("cerrar_con_esc", true)
	if vista.capa == "modal":
		var velo := ColorRect.new()
		velo.name = "Velo"
		velo.color = paleta.velo
		velo.mouse_filter = Control.MOUSE_FILTER_STOP
		vista.add_child(velo)
		velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var contenido := construir_nodo(spec, UIVista.Contexto.new(vista))
	_colocar(vista, contenido, spec.get("posicion", "centro"), int(spec.get("margen", 0)))
	if vista.capa != "hud" and contenido.mouse_filter != Control.MOUSE_FILTER_STOP:
		contenido.mouse_filter = Control.MOUSE_FILTER_STOP
	if spec.get("movible", false) and vista.capa == "ventana":
		_hacer_movible(vista, contenido)
	if vista.capa == "modal":
		_enfocar_primero.call_deferred(contenido)
	_conectar_clics(contenido)
	if vista.capa != "hud" and not vista.recargando:
		_animar_apertura.call_deferred(vista, contenido)


func _conectar_clics(n: Node) -> void:
	if not al_clic.is_valid():
		return
	for b in n.find_children("*", "BaseButton", true, false):
		(b as BaseButton).pressed.connect(func() -> void:
			if al_clic.is_valid():
				al_clic.call())


func _animar_apertura(vista: UIVista, contenido: Control) -> void:
	await get_tree().process_frame          # que ya tenga su tamaño final
	if not is_instance_valid(contenido) or not contenido.is_inside_tree():
		return
	if al_abrir.is_valid():
		al_abrir.call(contenido, vista)
		return
	contenido.modulate.a = 0.0
	var tw := contenido.create_tween()
	tw.tween_property(contenido, "modulate:a", 1.0, 0.12)


func _colocar(vista: UIVista, contenido: Control, posicion: String, margen: int) -> void:
	var marco := MarginContainer.new()
	marco.name = "Marco"
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lado in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		marco.add_theme_constant_override(lado, margen)
	vista.add_child(marco)
	marco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p: Array = POSICIONES.get(posicion, POSICIONES.centro)
	contenido.size_flags_horizontal = p[0]
	contenido.size_flags_vertical = p[1]
	marco.add_child(contenido)


## La ventana se mueve arrastrando cualquier zona libre (fondo, título, textos).
func _hacer_movible(vista: UIVista, contenido: Control) -> void:
	var agarre := {"activo": false, "raton": Vector2.ZERO, "inicio": Vector2.ZERO}
	contenido.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			agarre.activo = ev.pressed
			agarre.raton = ev.global_position
			agarre.inicio = vista.desplazamiento
		elif ev is InputEventMouseMotion and agarre.activo:
			_desplazar(vista, contenido, agarre.inicio + ev.global_position - agarre.raton))
	_aplicar_desplazamiento(vista)
	_ajustar_al_montar(vista, contenido)


func _ajustar_al_montar(vista: UIVista, contenido: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(vista) and is_instance_valid(contenido) and contenido.is_inside_tree():
		_desplazar(vista, contenido, vista.desplazamiento)


## Mueve la ventana sin dejar que se salga de la pantalla.
func _desplazar(vista: UIVista, contenido: Control, d: Vector2) -> void:
	var base := contenido.global_position - vista.desplazamiento
	var libre := vista.size - contenido.size - base
	d.x = clampf(d.x, -base.x, maxf(libre.x, -base.x))
	d.y = clampf(d.y, -base.y, maxf(libre.y, -base.y))
	vista.desplazamiento = d
	if vista.ruta != "":
		_posiciones[vista.ruta] = d
	_aplicar_desplazamiento(vista)


func _aplicar_desplazamiento(vista: UIVista) -> void:
	var marco: Control = vista.get_node_or_null("Marco")
	if marco:
		var d := vista.desplazamiento
		marco.offset_left = d.x
		marco.offset_right = d.x
		marco.offset_top = d.y
		marco.offset_bottom = d.y


func _enfocar_primero(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var botones := n.find_children("*", "Button", true, false)
	if not botones.is_empty():
		(botones[0] as Button).grab_focus()


func _mostrar_errores(vista: UIVista, origen: String, errores: PackedStringArray) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "PanelError"
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := Label.new()
	t.theme_type_variation = "Texto_error"
	t.text = "Errores en %s" % origen
	v.add_child(t)
	for e in errores:
		var l := Label.new()
		l.text = "• " + e
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
		v.add_child(l)
	_colocar(vista, p, "centro", 0)


## Construye un nodo a partir de su especificación (lo usan también los contenedores).
func construir_nodo(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var comp: Dictionary = _componentes.get(spec.get("tipo", ""), {})
	var n: Control = null
	if not comp.is_empty():
		n = comp.crear.call(spec, ctx) as Control
	if n == null:
		n = Control.new()
	if spec.has("tamano"):
		n.custom_minimum_size = Vector2(float(spec.tamano[0]), float(spec.tamano[1]))
	if spec.get("expandir", false):
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if spec.get("expandir_v", false):
		n.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctx.enlazar(n, spec, "tooltip", func(x: Variant) -> void:
		n.tooltip_text = _txt(x)
		n.set_meta("ui_tooltip", n.tooltip_text))
	ctx.enlazar(n, spec, "visible", func(x: Variant) -> void: n.visible = UIVista.verdadero(x))
	if spec.has("id") and ctx.locales.is_empty():
		ctx.vista.ids[spec.id] = n
		n.name = String(spec.id).validate_node_name()
	return n


# ================================================================ PLANTILLAS

func _expandir(v: Variant, camino: String, errores: PackedStringArray, nivel: int) -> Variant:
	if nivel > 24:
		errores.append("%s: las plantillas se llaman entre sí sin fin" % camino)
		return null
	if v is Array:
		var salida: Array = []
		for i in v.size():
			var e: Variant = _expandir(v[i], "%s[%d]" % [camino, i], errores, nivel)
			if e != null or v[i] == null:      # si falló una plantilla, el error ya está anotado
				salida.append(e)
		return salida
	if not (v is Dictionary):
		return v
	var d: Dictionary = v
	if d.has("usar"):
		var nombre: String = str(d.usar)
		if not _plantillas.has(nombre):
			errores.append("%s: no existe la plantilla \"%s\"%s" % [camino, nombre, _sugerir(nombre, _plantillas.keys())])
			return null
		var pl: Dictionary = _plantillas[nombre]
		var params: Dictionary = pl.parametros.duplicate(true)
		var extra: Dictionary = {}
		for k: String in d:
			if k == "usar":
				continue
			if params.has(k):
				params[k] = d[k]
			else:
				extra[k] = d[k]
		var cuerpo: Variant = _sustituir(pl.cuerpo, params, "%s(%s)" % [camino, nombre], errores)
		if cuerpo is Dictionary:
			cuerpo.merge(extra, true)
		return _expandir(cuerpo, camino, errores, nivel + 1)
	var copia: Dictionary = {}
	for k: String in d:
		copia[k] = _expandir(d[k], "%s.%s" % [camino, k], errores, nivel)
	return copia


func _sustituir(v: Variant, params: Dictionary, camino: String, errores: PackedStringArray) -> Variant:
	if v is String and v.begins_with("$"):
		var p: String = v.substr(1)
		if params.has(p):
			var valor: Variant = params[p]
			return valor.duplicate(true) if (valor is Array or valor is Dictionary) else valor
		errores.append("%s: la plantilla usa \"%s\" pero no declara ese parámetro" % [camino, v])
		return null
	if v is Array:
		var salida: Array = []
		for e: Variant in v:
			var s: Variant = _sustituir(e, params, camino, errores)
			if e is String and e.begins_with("$") and s is Array:
				salida.append_array(s)      # "$hijos" dentro de una lista: se intercalan
			else:
				salida.append(s)
		return salida
	if v is Dictionary:
		var d: Dictionary = {}
		for k: String in v:
			d[k] = _sustituir(v[k], params, camino, errores)
		return d
	return v


# ================================================================ VALIDACIÓN

func _validar(spec: Dictionary, camino: String, errores: PackedStringArray, es_raiz := false) -> void:
	if not spec.has("tipo"):
		errores.append("%s: falta \"tipo\"" % camino)
		return
	var tipo: String = str(spec.tipo)
	if not _componentes.has(tipo):
		errores.append("%s: tipo desconocido \"%s\"%s" % [camino, tipo, _sugerir(tipo, _componentes.keys())])
		return
	var props: Variant = _componentes[tipo].props
	var permitidas: Dictionary = PROPS_COMUNES.duplicate()
	if props is Dictionary:
		permitidas.merge(props)
	if es_raiz:
		permitidas.merge(PROPS_RAIZ)
	for k: String in spec:
		if not permitidas.has(k):
			if PROPS_RAIZ.has(k):
				errores.append("%s: \"%s\" solo se puede usar en la raíz de la interfaz" % [camino, k])
			elif props is Dictionary:
				errores.append("%s: \"%s\" no admite la propiedad \"%s\"%s" % [camino, tipo, k, _sugerir(k, permitidas.keys())])
			continue
		var problema := _revisar_tipo(spec[k], permitidas[k])
		if problema != "":
			errores.append("%s.%s: %s" % [camino, k, problema])
	if spec.has("repetir") and not spec.has("elemento"):
		errores.append("%s: \"repetir\" necesita \"elemento\" (lo que se repite)" % camino)
	var hijos: Variant = spec.get("hijos")
	if hijos is Array:
		for i in hijos.size():
			if hijos[i] is Dictionary:
				_validar(hijos[i], "%s.hijos[%d]" % [camino, i], errores)
	if spec.get("elemento") is Dictionary:
		_validar(spec.elemento, camino + ".elemento", errores)
	var paginas: Variant = spec.get("paginas")
	if paginas is Array:
		for i in paginas.size():
			var pg: Variant = paginas[i]
			if not (pg is Dictionary):
				continue
			var cp := "%s.paginas[%d]" % [camino, i]
			if not pg.has("titulo"):
				errores.append("%s: a la página le falta \"titulo\"" % cp)
			for k: String in pg:
				if k != "titulo" and not PROPS_HIJOS.has(k):
					errores.append("%s: una página no admite \"%s\" (usa \"titulo\" e \"hijos\")" % [cp, k])
			_validar_hijos(pg, cp, errores)


func _validar_hijos(spec: Dictionary, camino: String, errores: PackedStringArray) -> void:
	var hijos: Variant = spec.get("hijos")
	if hijos is Array:
		for i in hijos.size():
			if hijos[i] is Dictionary:
				_validar(hijos[i], "%s.hijos[%d]" % [camino, i], errores)
	if spec.get("elemento") is Dictionary:
		_validar(spec.elemento, camino + ".elemento", errores)


func _revisar_tipo(v: Variant, tipo: String) -> String:
	var enlazable := tipo.ends_with("*")
	tipo = tipo.trim_suffix("*")
	var es_enlace: bool = v is String and v.begins_with("@")
	if es_enlace and tipo != "texto" and tipo != "enlace":
		if enlazable:
			return ""
		return "esta propiedad no admite enlaces (\"%s\")" % v
	match tipo:
		"texto":
			return "" if v is String else "debe ser un texto entre comillas"
		"numero":
			return "" if (v is float or v is int) else "debe ser un número"
		"bool":
			return "" if v is bool else "debe ser true o false"
		"color":
			if v is String and (paleta.has(v) or Color.html_is_valid(v)):
				return ""
			return "color desconocido \"%s\": usa \"#rrggbb\" o un color del tema%s" % [v, _sugerir(str(v), paleta.keys())]
		"tamano":
			if v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
				return ""
			return "debe ser [ancho, alto]"
		"dic":
			return "" if v is Dictionary else "debe ser un objeto {...}"
		"spec":
			return "" if v is Dictionary else "debe ser un componente {...}"
		"specs":
			if not (v is Array):
				return "debe ser una lista [...] de componentes"
			for e: Variant in v:
				if not (e is Dictionary):
					return "cada elemento debe ser un componente {...}"
			return ""
		"enlace":
			return "" if es_enlace else "debe ser un enlace al estado, como \"@tienda.objetos\""
		"paginas":
			if not (v is Array):
				return "debe ser una lista [...] de páginas"
			for e: Variant in v:
				if not (e is Dictionary):
					return "cada página debe ser {\"titulo\": \"...\", \"hijos\": [...]}"
			return ""
		"opciones":
			if not (v is Array):
				return "debe ser una lista [...]"
			for e: Variant in v:
				if not (e is String or e is Dictionary):
					return "cada opción debe ser un texto o un objeto {\"texto\": ...}"
			return ""
	if tipo.begins_with("enum:"):
		var validos := tipo.substr(5).split("|")
		if v is String and validos.has(v):
			return ""
		return "valor \"%s\" no válido; opciones: %s" % [v, ", ".join(validos)]
	return ""


func _sugerir(palabra: String, candidatas: Array) -> String:
	var mejor := ""
	var nota := 0.5
	for c: String in candidatas:
		var s := palabra.similarity(c)
		if s > nota:
			nota = s
			mejor = c
	return "" if mejor == "" else " (¿quisiste decir \"%s\"?)" % mejor


# ================================================================ ARCHIVOS

func _leer_json(ruta: String, errores: PackedStringArray) -> Variant:
	if not FileAccess.file_exists(ruta):
		errores.append("no existe el archivo " + ruta)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(ruta)) != OK:
		errores.append("JSON mal escrito en la línea %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
		return null
	return json.data


func _seguir_archivo(ruta: String) -> void:
	_archivos[ruta] = FileAccess.get_modified_time(ruta)


func _vigilar_archivos() -> void:
	if not recarga_en_caliente:
		return
	var cambiados: PackedStringArray = []
	for ruta: String in _archivos:
		var fecha := FileAccess.get_modified_time(ruta)
		if fecha != _archivos[ruta]:
			_archivos[ruta] = fecha
			cambiados.append(ruta)
	if cambiados.is_empty():
		return
	var todas := false
	for ruta in cambiados:
		if _rutas_plantillas.has(ruta):
			cargar_plantillas(ruta)
			todas = true
		elif ruta == _ruta_tema:
			cargar_tema(ruta)
	for v in _vistas.duplicate():
		if not v.is_queued_for_deletion() and (todas or cambiados.has(v.ruta)):
			recargar(v)
			print("UIBuilder: recargado ", v.ruta if v.ruta != "" else "(interfaz desde código)")


# ================================================================ PILA DE VENTANAS

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_raton = event.position
	var foco := get_viewport().gui_get_focus_owner()
	var en_campo := foco is LineEdit or foco is TextEdit
	if en_campo and event.is_action_pressed("ui_cancel"):
		foco.release_focus()        # Esc deja de escribir antes de cerrar ventanas
		get_viewport().set_input_as_handled()
		return
	if en_campo and event is InputEventMouseButton and event.pressed \
			and not foco.get_global_rect().has_point(event.position):
		foco.release_focus()        # clic fuera del campo: deja de escribir
	if event.is_action_pressed("ui_cancel"):
		var arriba := _vista_superior()
		if arriba and arriba.cerrar_con_esc:
			arriba.cerrar()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var v := _vista_bajo_raton()
		if v and v.capa == "ventana" and _vistas.back() != v:
			_al_frente.call_deferred(v)


## La ventana o modal que está más arriba (la que cerraría Esc).
func _vista_superior() -> UIVista:
	var mejor: UIVista = null
	for v in _vistas:
		if v.capa == "hud" or v.is_queued_for_deletion():
			continue
		if mejor == null or RANGO[v.capa] >= RANGO[mejor.capa]:
			mejor = v
	return mejor


func _vista_bajo_raton() -> UIVista:
	var c: Node = get_viewport().gui_get_hovered_control()
	while c:
		if c is UIVista:
			return c
		c = c.get_parent()
	return null


func _al_frente(vista: UIVista) -> void:
	_vistas.erase(vista)
	_vistas.append(vista)
	_ordenar()


## Orden de dibujo: HUD debajo, luego ventanas (la última usada arriba) y modales encima.
func _ordenar() -> void:
	var i := 0
	for rango in 3:
		for v in _vistas:
			if RANGO.get(v.capa, 1) == rango and v.get_parent() == lienzo:
				lienzo.move_child(v, i)
				i += 1


# ================================================================ TEMA

func _rellenar_tema() -> void:
	var t := tema
	t.clear()
	t.default_font_size = tam_fuente
	t.default_font = fuente
	t.set_color("font_color", "Label", paleta.texto)
	t.set_color("font_color", "Button", paleta.texto)
	t.set_color("font_hover_color", "Button", paleta.texto)
	t.set_color("font_focus_color", "Button", paleta.texto)
	t.set_color("font_pressed_color", "Button", paleta.acento)
	t.set_color("font_hover_pressed_color", "Button", paleta.acento)
	t.set_color("font_disabled_color", "Button", paleta.borde)
	t.set_stylebox("panel", "PanelContainer", _caja(paleta.fondo, paleta.borde, 10))
	t.set_stylebox("normal", "Button", _caja(paleta.boton, paleta.borde, 6))
	t.set_stylebox("hover", "Button", _caja(paleta.boton_hover, paleta.acento, 6))
	t.set_stylebox("pressed", "Button", _caja(paleta.boton_hover, paleta.acento, 6))
	t.set_stylebox("disabled", "Button", _caja(paleta.ranura, paleta.boton, 6))
	t.set_stylebox("focus", "Button", _caja(Color(0, 0, 0, 0), paleta.acento, 6))
	t.set_stylebox("background", "ProgressBar", _caja(paleta.barra_fondo, paleta.borde, 0))
	t.set_stylebox("fill", "ProgressBar", _caja(paleta.acento, Color(0, 0, 0, 0), 0))
	t.set_stylebox("panel", "TooltipPanel", _caja(paleta.fondo, paleta.acento, 6))
	t.set_color("font_color", "TooltipLabel", paleta.texto)

	# Pestañas
	t.set_stylebox("panel", "TabContainer", _caja(Color(0, 0, 0, 0.18), paleta.borde, 8))
	var pest_sel := _caja(paleta.boton_hover, paleta.acento, 6)
	var pest := _caja(paleta.boton, paleta.borde, 6)
	for sb: StyleBoxFlat in [pest_sel, pest]:
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.content_margin_left = 12
		sb.content_margin_right = 12
	t.set_stylebox("tab_selected", "TabContainer", pest_sel)
	t.set_stylebox("tab_unselected", "TabContainer", pest)
	t.set_stylebox("tab_hovered", "TabContainer", pest)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", paleta.acento)
	t.set_color("font_unselected_color", "TabContainer", paleta.texto_tenue)
	t.set_color("font_hovered_color", "TabContainer", paleta.texto)
	# Deslizador
	var riel := _caja(paleta.barra_fondo, paleta.borde, 0)
	riel.content_margin_top = 3
	riel.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", riel)
	t.set_stylebox("grabber_area", "HSlider", _caja(paleta.acento, Color(0, 0, 0, 0), 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _caja(paleta.acento, Color(0, 0, 0, 0), 0))
	# Casilla
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckBox", paleta.texto)
	t.set_color("checkbox_unchecked_color", "CheckBox", paleta.texto_tenue)
	t.set_color("checkbox_checked_color", "CheckBox", paleta.acento)
	# Campo de texto
	t.set_stylebox("normal", "LineEdit", _caja(paleta.ranura, paleta.borde, 6))
	t.set_stylebox("focus", "LineEdit", _caja(Color(0, 0, 0, 0), paleta.acento, 6))
	t.set_stylebox("read_only", "LineEdit", _caja(paleta.ranura, paleta.boton, 6))
	t.set_color("font_color", "LineEdit", paleta.texto)
	t.set_color("font_placeholder_color", "LineEdit", paleta.texto_tenue)
	t.set_color("caret_color", "LineEdit", paleta.acento)
	t.set_color("selection_color", "LineEdit", Color(paleta.acento, 0.35))

	t.set_type_variation("Titulo", "Label")
	t.set_color("font_color", "Titulo", paleta.acento)
	t.set_font_size("font_size", "Titulo", tam_fuente + 4)
	if fuente_titulo:
		t.set_font("font", "Titulo", fuente_titulo)
	t.set_type_variation("TextoBarra", "Label")
	t.set_font_size("font_size", "TextoBarra", maxi(tam_fuente - 4, 8))
	t.set_type_variation("CantidadRanura", "Label")
	t.set_font_size("font_size", "CantidadRanura", maxi(tam_fuente - 4, 8))
	t.set_type_variation("PanelMenu", "PanelContainer")
	t.set_stylebox("panel", "PanelMenu", _caja(paleta.fondo, paleta.acento, 6))
	t.set_type_variation("PanelError", "PanelContainer")
	t.set_stylebox("panel", "PanelError", _caja(paleta.fondo, paleta.error, 12))

	t.set_type_variation("Ranura", "Panel")
	t.set_stylebox("panel", "Ranura", _caja(paleta.ranura, paleta.get("borde_ranura", paleta.borde), 2))
	t.set_type_variation("Ranura_destino", "Panel")
	t.set_stylebox("panel", "Ranura_destino", _caja(paleta.boton_hover, paleta.acento, 2))
	for r: String in rarezas:
		t.set_type_variation("Ranura_" + r, "Panel")
		t.set_stylebox("panel", "Ranura_" + r, _caja(paleta.ranura, rarezas[r], 2))
	# Cada color del tema se puede usar por nombre en textos y barras.
	for c: String in paleta:
		t.set_type_variation("Texto_" + c, "Label")
		t.set_color("font_color", "Texto_" + c, paleta[c])
		t.set_type_variation("Barra_" + c, "ProgressBar")
		t.set_stylebox("fill", "Barra_" + c, _caja(paleta[c], Color(0, 0, 0, 0), 0))
	if tema_base:
		t.merge_with(tema_base)   # los estilos del juego mandan sobre los del kit


func _caja(fondo: Color, borde: Color, relleno := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(grosor_borde)
	s.set_corner_radius_all(radio)
	s.set_content_margin_all(relleno)
	return s


# ================================================================ COMPONENTES

func _registrar_basicos() -> void:
	registrar_componente("panel", _panel, _mas(PROPS_HIJOS, {"titulo": "texto", "separacion": "numero"}))
	registrar_componente("vertical", _vertical, _mas(PROPS_HIJOS, {"separacion": "numero", "alinear": "enum:inicio|centro|final"}))
	registrar_componente("horizontal", _horizontal, _mas(PROPS_HIJOS, {"separacion": "numero", "alinear": "enum:inicio|centro|final"}))
	registrar_componente("rejilla", _rejilla, _mas(PROPS_HIJOS, {"columnas": "numero", "separacion": "numero"}))
	registrar_componente("lista", _lista, _mas(PROPS_HIJOS, {"ancho": "numero", "alto": "numero", "separacion": "numero"}))
	registrar_componente("texto", _texto, {
		"texto": "texto", "estilo": "enum:normal|titulo|tenue", "color": "color", "tam": "numero",
		"alinear": "enum:izq|centro|der", "ajustar": "bool",
	})
	registrar_componente("boton", _boton, _mas(PROPS_ACCION, {"texto": "texto", "deshabilitado": "bool*"}))
	registrar_componente("barra", _barra, {
		"valor": "numero*", "max": "numero*", "color": "color", "texto": "texto", "mostrar_porcentaje": "bool",
	})
	registrar_componente("imagen", _imagen, {"textura": "texto"})
	registrar_componente("ranura", _ranura, _mas(_mas(PROPS_ACCION, PROPS_ARRASTRE), {
		"objeto": "enlace", "icono": "texto", "cantidad": "numero*", "rareza": "texto", "tam": "numero",
		"silueta": "texto",
	}))
	registrar_componente("ranuras", _ranuras, _mas(_mas(PROPS_ACCION, PROPS_ARRASTRE), {
		"objetos": "enlace", "columnas": "numero", "filas": "numero", "cantidad": "numero*", "tam_ranura": "numero",
	}))
	registrar_componente("dialogo", _dialogo, _mas(PROPS_ACCION, {
		"titulo": "texto", "texto": "texto", "ancho": "numero", "opciones": "opciones", "hijos": "specs",
	}))
	registrar_componente("espacio", _espacio, {})
	registrar_componente("pestanas", _pestanas, _mas(PROPS_ACCION, {
		"paginas": "paginas", "seleccion": "numero*", "ancho": "numero", "alto": "numero", "separacion": "numero",
	}))
	registrar_componente("deslizador", _deslizador, _mas(PROPS_ACCION, {
		"valor": "numero*", "min": "numero", "max": "numero", "paso": "numero", "mostrar_valor": "bool",
		"accion_al_soltar": "bool",
	}))
	registrar_componente("casilla", _casilla, _mas(PROPS_ACCION, {"texto": "texto", "valor": "bool*"}))
	registrar_componente("campo", _campo, _mas(PROPS_ACCION, {
		"texto": "texto", "pista": "texto", "ancho": "numero", "max_largo": "numero",
		"secreto": "bool", "limpiar_al_enviar": "bool", "accion_al_escribir": "texto",
	}))


func _mas(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := a.duplicate()
	d.merge(b)
	return d


func _panel(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(spec.get("separacion", 8)))
	p.add_child(v)
	if spec.has("titulo"):
		var t := Label.new()
		t.theme_type_variation = "Titulo"
		v.add_child(t)
		ctx.enlazar(t, spec, "titulo", func(x: Variant) -> void: t.text = _txt(x))
	ctx.hijos(v, spec)
	return p


func _vertical(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	return _caja_lineal(VBoxContainer.new(), spec, ctx)


func _horizontal(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	return _caja_lineal(HBoxContainer.new(), spec, ctx)


func _caja_lineal(caja: BoxContainer, spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	caja.add_theme_constant_override("separation", int(spec.get("separacion", 6)))
	match spec.get("alinear", "inicio"):
		"centro": caja.alignment = BoxContainer.ALIGNMENT_CENTER
		"final": caja.alignment = BoxContainer.ALIGNMENT_END
	ctx.hijos(caja, spec)
	return caja


func _rejilla(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var g := GridContainer.new()
	g.columns = maxi(int(spec.get("columnas", 2)), 1)
	var sep := int(spec.get("separacion", 6))
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	ctx.hijos(g, spec)
	return g


func _lista(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size = Vector2(float(spec.get("ancho", 220)), float(spec.get("alto", 200)))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", int(spec.get("separacion", 4)))
	s.add_child(v)
	ctx.hijos(v, spec)
	return s


func _texto(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var l := Label.new()
	match spec.get("estilo", "normal"):
		"titulo": l.theme_type_variation = "Titulo"
		"tenue": l.theme_type_variation = "Texto_texto_tenue"
	if spec.has("color"):
		if paleta.has(spec.color):
			l.theme_type_variation = "Texto_" + spec.color
		else:
			l.add_theme_color_override("font_color", _color(spec.color))
	if spec.has("tam"):
		l.add_theme_font_size_override("font_size", int(spec.tam))
	match spec.get("alinear", "izq"):
		"centro": l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		"der": l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if spec.get("ajustar", false):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctx.enlazar(l, spec, "texto", func(x: Variant) -> void: l.text = _txt(x))
	return l


func _boton(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var b := Button.new()
	_foco(b, ctx)
	ctx.enlazar(b, spec, "texto", func(x: Variant) -> void: b.text = _txt(x))
	ctx.enlazar(b, spec, "deshabilitado", func(x: Variant) -> void: b.disabled = UIVista.verdadero(x))
	if spec.has("accion"):
		b.pressed.connect(func() -> void: ctx.vista.emitir(spec.accion, ctx.datos(spec)))
	return b


func _barra(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var b := ProgressBar.new()
	b.show_percentage = spec.get("mostrar_porcentaje", false)
	b.custom_minimum_size = Vector2(160, 20)
	if spec.has("color"):
		if paleta.has(spec.color):
			b.theme_type_variation = "Barra_" + spec.color
		else:
			b.add_theme_stylebox_override("fill", _caja(_color(spec.color), Color(0, 0, 0, 0), 0))
	ctx.enlazar(b, spec, "max", func(x: Variant) -> void: b.max_value = maxf(_num(x, 100.0), 0.001), 100.0)
	ctx.enlazar(b, spec, "valor", func(x: Variant) -> void: b.value = _num(x, 0.0), b.max_value)
	if spec.has("texto"):
		var l := Label.new()
		l.theme_type_variation = "TextoBarra"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ctx.enlazar(l, spec, "texto", func(x: Variant) -> void: l.text = _txt(x))
	return b


func _imagen(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(48, 48)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx.enlazar(t, spec, "textura", func(x: Variant) -> void: t.texture = _textura(x))
	return t


## Una ranura suelta. Con "objeto": "@equipo.casco" muestra ese objeto del estado
## (icono, cantidad, rareza y nombre); sin él se usan "icono", "cantidad" y "rareza".
func _ranura(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var r := _nueva_ranura(float(spec.get("tam", 48)))
	# "silueta": imagen tenue que se ve cuando la ranura está vacía (casco, arma...)
	if spec.has("silueta"):
		var sil := _textura(spec.silueta)
		if sil != null:
			r.set_meta("ui_silueta", sil)
	var actual := {"objeto": null}
	if spec.has("objeto"):
		ctx.enlazar(r, spec, "objeto", func(x: Variant) -> void:
			actual.objeto = x
			_pintar_ranura(r, x))
	else:
		var icono: TextureRect = r.get_node("Icono")
		var cantidad: Label = r.get_node("Cantidad")
		ctx.enlazar(r, spec, "icono", func(x: Variant) -> void: icono.texture = _textura(x))
		ctx.enlazar(r, spec, "cantidad", func(x: Variant) -> void: cantidad.text = _txt_cantidad(x))
		ctx.enlazar(r, spec, "rareza", func(x: Variant) -> void: r.theme_type_variation = _variacion_rareza(x))
	var ruta := _ruta_del_estado(spec.get("objeto"), ctx)
	_conectar_ranura(r, spec, ctx, func() -> Dictionary:
		return {"lista": ruta, "indice": -1, "objeto": actual.objeto})
	return r


## Rejilla de ranuras enlazada a una lista del estado: "objetos": "@inventario.objetos".
## Cada elemento es null (vacía) o {"icono", "cantidad", "nombre", "descripcion", "rareza", ...}.
func _ranuras(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var g := GridContainer.new()
	var columnas := maxi(int(spec.get("columnas", 5)), 1)
	g.columns = columnas
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	var lado := float(spec.get("tam_ranura", 48))
	var ruta := _ruta_del_estado(spec.get("objetos"), ctx)
	var actual := {"lista": []}
	var pintar := func() -> void:
		var lista: Array = actual.lista
		for i in g.get_child_count():
			_pintar_ranura(g.get_child(i), lista[i] if i < lista.size() else null)
	# "cantidad" puede ir enlazada ("@mochila.capacidad"): sobran o faltan ranuras y se ajustan.
	var ajustar := func(x: Variant) -> void:
		var total := maxi(int(_num(x, columnas * 4.0)), 0)
		while g.get_child_count() > total:
			var ultima := g.get_child(g.get_child_count() - 1)
			g.remove_child(ultima)
			ultima.queue_free()
		while g.get_child_count() < total:
			var i := g.get_child_count()
			var r := _nueva_ranura(lado)
			_conectar_ranura(r, spec, ctx, func() -> Dictionary:
				var lista: Array = actual.lista
				return {"lista": ruta, "indice": i, "objeto": lista[i] if i < lista.size() else null})
			g.add_child(r)
		pintar.call()
	ctx.enlazar(g, spec, "cantidad", ajustar, columnas * int(spec.get("filas", 4)))
	ctx.enlazar(g, spec, "objetos", func(x: Variant) -> void:
		actual.lista = x if x is Array else []
		pintar.call())
	return g


## Clic y arrastre de una ranura. info: func() -> {"lista", "indice", "objeto"} de esa ranura.
func _conectar_ranura(r: Panel, spec: Dictionary, ctx: UIVista.Contexto, info: Callable) -> void:
	var pulsado := {"boton": ""}
	if spec.has("accion"):
		# El clic cuenta al soltar el botón, para que arrastrar un objeto no lo "use".
		r.gui_input.connect(func(ev: InputEvent) -> void:
			if not (ev is InputEventMouseButton):
				return
			var boton := ""
			if ev.button_index == MOUSE_BUTTON_LEFT:
				boton = "izq"
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				boton = "der"
			if boton == "":
				return
			if ev.pressed:
				pulsado.boton = boton
			elif pulsado.boton == boton:
				pulsado.boton = ""
				if Rect2(Vector2.ZERO, r.size).has_point(ev.position):
					var o: Dictionary = info.call()
					if al_clic.is_valid():
						al_clic.call()
					var extra := {"boton": boton, "objeto": o.objeto}
					if o.indice >= 0:
						extra["indice"] = o.indice
					ctx.vista.emitir(spec.accion, ctx.datos(spec, extra)))

	var arrastrable: bool = spec.get("arrastrable", false)
	var al_soltar: String = spec.get("al_soltar", "")
	if not arrastrable and al_soltar == "":
		return
	var grupo: String = spec.get("grupo", "")
	var acepta: Dictionary = spec.get("acepta", {})
	var intercambio: bool = spec.get("intercambio", true)

	var tomar := func(_pos: Vector2) -> Variant:
		if not arrastrable:
			return null
		var o: Dictionary = info.call()
		if not (o.objeto is Dictionary) or o.objeto.is_empty():
			return null
		pulsado.boton = ""
		r.set_drag_preview(_vista_previa(r, o.objeto))
		_arrastre_origen = r
		(r.get_node("Icono") as Control).modulate.a = 0.3
		return {
			"ui_arrastre": true, "grupo": grupo, "acepta": acepta, "nodo": r,
			"desde": o.lista, "desde_indice": o.indice, "objeto": o.objeto,
		}

	var puede := func(_pos: Vector2, d: Variant) -> bool:
		if al_soltar == "" or not (d is Dictionary) or not d.get("ui_arrastre", false):
			return false
		if d.grupo != grupo or d.nodo == r or not _encaja(acepta, d.objeto):
			return false
		# Si esta ranura está ocupada se intercambian: lo de aquí debe caber en el origen.
		var aqui: Variant = info.call().objeto
		if intercambio and aqui is Dictionary and not aqui.is_empty() and not _encaja(d.acepta, aqui):
			return false
		_resaltar(r)
		return true

	var soltar := func(_pos: Vector2, d: Variant) -> void:
		_quitar_resalte()
		var o: Dictionary = info.call()
		ctx.vista.emitir(al_soltar, ctx.datos(spec, {
			"desde": d.desde, "desde_indice": d.desde_indice,
			"hasta": o.lista, "hasta_indice": o.indice,
			"objeto": d.objeto, "objeto_destino": o.objeto,
		}))

	r.set_drag_forwarding(tomar, puede, soltar)
	r.mouse_exited.connect(func() -> void:
		if _arrastre_destino == r:
			_quitar_resalte())


## true si el objeto tiene todos los campos que pide "acepta": {"clase": "casco"}.
func _encaja(acepta: Dictionary, objeto: Variant) -> bool:
	if acepta.is_empty():
		return true
	if not (objeto is Dictionary):
		return false
	for k: String in acepta:
		if not objeto.has(k) or typeof(objeto[k]) != typeof(acepta[k]) or objeto[k] != acepta[k]:
			return false
	return true


func _vista_previa(r: Control, objeto: Dictionary) -> Control:
	var raiz := Control.new()
	raiz.theme = tema
	var textura := _textura(objeto.get("icono"))
	if textura:
		var t := TextureRect.new()
		t.texture = textura
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size = r.size - Vector2(10, 10)
		t.position = -t.size / 2.0
		t.modulate.a = 0.85
		raiz.add_child(t)
	else:
		var l := Label.new()
		l.text = _txt(objeto.get("nombre"))
		l.position = Vector2(12, 4)
		raiz.add_child(l)
	return raiz


func _resaltar(r: Control) -> void:
	if _arrastre_destino == r:
		return
	_quitar_resalte()
	_arrastre_destino = r
	r.set_meta("ui_variacion", r.theme_type_variation)
	r.theme_type_variation = "Ranura_destino"


func _quitar_resalte() -> void:
	var r := _arrastre_destino
	_arrastre_destino = null
	if is_instance_valid(r) and r.theme_type_variation == &"Ranura_destino":
		r.theme_type_variation = r.get_meta("ui_variacion", &"Ranura")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_quitar_resalte()
		if is_instance_valid(_arrastre_origen):
			(_arrastre_origen.get_node("Icono") as Control).modulate.a = 1.0
		_arrastre_origen = null


## La ruta del estado a la que apunta un enlace ("" si es fijo o una variable local).
func _ruta_del_estado(valor: Variant, ctx: UIVista.Contexto) -> String:
	var an := UIVista.analizar(valor)
	if an.is_empty() or an.modo != "ruta" or ctx.locales.has(String(an.ruta).get_slice(".", 0)):
		return ""
	return an.ruta


func _nueva_ranura(lado: float) -> Panel:
	var r := RanuraUI.new()
	r.constructor = self
	r.theme_type_variation = "Ranura"
	r.custom_minimum_size = Vector2(lado, lado)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # cuadrada aunque la columna sea más ancha
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icono := TextureRect.new()
	icono.name = "Icono"
	icono.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icono.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(icono)
	icono.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	var marcas := Control.new()
	marcas.name = "Marcas"
	marcas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(marcas)
	marcas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var num := Label.new()
	num.name = "Cantidad"
	num.theme_type_variation = "CantidadRanura"
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(num)
	num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	return r


func _pintar_ranura(r: Panel, objeto: Variant) -> void:
	var o: Dictionary = objeto if objeto is Dictionary else {}
	if r is RanuraUI:
		r.objeto = o
	var icono: TextureRect = r.get_node("Icono")
	var alfa := icono.modulate.a       # se conserva si se está arrastrando desde aquí
	icono.modulate = Color(1, 1, 1, alfa)
	var marcas: Control = r.get_node("Marcas")
	for m in marcas.get_children():
		marcas.remove_child(m)
		m.queue_free()
	if decorar_ranura.is_valid() and not o.is_empty():
		decorar_ranura.call(r, marcas, o)
	if o.is_empty() and r.has_meta("ui_silueta"):
		var sil := TextureRect.new()
		sil.texture = r.get_meta("ui_silueta")
		sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sil.modulate = Color(paleta.texto_tenue, 0.35)
		marcas.add_child(sil)
		sil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	(r.get_node("Icono") as TextureRect).texture = _textura(o.get("icono"))
	(r.get_node("Cantidad") as Label).text = _txt_cantidad(o.get("cantidad"))
	r.theme_type_variation = _variacion_rareza(o.get("rareza"))
	var pista := _txt(o.get("nombre"))
	if o.get("descripcion"):
		pista += "\n" + _txt(o.descripcion)
	r.tooltip_text = pista if pista != "" else str(r.get_meta("ui_tooltip", ""))


func _dialogo(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	if spec.has("titulo"):
		var t := Label.new()
		t.theme_type_variation = "Titulo"
		v.add_child(t)
		ctx.enlazar(t, spec, "titulo", func(x: Variant) -> void: t.text = _txt(x))
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = float(spec.get("ancho", 360))
	v.add_child(l)
	ctx.enlazar(l, spec, "texto", func(x: Variant) -> void: l.text = _txt(x))
	ctx.hijos(v, spec)
	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.add_theme_constant_override("separation", 6)
	v.add_child(fila)
	var opciones: Array = spec.get("opciones", [])
	for i in opciones.size():
		var op: Dictionary = opciones[i] if opciones[i] is Dictionary else {"texto": str(opciones[i])}
		var b := Button.new()
		_foco(b, ctx)
		ctx.enlazar(b, op, "texto", func(x: Variant) -> void: b.text = _txt(x))
		var nombre: String = op.get("accion", spec.get("accion", "opcion"))
		b.pressed.connect(func() -> void:
			ctx.vista.emitir(nombre, ctx.datos(op, {"indice": i, "texto": b.text})))
		fila.add_child(b)
	return p


## Pestañas: "paginas": [{"titulo": "Misiones", "hijos": [...]}, ...]
## "seleccion": "@ui.pestana_diario" recuerda la pestaña abierta en el estado.
func _pestanas(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var tc := TabContainer.new()
	tc.custom_minimum_size = Vector2(float(spec.get("ancho", 340)), float(spec.get("alto", 220)))
	if ctx.vista.capa != "modal":
		tc.get_tab_bar().focus_mode = Control.FOCUS_NONE
	var paginas: Array = spec.get("paginas", [])
	for i in paginas.size():
		var pg: Dictionary = paginas[i]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", int(spec.get("separacion", 6)))
		tc.add_child(v)
		ctx.hijos(v, pg)
		ctx.enlazar(v, pg, "titulo", func(x: Variant) -> void: tc.set_tab_title(i, _txt(x)))
	var aplicando := {"si": false}
	ctx.enlazar(tc, spec, "seleccion", func(x: Variant) -> void:
		var n := clampi(int(_num(x, 0.0)), 0, maxi(tc.get_tab_count() - 1, 0))
		if tc.get_tab_count() > 0 and tc.current_tab != n:
			aplicando.si = true
			tc.current_tab = n
			aplicando.si = false)
	var escribir := _escritor(spec, "seleccion", ctx)
	tc.tab_changed.connect(func(i: int) -> void:
		if aplicando.si:
			return
		if escribir.is_valid():
			escribir.call(i)
		if spec.has("accion"):
			ctx.vista.emitir(spec.accion, ctx.datos(spec, {"indice": i, "titulo": tc.get_tab_title(i)})))
	return tc


## Deslizador. Con "valor": "@opciones.volumen" lee y escribe ese dato del estado.
func _deslizador(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var s := HSlider.new()
	s.min_value = float(spec.get("min", 0))
	s.max_value = float(spec.get("max", 100))
	s.step = float(spec.get("paso", 1))
	s.custom_minimum_size = Vector2(160, 20)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foco(s, ctx)
	var etiqueta: Label = null
	if spec.get("mostrar_valor", false):
		etiqueta = Label.new()
		etiqueta.custom_minimum_size.x = 44
		etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var pintar := func() -> void:
		if etiqueta:
			etiqueta.text = _txt(s.value)
	ctx.enlazar(s, spec, "valor", func(x: Variant) -> void:
		s.set_value_no_signal(_num(x, s.min_value))
		pintar.call(), s.min_value)
	var escribir := _escritor(spec, "valor", ctx)
	# "accion_al_soltar": la acción se emite al soltar el deslizador y no mientras se arrastra
	# (para cosas caras de aplicar, como la escala de la interfaz).
	var al_soltar: bool = spec.get("accion_al_soltar", false)
	s.value_changed.connect(func(v: float) -> void:
		pintar.call()
		if escribir.is_valid():
			escribir.call(v)
		if spec.has("accion") and not (al_soltar and s.has_meta("ui_arrastrando")):
			ctx.vista.emitir(spec.accion, ctx.datos(spec, {"valor": v})))
	if al_soltar:
		s.drag_started.connect(func() -> void: s.set_meta("ui_arrastrando", true))
		s.drag_ended.connect(func(cambio: bool) -> void:
			s.remove_meta("ui_arrastrando")
			if cambio and spec.has("accion"):
				ctx.vista.emitir(spec.accion, ctx.datos(spec, {"valor": s.value})))
	if etiqueta == null:
		return s
	var h := HBoxContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(s)
	h.add_child(etiqueta)
	return h


## Casilla de verificación. Con "valor": "@opciones.pantalla_completa" lee y escribe el estado.
func _casilla(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var c := CheckBox.new()
	_foco(c, ctx)
	ctx.enlazar(c, spec, "texto", func(x: Variant) -> void: c.text = _txt(x))
	ctx.enlazar(c, spec, "valor", func(x: Variant) -> void: c.set_pressed_no_signal(UIVista.verdadero(x)))
	var escribir := _escritor(spec, "valor", ctx)
	c.toggled.connect(func(activa: bool) -> void:
		if escribir.is_valid():
			escribir.call(activa)
		if spec.has("accion"):
			ctx.vista.emitir(spec.accion, ctx.datos(spec, {"valor": activa})))
	return c


## Campo de texto. Con "texto": "@jugador.nombre" lee y escribe el estado.
## "accion" se emite al pulsar Enter, con {"texto": ...}.
func _campo(spec: Dictionary, ctx: UIVista.Contexto) -> Control:
	var e := LineEdit.new()
	e.custom_minimum_size.x = float(spec.get("ancho", 200))
	e.secret = spec.get("secreto", false)
	if spec.has("max_largo"):
		e.max_length = int(spec.max_largo)
	ctx.enlazar(e, spec, "pista", func(x: Variant) -> void: e.placeholder_text = _txt(x))
	ctx.enlazar(e, spec, "texto", func(x: Variant) -> void:
		var t := _txt(x)
		if e.text != t:
			e.text = t)
	var escribir := _escritor(spec, "texto", ctx)
	if escribir.is_valid():
		e.text_changed.connect(func(t: String) -> void: escribir.call(t))
	# "accion_al_escribir": otra acción que se emite con cada letra ({"texto": ...})
	if spec.has("accion_al_escribir"):
		e.text_changed.connect(func(t: String) -> void:
			ctx.vista.emitir(spec.accion_al_escribir, ctx.datos(spec, {"texto": t})))
	var limpiar: bool = spec.get("limpiar_al_enviar", false)
	e.text_submitted.connect(func(t: String) -> void:
		if spec.has("accion"):
			ctx.vista.emitir(spec.accion, ctx.datos(spec, {"texto": t}))
		if limpiar:
			e.clear()
			if escribir.is_valid():
				escribir.call(""))
	return e


## Si spec[prop] es un enlace al estado ("@opciones.volumen"), devuelve una función
## que escribe ahí; si no, un Callable vacío.
func _escritor(spec: Dictionary, prop: String, ctx: UIVista.Contexto) -> Callable:
	var v: Variant = spec.get(prop)
	if v is String and v.begins_with("@!"):
		return Callable()
	var ruta := _ruta_del_estado(v, ctx)
	if ruta == "":
		return Callable()
	var est: UIEstado = ctx.vista.estado
	return func(x: Variant) -> void: est.poner(ruta, x)


func _espacio(_spec: Dictionary, _ctx: UIVista.Contexto) -> Control:
	var e := Control.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.size_flags_vertical = Control.SIZE_EXPAND_FILL
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return e


# ================================================================ AYUDAS

## Fuera de los modales, los botones no toman el foco del teclado: así Espacio o
## Enter no vuelven a pulsar el último botón mientras juegas.
func _foco(b: Control, ctx: UIVista.Contexto) -> void:
	if ctx.vista.capa != "modal":
		b.focus_mode = Control.FOCUS_NONE


func _txt(x: Variant) -> String:
	return UIVista.formatear(x)


func _txt_cantidad(x: Variant) -> String:
	return _txt(x) if _num(x, 0.0) > 1.0 else ""


func _num(x: Variant, defecto: float) -> float:
	if x is float or x is int:
		return float(x)
	if x is String and x.is_valid_float():
		return x.to_float()
	return defecto


func _variacion_rareza(x: Variant) -> StringName:
	return StringName("Ranura_" + str(x)) if rarezas.has(x) else &"Ranura"


func _textura(x: Variant) -> Texture2D:
	if x is Texture2D:
		return x
	if x is String and x != "" and ResourceLoader.exists(x):
		return load(x) as Texture2D
	return null


func _color(v: Variant) -> Color:
	if v is Color:
		return v
	if paleta.has(v):
		return paleta[v]
	return Color.from_string(str(v), Color.MAGENTA)


func _crear_avisos() -> void:
	lienzo_avisos = CanvasLayer.new()
	lienzo_avisos.name = "UIAvisos"
	lienzo_avisos.layer = 101
	add_child(lienzo_avisos)
	var marco := MarginContainer.new()
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lado in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		marco.add_theme_constant_override(lado, 16)
	lienzo_avisos.add_child(marco)
	marco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avisos = VBoxContainer.new()
	_avisos.theme = tema
	_avisos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avisos.add_theme_constant_override("separation", 6)
	var p: Array = POSICIONES.get(esquina_avisos, POSICIONES.arriba_der)
	_avisos.size_flags_horizontal = p[0]
	_avisos.size_flags_vertical = p[1]
	marco.add_child(_avisos)


## Ranura que muestra un tooltip con estadísticas en vez de texto plano.
class RanuraUI extends Panel:
	var objeto: Dictionary = {}
	var constructor: Node

	func _make_custom_tooltip(_texto: String) -> Object:
		if objeto.is_empty() or constructor == null:
			return null
		return constructor.crear_tooltip(objeto)
