class_name UIEstado
extends RefCounted
## Almacén de datos observable. La interfaz se enlaza a rutas ("jugador.vida")
## y se actualiza sola cuando cambian.
##
##   UIBuilder.estado.poner("jugador.vida", 70)
##   UIBuilder.estado.leer("jugador.vida")        -> 70
##   UIBuilder.estado.sumar("jugador.creditos", -50)

## Se emite cada vez que cambia el valor de una ruta.
signal cambio(ruta: String)

var datos: Dictionary = {}


## Guarda un valor. Si es igual al que ya había, no avisa a nadie.
func poner(ruta: String, valor: Variant) -> void:
	var segs := ruta.split(".")
	var d := datos
	for i in segs.size() - 1:
		if not (d.get(segs[i]) is Dictionary):
			d[segs[i]] = {}
		d = d[segs[i]]
	var ultimo := segs[segs.size() - 1]
	var anterior: Variant = d.get(ultimo)
	var es_coleccion := valor is Dictionary or valor is Array
	if not es_coleccion and typeof(anterior) == typeof(valor) and anterior == valor:
		return
	d[ultimo] = valor
	cambio.emit(ruta)


## Guarda varios valores de golpe: fusionar("jugador", {"vida": 70, "energia": 20})
func fusionar(ruta: String, valores: Dictionary) -> void:
	for k in valores:
		poner(str(k) if ruta == "" else ruta + "." + str(k), valores[k])


func leer(ruta: String, defecto: Variant = null) -> Variant:
	var v: Variant = caminar(datos, ruta.split("."), 0)
	return defecto if v == null else v


## Suma (o resta) a un número guardado.
func sumar(ruta: String, cantidad: float) -> void:
	poner(ruta, float(leer(ruta, 0)) + cantidad)


## Avisa de un cambio hecho "por dentro" (por ejemplo, tras modificar un Array
## que ya estaba guardado, sin volver a llamar a poner()).
func avisar(ruta: String) -> void:
	cambio.emit(ruta)


## Intercambia dos casillas, de la misma lista o de listas distintas. Sirve para
## mover objetos: si el destino está vacío, el objeto simplemente cambia de sitio.
## Con índice -1 la ruta es la casilla misma (por ejemplo "equipo.casco").
##   estado.intercambiar("inventario.objetos", 0, "inventario.objetos", 7)
##   estado.intercambiar("inventario.objetos", 3, "equipo.casco", -1)
func intercambiar(ruta_a: String, indice_a: int, ruta_b: String, indice_b: int) -> void:
	var a: Variant = _casilla(ruta_a, indice_a)
	var b: Variant = _casilla(ruta_b, indice_b)
	_fijar_casilla(ruta_a, indice_a, b)
	_fijar_casilla(ruta_b, indice_b, a)
	cambio.emit(ruta_a)
	if ruta_b != ruta_a:
		cambio.emit(ruta_b)


func _casilla(ruta: String, indice: int) -> Variant:
	var v: Variant = leer(ruta)
	if indice < 0:
		return v
	return v[indice] if v is Array and indice < v.size() else null


func _fijar_casilla(ruta: String, indice: int, valor: Variant) -> void:
	if indice < 0:
		_fijar(ruta, valor)
		return
	var lista: Variant = leer(ruta)
	if not (lista is Array):
		lista = []
		_fijar(ruta, lista)
	while lista.size() <= indice:
		lista.append(null)
	lista[indice] = valor


func _fijar(ruta: String, valor: Variant) -> void:
	var segs := ruta.split(".")
	var d := datos
	for i in segs.size() - 1:
		if not (d.get(segs[i]) is Dictionary):
			d[segs[i]] = {}
		d = d[segs[i]]
	d[segs[segs.size() - 1]] = valor


## Recorre diccionarios, arrays (con índice numérico) y propiedades de objetos.
static func caminar(base: Variant, segs: PackedStringArray, desde: int) -> Variant:
	var v: Variant = base
	for i in range(desde, segs.size()):
		var s := segs[i]
		if v is Dictionary:
			v = v.get(s)
		elif v is Array and s.is_valid_int():
			var n := int(s)
			v = v[n] if n >= 0 and n < v.size() else null
		elif v is Object and is_instance_valid(v):
			v = v.get(s)
		else:
			return null
	return v
