class_name DatosCfg
## Lectura sencilla de los .cfg de datos/ con caché.

static var _cache: Dictionary = {}


static func archivo(ruta: String) -> ConfigFile:
	if _cache.has(ruta):
		return _cache[ruta]
	var cfg := ConfigFile.new()
	var err := cfg.load(ruta)
	if err != OK:
		push_error("DatosCfg: no se pudo leer %s (error %d)" % [ruta, err])
	_cache[ruta] = cfg
	return cfg


## Valor de una sección; si falta, devuelve el valor por defecto.
static func valor(ruta: String, seccion: String, clave: String, defecto: Variant = null) -> Variant:
	return archivo(ruta).get_value(seccion, clave, defecto)


## Toda una sección como diccionario.
static func seccion(ruta: String, nombre: String) -> Dictionary:
	var cfg := archivo(ruta)
	var d := {}
	if cfg.has_section(nombre):
		for clave in cfg.get_section_keys(nombre):
			d[clave] = cfg.get_value(nombre, clave)
	return d


## Olvida la caché (para recargar datos mientras el juego corre).
static func olvidar() -> void:
	_cache.clear()
