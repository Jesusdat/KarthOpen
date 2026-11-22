@tool
extends VBoxContainer

# Pestaña "Datos": edita las tablas de res://datos/ sin tocar código.
# - Ficha: una entrada con todos sus campos.
# - Tabla: todas las entradas lado a lado (ideal para balancear). Clic en un título ordena.
# - Revisar: busca referencias rotas (objetos, monstruos, iconos o sprites que no existen)
#   y precios que permiten ganar dinero comprando y vendiendo.

const RAREZAS := ["Común", "Poco común", "Raro", "Épico", "Legendario"]
const COLORES_RAREZA := [Color(0.78, 0.78, 0.8), Color(0.45, 0.85, 0.45), Color(0.4, 0.65, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.65, 0.2)]
# Campos de texto con valores conocidos: se muestran como lista desplegable.
const OPCIONES := {
	"type": ["kill", "collect"],
	"slot": ["arma", "armadura", "casco", "botas", "amuleto", "especial"],
	"use": ["heal", "energy", "buff_xp", "buff_dmg"],
	"faction": ["enjambre", "antiguos"],
	"bando": ["colonos", "enjambre", "antiguos"],
	"apunta": ["objetivo", "propio", "cursor"],
	"forma": ["objetivo", "circulo", "rombo", "cuadrado", "cruz", "linea", "cono"],
	"fx": ["disparo", "rafaga", "curacion", "pulso", "escudo"],
}
const TIPOS_CAMPO := ["Número entero", "Número decimal", "Texto", "Sí/No", "Color", "Lista [ ]", "Diccionario { }"]
const STATS_VALIDOS := ["hp", "damage", "energy", "regen", "speed", "shield"]
const TABLAS_MISION := ["misiones_colonos", "misiones_enjambre", "misiones_antiguos", "contratos"]

var cache := {}        # tabla -> datos en memoria (Dictionary o Array)
var sucio := {}        # tabla -> true si hay cambios sin guardar
var tabla := ""
var ids: Array = []    # claves (dict) o índices (lista) en el orden mostrado
var visibles: Array = []  # posiciones de ids que pasan el filtro
var sel := -1          # posición en ids
var orden_tabla := {"col": -1, "asc": true}
var _llenando := false

var sel_tabla: OptionButton
var lbl_estado: Label
var buscar: LineEdit
var lista: ItemList
var tabs: TabContainer
var ficha: VBoxContainer
var arbol: Tree
var columnas: Array = []
var reporte: RichTextLabel
var confirmar: ConfirmationDialog
var _accion_confirmada: Callable

func _ready() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	size_flags_horizontal = SIZE_EXPAND_FILL
	_armar_ui()
	for t in DatosJuego.TABLAS:
		sel_tabla.add_item(DatosJuego.TABLAS[t]["titulo"])
		sel_tabla.set_item_metadata(sel_tabla.item_count - 1, t)
	_cambiar_tabla(0)

# ---------------------------------------------------------------- interfaz

func _armar_ui() -> void:
	var barra := HBoxContainer.new()
	add_child(barra)
	sel_tabla = OptionButton.new()
	sel_tabla.custom_minimum_size.x = 220
	sel_tabla.item_selected.connect(_cambiar_tabla)
	barra.add_child(sel_tabla)
	_boton(barra, "Guardar", "Save", _guardar_actual)
	_boton(barra, "Guardar todo", "Save", _guardar_todo)
	_boton(barra, "Recargar", "Reload", _recargar)
	_boton(barra, "Revisar todo", "StatusWarning", _revisar)
	lbl_estado = Label.new()
	lbl_estado.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	barra.add_child(lbl_estado)

	var vsplit := VSplitContainer.new()
	vsplit.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(vsplit)
	var split := HSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	vsplit.add_child(split)

	var izq := VBoxContainer.new()
	izq.custom_minimum_size.x = 280
	split.add_child(izq)
	buscar = LineEdit.new()
	buscar.placeholder_text = "Buscar…"
	buscar.clear_button_enabled = true
	buscar.text_changed.connect(func(_t): _llenar_lista())
	izq.add_child(buscar)
	lista = ItemList.new()
	lista.size_flags_vertical = SIZE_EXPAND_FILL
	lista.item_selected.connect(func(i): _seleccionar(int(lista.get_item_metadata(i))))
	izq.add_child(lista)
	var botones := HBoxContainer.new()
	izq.add_child(botones)
	_boton(botones, "Nuevo", "Add", _nuevo)
	_boton(botones, "Duplicar", "Duplicate", _duplicar)
	_boton(botones, "", "Remove", _borrar).tooltip_text = "Borrar"
	_boton(botones, "", "MoveUp", func(): _mover(-1)).tooltip_text = "Subir"
	_boton(botones, "", "MoveDown", func(): _mover(1)).tooltip_text = "Bajar"

	tabs = TabContainer.new()
	tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	split.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.name = "Ficha"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	ficha = VBoxContainer.new()
	ficha.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(ficha)
	arbol = Tree.new()
	arbol.name = "Tabla"
	arbol.hide_root = true
	arbol.column_titles_visible = true
	arbol.select_mode = Tree.SELECT_ROW
	arbol.item_edited.connect(_celda_editada)
	arbol.column_title_clicked.connect(_ordenar_columna)
	arbol.item_selected.connect(func():
		var it := arbol.get_selected()
		if it: _seleccionar(int(it.get_metadata(0)), false))
	tabs.add_child(arbol)
	tabs.tab_changed.connect(func(_t): _refrescar_vista())

	reporte = RichTextLabel.new()
	reporte.bbcode_enabled = true
	reporte.custom_minimum_size.y = 130
	reporte.meta_clicked.connect(_ir_a)
	reporte.text = "[color=gray]Pulsa «Revisar todo» para buscar errores en los datos.[/color]"
	vsplit.add_child(reporte)

	confirmar = ConfirmationDialog.new()
	confirmar.confirmed.connect(func(): if _accion_confirmada.is_valid(): _accion_confirmada.call())
	add_child(confirmar)

func _boton(padre: Control, texto: String, icono: String, accion: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.icon = _icono(icono)
	b.pressed.connect(accion)
	padre.add_child(b)
	return b

func _icono(nombre: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var tema := EditorInterface.get_editor_theme()
	return tema.get_icon(nombre, "EditorIcons") if tema and tema.has_icon(nombre, "EditorIcons") else null

func _preguntar(texto: String, accion: Callable) -> void:
	confirmar.dialog_text = texto
	_accion_confirmada = accion
	confirmar.popup_centered()

# ---------------------------------------------------------------- datos

func _datos(t: String) -> Variant:
	if not cache.has(t):
		cache[t] = DatosJuego.cargar(t)
	return cache[t]

func _entrada(pos: int) -> Dictionary:
	if pos < 0 or pos >= ids.size():
		return {}
	return _datos(tabla)[ids[pos]]

func _marcar() -> void:
	sucio[tabla] = true
	_actualizar_estado()

func _actualizar_estado() -> void:
	var pendientes := []
	for t in sucio:
		if sucio[t]:
			pendientes.append(DatosJuego.TABLAS[t]["titulo"])
	if pendientes.is_empty():
		lbl_estado.text = "Todo guardado"
		lbl_estado.modulate = Color(0.6, 0.9, 0.6)
	else:
		lbl_estado.text = "● Sin guardar: " + ", ".join(pendientes)
		lbl_estado.modulate = Color(1, 0.75, 0.35)
	for i in sel_tabla.item_count:
		var t: String = sel_tabla.get_item_metadata(i)
		sel_tabla.set_item_text(i, DatosJuego.TABLAS[t]["titulo"] + (" ●" if sucio.get(t, false) else ""))

func _cambiar_tabla(i: int) -> void:
	tabla = sel_tabla.get_item_metadata(i)
	orden_tabla = {"col": -1, "asc": true}
	_recalcular_ids()
	sel = 0 if ids.size() > 0 else -1
	_llenar_lista()
	_refrescar_vista()
	_actualizar_estado()

func _recalcular_ids() -> void:
	var d = _datos(tabla)
	ids = d.keys() if d is Dictionary else range(d.size())

func _guardar_actual() -> void:
	_guardar(tabla)

func _guardar_todo() -> void:
	for t in sucio.keys():
		if sucio[t]:
			_guardar(t)

func _guardar(t: String) -> void:
	_aplicar_foco()
	var err := DatosJuego.guardar(t, _datos(t))
	if err != OK:
		push_error("No se pudo guardar %s (error %d)" % [t, err])
		return
	sucio[t] = false
	_actualizar_estado()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	print("Datos guardados: ", DatosJuego.ruta(t))

func _recargar() -> void:
	var hacer := func():
		cache.erase(tabla)
		sucio[tabla] = false
		_cambiar_tabla(sel_tabla.selected)
	if sucio.get(tabla, false):
		_preguntar("¿Descartar los cambios sin guardar de esta tabla?", hacer)
	else:
		hacer.call()

# Fuerza que el campo con el foco aplique su texto (los de lista/diccionario se aplican al salir).
func _aplicar_foco() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f and is_ancestor_of(f):
		f.release_focus()

# ---------------------------------------------------------------- lista izquierda

func _etiqueta(pos: int) -> String:
	var e := _entrada(pos)
	var nombre := str(e.get("name", e.get("title", e.get("nombre", ""))))
	if DatosJuego.es_lista(tabla):
		var extra := ""
		if e.has("region"):
			extra = "  [%s]" % e["region"]
		return "%03d · %s%s" % [pos, nombre, extra]
	var k := str(ids[pos])
	return k if nombre == "" or nombre == k else "%s — %s" % [k, nombre]

func _llenar_lista() -> void:
	lista.clear()
	visibles.clear()
	var filtro := buscar.text.strip_edges().to_lower()
	for pos in ids.size():
		var txt := _etiqueta(pos)
		if filtro != "" and not txt.to_lower().contains(filtro):
			continue
		var i := lista.add_item(txt)
		lista.set_item_metadata(i, pos)
		visibles.append(pos)
		var e := _entrada(pos)
		if tabla == "objetos":
			lista.set_item_custom_fg_color(i, COLORES_RAREZA[clampi(int(e.get("rareza", 0)), 0, 4)])
		elif e.has("boss"):
			lista.set_item_custom_fg_color(i, Color(1, 0.6, 0.3))
		if pos == sel:
			lista.select(i)
	if visibles.has(sel):
		lista.ensure_current_is_visible()

func _seleccionar(pos: int, refrescar_arbol := true) -> void:
	sel = pos
	var idx := visibles.find(pos)
	if idx >= 0 and not lista.is_selected(idx):
		lista.select(idx)
	if tabs.current_tab == 0 or refrescar_arbol:
		_refrescar_vista()

func _refrescar_vista() -> void:
	if tabs.current_tab == 0:
		_armar_ficha()
	else:
		_armar_arbol()

func _nuevo() -> void:
	var plantilla: Dictionary = DatosJuego.TABLAS[tabla].get("plantilla", {}).duplicate(true)
	_insertar(plantilla, "Nuevo objeto" if tabla == "objetos" else "nuevo")

func _duplicar() -> void:
	if sel < 0:
		return
	var copia := _entrada(sel).duplicate(true)
	var base := ""
	if not DatosJuego.es_lista(tabla):
		base = str(ids[sel]) + (" (copia)" if tabla == "objetos" else "_copia")
	_insertar(copia, base)

func _insertar(campos: Dictionary, base: String) -> void:
	var d = _datos(tabla)
	if d is Array:
		var en: int = sel + 1 if sel >= 0 else d.size()
		d.insert(en, campos)
		_recalcular_ids()
		sel = en
	else:
		var k := base
		var n := 1
		while d.has(k):
			n += 1
			k = "%s_%d" % [base, n]
		var nuevo := {}
		for key in d:
			nuevo[key] = d[key]
			if sel >= 0 and key == ids[sel]:
				nuevo[k] = campos
		if not nuevo.has(k):
			nuevo[k] = campos
		cache[tabla] = nuevo
		_recalcular_ids()
		sel = ids.find(k)
	_marcar()
	_llenar_lista()
	_refrescar_vista()

func _borrar() -> void:
	if sel < 0:
		return
	_preguntar("¿Borrar «%s»?" % _etiqueta(sel), func():
		var d = _datos(tabla)
		if d is Array:
			d.remove_at(sel)
		else:
			d.erase(ids[sel])
		_recalcular_ids()
		sel = mini(sel, ids.size() - 1)
		_marcar()
		_llenar_lista()
		_refrescar_vista())

func _mover(dir: int) -> void:
	var destino := sel + dir
	if sel < 0 or destino < 0 or destino >= ids.size():
		return
	var d = _datos(tabla)
	if d is Array:
		var tmp = d[sel]
		d[sel] = d[destino]
		d[destino] = tmp
	else:
		var orden: Array = ids.duplicate()
		var tmp = orden[sel]
		orden[sel] = orden[destino]
		orden[destino] = tmp
		var nuevo := {}
		for k in orden:
			nuevo[k] = d[k]
		cache[tabla] = nuevo
	_recalcular_ids()
	sel = destino
	_marcar()
	_llenar_lista()
	_refrescar_vista()

# ---------------------------------------------------------------- ficha

func _armar_ficha() -> void:
	for c in ficha.get_children():
		c.queue_free()
	if sel < 0:
		var vacio := Label.new()
		vacio.text = "Tabla vacía. Pulsa «Nuevo»."
		ficha.add_child(vacio)
		return
	var e := _entrada(sel)
	if not DatosJuego.es_lista(tabla):
		var fila := _fila("Id (nombre interno)")
		var id_edit := LineEdit.new()
		id_edit.text = str(ids[sel])
		id_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		id_edit.tooltip_text = "Al cambiarlo se actualiza en las demás tablas. Pulsa Enter para aplicar."
		id_edit.text_submitted.connect(func(t): _renombrar(str(ids[sel]), t.strip_edges()))
		fila.add_child(id_edit)
	for campo in e.keys():
		_fila_campo(e, campo)
	ficha.add_child(HSeparator.new())
	var agregar := HBoxContainer.new()
	ficha.add_child(agregar)
	var nombre := LineEdit.new()
	nombre.placeholder_text = "campo nuevo"
	nombre.custom_minimum_size.x = 160
	agregar.add_child(nombre)
	var tipo := OptionButton.new()
	for t in TIPOS_CAMPO:
		tipo.add_item(t)
	agregar.add_child(tipo)
	var b := Button.new()
	b.text = "Agregar campo"
	b.pressed.connect(func():
		var c := nombre.text.strip_edges()
		if c == "" or e.has(c):
			return
		e[c] = [0, 0.0, "", false, Color.WHITE, [], {}][tipo.selected]
		_marcar()
		_armar_ficha())
	agregar.add_child(b)

func _fila(texto: String) -> HBoxContainer:
	var fila := HBoxContainer.new()
	ficha.add_child(fila)
	var l := Label.new()
	l.text = texto
	l.custom_minimum_size.x = 150
	fila.add_child(l)
	return fila

func _fila_campo(e: Dictionary, campo: String) -> void:
	var fila := _fila(campo)
	var v = e[campo]
	var ctrl: Control
	if campo == "rareza" and v is int:
		var ob := OptionButton.new()
		for i in RAREZAS.size():
			ob.add_item(RAREZAS[i])
			ob.set_item_icon(i, _muestra_color(COLORES_RAREZA[i]))
		ob.selected = clampi(v, 0, 4)
		ob.item_selected.connect(func(i): _poner(e, campo, i, true))
		ctrl = ob
	elif OPCIONES.has(campo) and v is String:
		var ob := OptionButton.new()
		var opciones: Array = OPCIONES[campo].duplicate()
		if not opciones.has(v):
			opciones.append(v)
		for o in opciones:
			ob.add_item(o)
		ob.selected = opciones.find(v)
		ob.item_selected.connect(func(i): _poner(e, campo, opciones[i]))
		ctrl = ob
	elif v is bool:
		var cb := CheckBox.new()
		cb.button_pressed = v
		cb.toggled.connect(func(on): _poner(e, campo, on))
		ctrl = cb
	elif v is int or v is float:
		var sp := SpinBox.new()
		sp.allow_greater = true
		sp.allow_lesser = true
		sp.min_value = -1000000
		sp.max_value = 1000000
		sp.step = 1 if v is int else 0.001
		sp.custom_arrow_step = 1 if v is int else 0.05
		sp.rounded = v is int
		sp.value = v
		sp.custom_minimum_size.x = 120
		sp.value_changed.connect(func(x): _poner(e, campo, int(x) if e[campo] is int else x))
		ctrl = sp
	elif v is String:
		if v.length() > 50 or v.contains("\n"):
			var te := TextEdit.new()
			te.text = v
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.custom_minimum_size.y = 64
			te.scroll_fit_content_height = true
			te.text_changed.connect(func(): _poner(e, campo, te.text))
			ctrl = te
		else:
			var le := LineEdit.new()
			le.text = v
			le.text_changed.connect(func(t): _poner(e, campo, t))
			ctrl = le
	elif v is Color:
		var cp := ColorPickerButton.new()
		cp.color = v
		cp.custom_minimum_size = Vector2(90, 26)
		cp.color_changed.connect(func(c): _poner(e, campo, c))
		ctrl = cp
	else:
		# Listas, diccionarios y otros: se editan como texto de Godot y se aplican al salir.
		var te := TextEdit.new()
		te.text = var_to_str(v)
		te.custom_minimum_size.y = 64
		te.scroll_fit_content_height = true
		te.tooltip_text = "Formato de Godot: [\"a\", 1] o {\"clave\": valor}. Se aplica al salir del campo."
		te.focus_exited.connect(func():
			var nuevo = str_to_var(te.text)
			if typeof(nuevo) == typeof(e[campo]):
				te.modulate = Color.WHITE
				if nuevo != e[campo]:
					_poner(e, campo, nuevo)
			else:
				te.modulate = Color(1, 0.5, 0.5)
				push_warning("«%s»: el texto no es válido, no se aplicó." % campo))
		ctrl = te
	ctrl.size_flags_horizontal = SIZE_EXPAND_FILL
	fila.add_child(ctrl)
	var quitar := Button.new()
	quitar.flat = true
	quitar.icon = _icono("Remove")
	quitar.tooltip_text = "Quitar el campo «%s»" % campo
	quitar.pressed.connect(func():
		e.erase(campo)
		_marcar()
		_armar_ficha())
	fila.add_child(quitar)

func _muestra_color(c: Color) -> Texture2D:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _poner(e: Dictionary, campo: String, valor, refrescar_lista := false) -> void:
	e[campo] = valor
	_marcar()
	if refrescar_lista or campo in ["name", "title", "nombre", "region"]:
		var idx := visibles.find(sel)
		if idx >= 0:
			lista.set_item_text(idx, _etiqueta(sel))
		if refrescar_lista:
			_llenar_lista()

# Cambia el id de una entrada y lo actualiza en todas las tablas.
func _renombrar(viejo: String, nuevo: String) -> void:
	if nuevo == "" or nuevo == viejo:
		return
	var d: Dictionary = _datos(tabla)
	if d.has(nuevo):
		push_warning("Ya existe «%s»." % nuevo)
		return
	# Los monstruos sin "sprite" usan su id como nombre de imagen: se conserva la imagen.
	if tabla == "monstruos" and not d[viejo].has("sprite"):
		d[viejo]["sprite"] = viejo
	var reemplazado := {}
	for k in d:
		reemplazado[nuevo if k == viejo else k] = d[k]
	cache[tabla] = reemplazado
	var cambios := 0
	for t in DatosJuego.TABLAS:
		var n := _reemplazar_en(_datos(t), viejo, nuevo)
		if n > 0:
			sucio[t] = true
			cambios += n
	sucio[tabla] = true
	_recalcular_ids()
	sel = ids.find(nuevo)
	_llenar_lista()
	_refrescar_vista()
	_actualizar_estado()
	var en_codigo := _buscar_en_codigo(viejo)
	var txt := "[b]Renombrado[/b] «%s» → «%s». Referencias actualizadas en los datos: %d.\n" % [viejo, nuevo, cambios]
	if en_codigo.is_empty():
		txt += "[color=gray]No aparece en el código.[/color]"
	else:
		txt += "[color=orange]Aparece en el código y ahí hay que cambiarlo a mano (busca \"%s\" con Ctrl+F):[/color] %s" % [viejo, ", ".join(en_codigo)]
	if tabla == "objetos":
		txt += "\n[color=orange]Ojo: los personajes guardados que ya tengan este objeto lo seguirán llamando «%s».[/color]" % viejo
	reporte.text = txt

# Reemplaza textos iguales a "viejo" dentro de cualquier valor (listas y diccionarios anidados).
# No toca "sprite" ni "icono": esos son nombres de archivo y siguen igual.
func _reemplazar_en(v, viejo: String, nuevo: String) -> int:
	var n := 0
	if v is Dictionary:
		for k in v.keys():
			if k is String and k in ["sprite", "icono"]:
				continue
			if v[k] is String and v[k] == viejo:
				v[k] = nuevo
				n += 1
			else:
				n += _reemplazar_en(v[k], viejo, nuevo)
	elif v is Array:
		for i in v.size():
			if v[i] is String and v[i] == viejo:
				v[i] = nuevo
				n += 1
			else:
				n += _reemplazar_en(v[i], viejo, nuevo)
	return n

func _buscar_en_codigo(texto: String) -> Array:
	var encontrados := []
	var buscado := "\"%s\"" % texto
	for ruta in _scripts("res://"):
		var f := FileAccess.open(ruta, FileAccess.READ)
		if f and f.get_as_text().contains(buscado):
			encontrados.append(ruta.get_file())
	return encontrados

func _scripts(carpeta: String) -> Array:
	var out := []
	var dir := DirAccess.open(carpeta)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "datos_juego.gd":
			out.append(carpeta.path_join(f))
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		out.append_array(_scripts(carpeta.path_join(sub)))
	return out

# ---------------------------------------------------------------- tabla (vista de balance)

func _armar_arbol() -> void:
	_llenando = true
	arbol.clear()
	columnas.clear()
	for pos in ids.size():
		var e := _entrada(pos)
		for c in e:
			if not columnas.has(c) and _es_simple(e[c]):
				columnas.append(c)
	arbol.columns = columnas.size() + 1
	arbol.set_column_title(0, "Entrada")
	arbol.set_column_custom_minimum_width(0, 220)
	arbol.set_column_expand(0, false)
	for i in columnas.size():
		var titulo: String = columnas[i]
		if orden_tabla["col"] == i + 1:
			titulo += " ▲" if orden_tabla["asc"] else " ▼"
		arbol.set_column_title(i + 1, titulo)
		arbol.set_column_custom_minimum_width(i + 1, 90)
		arbol.set_column_expand(i + 1, false)
		arbol.set_column_clip_content(i + 1, true)
	var raiz := arbol.create_item()
	var orden := range(ids.size())
	if orden_tabla["col"] > 0:
		var campo: String = columnas[orden_tabla["col"] - 1]
		var asc: bool = orden_tabla["asc"]
		orden.sort_custom(func(a, b):
			var va = _entrada(a).get(campo, null)
			var vb = _entrada(b).get(campo, null)
			if va == null: return false
			if vb == null: return true
			if typeof(va) != typeof(vb): va = str(va); vb = str(vb)
			return va < vb if asc else va > vb)
	var filtro := buscar.text.strip_edges().to_lower()
	for pos in orden:
		var etiqueta := _etiqueta(pos)
		if filtro != "" and not etiqueta.to_lower().contains(filtro):
			continue
		var e := _entrada(pos)
		var it := arbol.create_item(raiz)
		it.set_text(0, etiqueta)
		it.set_metadata(0, pos)
		for i in columnas.size():
			_poner_celda(it, i + 1, e.get(columnas[i], null))
		if pos == sel:
			it.select(0)
	_llenando = false

func _es_simple(v) -> bool:
	return v is int or v is float or v is bool or (v is String and v.length() <= 40 and not v.contains("\n"))

func _poner_celda(it: TreeItem, col: int, v) -> void:
	it.set_editable(col, true)
	if v is bool:
		it.set_cell_mode(col, TreeItem.CELL_MODE_CHECK)
		it.set_checked(col, v)
	elif v is int or v is float:
		it.set_cell_mode(col, TreeItem.CELL_MODE_RANGE)
		it.set_range_config(col, -1000000, 1000000, 1 if v is int else 0.001)
		it.set_range(col, v)
	else:
		it.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
		it.set_text(col, "" if v == null else str(v))
		if v == null:
			it.set_custom_color(col, Color(1, 1, 1, 0.3))
		elif not (v is String):
			it.set_editable(col, false)

func _celda_editada() -> void:
	if _llenando:
		return
	var it := arbol.get_edited()
	var col := arbol.get_edited_column()
	if it == null or col < 1:
		return
	var e := _entrada(int(it.get_metadata(0)))
	var campo: String = columnas[col - 1]
	match it.get_cell_mode(col):
		TreeItem.CELL_MODE_CHECK:
			e[campo] = it.is_checked(col)
		TreeItem.CELL_MODE_RANGE:
			e[campo] = int(it.get_range(col)) if e.get(campo) is int else it.get_range(col)
		_:
			var t := it.get_text(col).strip_edges()
			if t == "":
				e.erase(campo)
			elif not e.has(campo) and t.is_valid_int():
				e[campo] = t.to_int()
			elif not e.has(campo) and t.is_valid_float():
				e[campo] = t.to_float()
			else:
				e[campo] = t
	_marcar()
	if campo in ["name", "title", "nombre", "region", "rareza"]:
		it.set_text(0, _etiqueta(int(it.get_metadata(0))))
		_llenar_lista()

func _ordenar_columna(col: int, _boton_mouse: int) -> void:
	if col == 0:
		orden_tabla = {"col": -1, "asc": true}
	elif orden_tabla["col"] == col:
		orden_tabla["asc"] = not orden_tabla["asc"]
	else:
		orden_tabla = {"col": col, "asc": true}
	_armar_arbol()

# ---------------------------------------------------------------- revisión

func _revisar() -> void:
	_aplicar_foco()
	var errores: Array = []
	var avisos: Array = []
	var objetos: Dictionary = _datos("objetos")
	var monstruos: Dictionary = _datos("monstruos")

	for k in objetos:
		var o: Dictionary = objetos[k]
		if not o.has("sell"):
			errores.append(["objetos", k, "no tiene precio de venta (sell)"])
		var r := int(o.get("rareza", 0))
		if r < 0 or r > 4:
			errores.append(["objetos", k, "rareza %d fuera de rango (0 a 4)" % r])
		var ic := str(o.get("icono", ""))
		if ic == "":
			avisos.append(["objetos", k, "no tiene icono"])
		elif not ResourceLoader.exists("res://icons/%s.png" % ic):
			errores.append(["objetos", k, "el icono icons/%s.png no existe" % ic])
		if o.has("slot") and not OPCIONES["slot"].has(o["slot"]):
			errores.append(["objetos", k, "ranura desconocida «%s»" % o["slot"]])
		if o.has("bando") and not OPCIONES["bando"].has(o["bando"]):
			errores.append(["objetos", k, "bando desconocido «%s»" % o["bando"]])
		if o.has("use"):
			if not OPCIONES["use"].has(o["use"]):
				errores.append(["objetos", k, "uso desconocido «%s»" % o["use"]])
			if not o.has("amount"):
				errores.append(["objetos", k, "es usable pero no tiene «amount»"])
			if str(o["use"]).begins_with("buff") and not o.has("dur"):
				errores.append(["objetos", k, "estimulante sin duración (dur)"])
		if o.has("buy") and o.has("sell") and float(o["buy"]) < float(o["sell"]):
			errores.append(["objetos", k, "se compra en %s y se vende en %s: dinero infinito" % [o["buy"], o["sell"]]])

	for k in monstruos:
		var m: Dictionary = monstruos[k]
		for c in ["name", "hp", "damage", "xp", "move_time", "range", "attack_cd"]:
			if not m.has(c):
				errores.append(["monstruos", k, "le falta el campo «%s»" % c])
		var spr := str(m.get("sprite", k))
		if not ResourceLoader.exists("res://sprites/%s.png" % spr):
			errores.append(["monstruos", k, "el sprite sprites/%s.png no existe" % spr])
		var drops = m.get("drops", [])
		if not (drops is Array):
			errores.append(["monstruos", k, "«drops» debe ser una lista"])
		else:
			for dr in drops:
				if not (dr is Array) or dr.size() != 2:
					errores.append(["monstruos", k, "botín mal escrito: %s (usa [\"Objeto\", 0.5])" % str(dr)])
					continue
				if not objetos.has(dr[0]):
					errores.append(["monstruos", k, "suelta «%s», que no existe en Objetos" % dr[0]])
				if float(dr[1]) <= 0.0 or float(dr[1]) > 1.0:
					avisos.append(["monstruos", k, "probabilidad de «%s» es %s (debe ir de 0 a 1)" % [dr[0], dr[1]]])
		if m.has("golpe"):
			for e in _revisar_regla("Golpes", [m["golpe"]]):
				errores.append(["monstruos", k, "golpe: " + e])
		if m.has("boss"):
			var b = m["boss"]
			if b is Dictionary and not monstruos.has(b.get("summon", "")):
				errores.append(["monstruos", k, "invoca «%s», que no existe" % b.get("summon", "")])

	var habilidades: Dictionary = _datos("habilidades")
	for k in habilidades:
		for e in _revisar_regla("Abilities", [habilidades[k]]):
			errores.append(["habilidades", k, e])
	var clases: Dictionary = _datos("clases")
	var usadas := {}
	for k in clases:
		for hid in clases[k].get("abilities", []):
			usadas[str(hid)] = true
	for k in clases:
		for hid in clases[k].get("variantes", []):
			usadas[str(hid)] = true
			if str(hid) != "" and not habilidades.has(str(hid)):
				errores.append(["clases", k, "variante «%s», que no existe en Habilidades" % hid])
		if clases[k].has("variantes") and clases[k]["variantes"].size() != clases[k].get("abilities", []).size():
			errores.append(["clases", k, "«variantes» debe tener tantas entradas como «abilities» (\"\" = sin variante)"])
	var talentos: Dictionary = _datos("talentos")
	for k in talentos:
		for e in _revisar_regla("Talentos", [talentos[k], clases]):
			errores.append(["talentos", k, e])
	for k in habilidades:
		if not usadas.has(k):
			avisos.append(["habilidades", k, "ninguna clase la usa"])
	for k in clases:
		var c: Dictionary = clases[k]
		var n_hab: int = c.get("abilities", []).size()
		if n_hab < MIN_HABILIDADES or n_hab > MAX_HABILIDADES:
			errores.append(["clases", k, "debe tener de %d a %d habilidades" % [MIN_HABILIDADES, MAX_HABILIDADES]])
		for hid in c.get("abilities", []):
			if not habilidades.has(str(hid)):
				errores.append(["clases", k, "usa la habilidad «%s», que no existe en Habilidades" % hid])
		if c.has("faction") and not OPCIONES["faction"].has(c["faction"]):
			errores.append(["clases", k, "facción desconocida «%s»" % c["faction"]])

	var mutaciones: Dictionary = _datos("mutaciones")
	for k in mutaciones:
		var st = mutaciones[k].get("stats", {})
		if not (st is Dictionary) or st.is_empty():
			errores.append(["mutaciones", k, "no tiene «stats»"])
		else:
			for s in st:
				if not STATS_VALIDOS.has(s):
					errores.append(["mutaciones", k, "estadística desconocida «%s»" % s])

	for t in TABLAS_MISION:
		var l: Array = _datos(t)
		for i in l.size():
			_revisar_mision(l[i], t, i, objetos, monstruos, errores)
	var npcs: Dictionary = _datos("misiones_npc")
	for k in npcs:
		var cadena = npcs[k].get("cadena", [])
		for i in cadena.size():
			_revisar_mision(cadena[i], "misiones_npc", k, objetos, monstruos, errores, " (paso %d)" % (i + 1))

	var txt := ""
	if errores.is_empty() and avisos.is_empty():
		txt = "[color=lightgreen][b]Todo en orden.[/b] No se encontraron problemas.[/color]"
	else:
		txt = "[b]%d errores, %d avisos[/b]   [color=gray](clic para ir a la entrada)[/color]\n" % [errores.size(), avisos.size()]
		for e in errores:
			txt += _linea(e, "tomato")
		for a in avisos:
			txt += _linea(a, "khaki")
	reporte.text = txt

func _revisar_mision(q: Dictionary, t: String, id, objetos: Dictionary, monstruos: Dictionary, errores: Array, extra := "") -> void:
	var tipo := str(q.get("type", ""))
	var obj := str(q.get("target", ""))
	if tipo == "kill" and not monstruos.has(obj):
		errores.append([t, id, "pide matar «%s», que no existe en Monstruos%s" % [obj, extra]])
	elif tipo == "collect" and not objetos.has(obj):
		errores.append([t, id, "pide juntar «%s», que no existe en Objetos%s" % [obj, extra]])
	elif tipo != "kill" and tipo != "collect":
		errores.append([t, id, "tipo desconocido «%s»%s" % [tipo, extra]])
	if int(q.get("count", 0)) <= 0:
		errores.append([t, id, "la cantidad (count) debe ser mayor que 0%s" % extra])
	if q.has("reward_item") and not objetos.has(q["reward_item"]):
		errores.append([t, id, "da de premio «%s», que no existe en Objetos%s" % [q["reward_item"], extra]])
	# Las campañas de bando no deben premiar con equipo que ese bando no puede usar
	var bando_t := t.trim_prefix("misiones_")
	if q.has("reward_item") and objetos.has(q["reward_item"]) and bando_t in OPCIONES["bando"]:
		var b := str(objetos[q["reward_item"]].get("bando", ""))
		if b != "" and b != bando_t:
			errores.append([t, id, "da de premio «%s», que es equipo de %s%s" % [q["reward_item"], b, extra]])

func _linea(p: Array, color: String) -> String:
	var titulo: String = DatosJuego.TABLAS[p[0]]["titulo"]
	var nombre := "%03d" % p[1] if p[1] is int else str(p[1])
	return "[color=%s]•[/color] [url=%s|%s]%s › %s[/url]: %s\n" % [color, p[0], str(p[1]), titulo, nombre, p[2]]

func _ir_a(meta) -> void:
	var partes := str(meta).split("|", true, 1)
	if partes.size() != 2:
		return
	for i in sel_tabla.item_count:
		if sel_tabla.get_item_metadata(i) == partes[0]:
			sel_tabla.select(i)
			_cambiar_tabla(i)
			break
	buscar.text = ""
	var id = partes[1].to_int() if DatosJuego.es_lista(tabla) else partes[1]
	var pos := ids.find(id)
	if pos >= 0:
		tabs.current_tab = 0
		_seleccionar(pos)
		_llenar_lista()


# --- Karth Open: los revisores de reglas (Golpes, Abilities, Talentos) eran del juego por
# casillas de Karth. Si el proyecto tiene una clase con ese nombre y su revisar(), se usa;
# si no, se omite esa revisión.
const MIN_HABILIDADES := 3
const MAX_HABILIDADES := 4

func _revisar_regla(clase: String, args: Array) -> Array:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == clase:
			var s: Script = load(c["path"])
			if s and s.has_method("revisar"):
				return s.callv("revisar", args)
	return []
