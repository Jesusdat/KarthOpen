class_name UIVista
extends Control
## Una interfaz abierta con UIBuilder.abrir(). Cada vista tiene su propia señal
## "accion", así que una pantalla nunca recibe los clics de otra.
##
##   var mochila := UIBuilder.abrir("res://ui/mochila.json")
##   mochila.accion.connect(_on_mochila)
##   mochila.cerrar()

## Botón, opción de diálogo o ranura pulsados en ESTA vista.
signal accion(nombre: String, datos: Dictionary)
## La vista se cerró (botón, Esc o cerrar()).
signal cerrada
## Para diálogos: índice de la opción elegida, o -1 si se cerró sin elegir.
signal resuelta(resultado: int)

var estado: UIEstado
var ruta := ""                 ## Archivo JSON de origen ("" si se abrió desde código)
var spec_origen: Dictionary    ## Especificación de origen si se abrió desde código
var capa := "ventana"          ## "hud", "ventana" o "modal"
var cerrar_con_esc := true
var recargando := false              ## true mientras la recarga en caliente la reconstruye
var desplazamiento := Vector2.ZERO   ## Cuánto la ha movido el jugador ("movible")
var ids: Dictionary = {}
var errores: PackedStringArray = []

var _enlaces: Array[Dictionary] = []
var _pendientes: PackedStringArray = []
var _programado := false
var _cerrando := false
var _resuelta := false

static var _re: RegEx


## Devuelve el nodo con ese "id" (o null).
func buscar(id: String) -> Control:
	return ids.get(id)


func cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	if not _resuelta:
		_resuelta = true
		resuelta.emit(-1)
	cerrada.emit()
	queue_free()


## Cierra un diálogo devolviendo un resultado (lo usa UIBuilder.preguntar).
func resolver(resultado: int) -> void:
	if _resuelta:
		return
	_resuelta = true
	resuelta.emit(resultado)
	cerrar()


func emitir(nombre: String, datos: Dictionary = {}) -> void:
	if nombre == "ui:cerrar":
		cerrar()
	else:
		accion.emit(nombre, datos)


func conectar_estado(e: UIEstado) -> void:
	if estado and estado.cambio.is_connected(_al_cambiar):
		estado.cambio.disconnect(_al_cambiar)
	estado = e
	estado.cambio.connect(_al_cambiar)


## Vacía la vista para volver a construirla (recarga en caliente).
## Las conexiones a "accion" y "cerrada" se conservan.
func limpiar() -> void:
	for e in _enlaces:
		e.vivo = false
	_enlaces.clear()
	ids.clear()
	errores.clear()
	for h in get_children():
		remove_child(h)
		h.queue_free()


func registrar_enlace(e: Dictionary) -> void:
	e.vivo = true
	_enlaces.append(e)


## Olvida los enlaces de un nodo y de todo lo que cuelga de él.
func purgar(nodo: Node) -> void:
	for e in _enlaces:
		var n: Variant = e.nodo
		if not is_instance_valid(n) or n == nodo or nodo.is_ancestor_of(n):
			e.vivo = false


func _al_cambiar(ruta_cambiada: String) -> void:
	_pendientes.append(ruta_cambiada)
	if not _programado:
		_programado = true
		_refrescar.call_deferred()


## Aplica de una vez todos los cambios acumulados en este fotograma.
func _refrescar() -> void:
	_programado = false
	var rutas := _pendientes.duplicate()
	_pendientes.clear()
	for e in _enlaces.duplicate():
		if not e.vivo:
			continue
		if not is_instance_valid(e.nodo):
			e.vivo = false
			continue
		if _afecta(e.deps, rutas):
			e.aplicar.call(evaluar(e.an, e.ctx))
	_enlaces = _enlaces.filter(func(e: Dictionary) -> bool: return e.vivo)


static func _afecta(deps: Array, rutas: PackedStringArray) -> bool:
	for d: String in deps:
		for r in rutas:
			if d == r or d.begins_with(r + ".") or r.begins_with(d + "."):
				return true
	return false


# ---------------------------------------------------------------- ENLACES

## Analiza un valor del JSON. Devuelve {} si es un valor fijo.
##   "@jugador.vida"            -> el valor de esa ruta
##   "@!tienda.abierta"         -> ese valor, negado
##   "Créditos: {jugador.oro}"  -> texto con valores intercalados
static func analizar(v: Variant) -> Dictionary:
	if not (v is String):
		return {}
	var s: String = v
	if s.begins_with("@"):
		var negar := s.begins_with("@!")
		var r := s.substr(2 if negar else 1).strip_edges()
		return {"modo": "ruta", "ruta": r, "negar": negar, "rutas": [r]}
	if s.contains("{"):
		if _re == null:
			_re = RegEx.new()
			_re.compile("\\{([A-Za-z_][A-Za-z0-9_\\.]*)\\}")
		var rutas: Array = []
		for m in _re.search_all(s):
			rutas.append(m.get_string(1))
		if not rutas.is_empty():
			return {"modo": "texto", "texto": s, "rutas": rutas}
	return {}


static func evaluar(an: Dictionary, ctx: Contexto) -> Variant:
	if an.modo == "ruta":
		var v: Variant = ctx.leer(an.ruta)
		if an.negar:
			return not verdadero(v)
		return v
	var s: String = an.texto
	for r: String in an.rutas:
		s = s.replace("{" + r + "}", formatear(ctx.leer(r)))
	return s


static func verdadero(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	if v is Array or v is Dictionary:
		return not v.is_empty()
	return true


## Convierte un valor a texto (los números enteros salen sin ".0").
static func formatear(v: Variant) -> String:
	if v == null:
		return ""
	if v is float:
		if is_equal_approx(v, roundf(v)):
			return str(int(roundf(v)))
		return str(snappedf(v, 0.01))
	return str(v)


## Lo que recibe cada componente al construirse: la vista y las variables
## locales (por ejemplo "item" e "indice" dentro de un "repetir").
class Contexto:
	var vista: UIVista
	var locales: Dictionary = {}

	func _init(v: UIVista, l: Dictionary = {}) -> void:
		vista = v
		locales = l

	func derivar(extra: Dictionary) -> Contexto:
		var l := locales.duplicate()
		l.merge(extra, true)
		return Contexto.new(vista, l)

	func leer(ruta: String) -> Variant:
		var segs := ruta.split(".")
		if locales.has(segs[0]):
			return UIEstado.caminar(locales[segs[0]], segs, 1)
		return vista.estado.leer(ruta)

	## Valor actual de una propiedad (fija o enlazada), sin suscribirse.
	func valor(v: Variant) -> Variant:
		var an := UIVista.analizar(v)
		return v if an.is_empty() else UIVista.evaluar(an, self)

	## Aplica spec[prop] al nodo y lo mantiene al día si está enlazado al estado.
	## aplicar: func(valor) que pone el valor en el nodo.
	func enlazar(nodo: Node, spec: Dictionary, prop: String, aplicar: Callable, defecto: Variant = null) -> void:
		if not spec.has(prop):
			if defecto != null:
				aplicar.call(defecto)
			return
		var an := UIVista.analizar(spec[prop])
		if an.is_empty():
			aplicar.call(spec[prop])
			return
		aplicar.call(UIVista.evaluar(an, self))
		var deps: Array = []
		for r: String in an.rutas:
			if not locales.has(r.get_slice(".", 0)):
				deps.append(r)
		if not deps.is_empty():
			vista.registrar_enlace({"nodo": nodo, "an": an, "ctx": self, "aplicar": aplicar, "deps": deps})

	## Datos que acompañan a una acción; los enlaces se resuelven al hacer clic.
	func datos(spec: Dictionary, extra: Dictionary = {}) -> Dictionary:
		var d: Dictionary = {}
		var origen: Variant = spec.get("datos", {})
		if origen is Dictionary:
			for k in origen:
				d[k] = valor(origen[k])
		d.merge(extra, true)
		return d

	## Construye los "hijos" fijos y, si hay "repetir", un hijo por cada elemento
	## de la lista (se rehacen solos cuando la lista cambia).
	func hijos(contenedor: Node, spec: Dictionary) -> void:
		for h: Dictionary in spec.get("hijos", []):
			contenedor.add_child(UIBuilder.construir_nodo(h, self))
		if not spec.has("repetir"):
			return
		var como: String = spec.get("como", "item")
		var molde: Dictionary = spec.get("elemento", {})
		var creados: Array[Node] = []
		var v := vista
		var c := self
		var rehacer := func(lista: Variant) -> void:
			for viejo in creados:
				v.purgar(viejo)
				contenedor.remove_child(viejo)
				viejo.queue_free()
			creados.clear()
			if lista is Array:
				for i in lista.size():
					var n: Control = UIBuilder.construir_nodo(molde, c.derivar({como: lista[i], "indice": i}))
					contenedor.add_child(n)
					creados.append(n)
		enlazar(contenedor, spec, "repetir", rehacer)
