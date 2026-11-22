@tool
class_name DatosJuego

# Carga y guarda las tablas de datos del juego (objetos, monstruos, clases...).
# Cada tabla vive en res://datos/<tabla>.cfg y se edita con el Editor de datos
# (pestaña "Datos" arriba en el editor de Godot). El servidor y el cliente leen
# los mismos archivos, así que el balance queda igual en ambos lados.
#
# Formato: un [bloque] por entrada y un campo por línea, con valores de Godot
# (números, textos, Color(...), listas [...] y diccionarios {...}).
# En las tablas tipo "lista" los bloques se llaman 000, 001, 002... y ese es su orden.

const CARPETA := "res://datos/"

# nombre del archivo -> cómo se usa. "plantilla" son los campos de una entrada nueva.
const TABLAS := {
	"objetos": {"titulo": "Objetos", "tipo": "dict",
		"plantilla": {"sell": 1, "rareza": 0, "icono": ""}},
	"monstruos": {"titulo": "Monstruos", "tipo": "dict",
		"plantilla": {"name": "Nuevo monstruo", "hp": 30, "damage": 3, "xp": 20, "move_time": 0.4, "range": 1, "attack_cd": 1.5, "color": Color(1, 1, 1)}},
	"clases": {"titulo": "Clases", "tipo": "dict",
		"plantilla": {"name": "Nueva clase", "desc": "", "hp": 0, "hp_lvl": 20, "damage": 1, "energy": 0, "regen": 0, "range": 5, "speed": 1.0, "abilities": ["", "", ""]}},
	"habilidades": {"titulo": "Habilidades", "tipo": "dict",
		"plantilla": {"name": "Nueva habilidad", "cost": 10, "cooldown": 5.0, "apunta": "objetivo", "alcance": 0, "forma": "objetivo", "tam": 0, "efectos": [{"tipo": "dano", "mult": 2.0}], "golpes": 1, "fx": "disparo"}},
	"talentos": {"titulo": "Talentos", "tipo": "dict",
		"plantilla": {"clase": "soldado", "nivel": 10, "name": "Nuevo talento", "desc": "", "tipo": "remate", "efectos": [{"tipo": "empuje", "casillas": 1}]}},
	"mutaciones": {"titulo": "Mutaciones", "tipo": "dict",
		"plantilla": {"name": "Nueva mutación", "desc": "", "cost": 40, "level": 1, "stats": {"hp": 10}}},
	"misiones_colonos": {"titulo": "Misiones · Colonos", "tipo": "lista",
		"plantilla": {"title": "Nueva misión", "text": "", "done_text": "", "type": "kill", "target": "nidal", "count": 1, "reward_cr": 10, "reward_xp": 10}},
	"misiones_enjambre": {"titulo": "Misiones · Progenie", "tipo": "lista",
		"plantilla": {"title": "Nueva misión", "text": "", "done_text": "", "type": "kill", "target": "miliciano", "count": 1, "reward_cr": 10, "reward_xp": 10}},
	"misiones_antiguos": {"titulo": "Misiones · Antiguos", "tipo": "lista",
		"plantilla": {"title": "Nueva misión", "text": "", "done_text": "", "type": "kill", "target": "nidal", "count": 1, "reward_cr": 10, "reward_xp": 10}},
	"contratos": {"titulo": "Contratos (tablón)", "tipo": "lista",
		"plantilla": {"title": "Nuevo contrato", "region": "", "levels": "1-3", "text": "", "type": "kill", "target": "nidal", "count": 5, "reward_cr": 50, "reward_xp": 70}},
	"misiones_npc": {"titulo": "Misiones de NPC", "tipo": "dict",
		"plantilla": {"nombre": "Nuevo NPC", "fin": "", "cadena": []}},
}

static func ruta(tabla: String) -> String:
	return CARPETA + tabla + ".cfg"

static func es_lista(tabla: String) -> bool:
	return TABLAS.get(tabla, {}).get("tipo", "dict") == "lista"

static func _abrir(tabla: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	var err := cfg.load(ruta(tabla))
	if err != OK:
		push_error("DatosJuego: no se pudo leer %s (error %d)" % [ruta(tabla), err])
	return cfg

static func _entrada(cfg: ConfigFile, seccion: String) -> Dictionary:
	var d := {}
	for campo in cfg.get_section_keys(seccion):
		d[campo] = cfg.get_value(seccion, campo)
	return d

# Tabla con nombre -> datos (objetos, monstruos, clases...).
static func cargar_dict(tabla: String) -> Dictionary:
	var cfg := _abrir(tabla)
	var out := {}
	for s in cfg.get_sections():
		out[s] = _entrada(cfg, s)
	return out

# Tabla en orden (misiones, contratos, habilidades).
static func cargar_lista(tabla: String) -> Array:
	var cfg := _abrir(tabla)
	var secciones := Array(cfg.get_sections())
	secciones.sort()
	var out := []
	for s in secciones:
		out.append(_entrada(cfg, s))
	return out

static func cargar(tabla: String) -> Variant:
	return cargar_lista(tabla) if es_lista(tabla) else cargar_dict(tabla)

# datos: Dictionary (nombre -> campos) o Array (lista de campos).
static func guardar(tabla: String, datos: Variant) -> Error:
	var cfg := ConfigFile.new()
	if datos is Array:
		for i in datos.size():
			_escribir(cfg, "%03d" % i, datos[i])
	else:
		for k in datos:
			_escribir(cfg, str(k), datos[k])
	DirAccess.make_dir_recursive_absolute(CARPETA)
	return cfg.save(ruta(tabla))

static func _escribir(cfg: ConfigFile, seccion: String, campos: Dictionary) -> void:
	for c in campos:
		cfg.set_value(seccion, str(c), campos[c])

# Copia de la tabla sin ciertos campos (p. ej. quitar "rareza" e "icono" de los objetos).
static func sin_campos(tabla: Dictionary, campos: Array) -> Dictionary:
	var out := {}
	for k in tabla:
		var d: Dictionary = tabla[k].duplicate(true)
		for c in campos:
			d.erase(c)
		out[k] = d
	return out

# nombre -> valor de un solo campo (solo las entradas que lo tienen).
static func extraer_campo(tabla: Dictionary, campo: String) -> Dictionary:
	var out := {}
	for k in tabla:
		if tabla[k].has(campo):
			out[k] = tabla[k][campo]
	return out
