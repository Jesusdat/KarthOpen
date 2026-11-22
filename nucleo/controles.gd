extends Node
## Carga las acciones de entrada desde datos/controles.cfg (teclas, ratón y control).
## Así los controles se cambian en datos, sin tocar el Mapa de entrada del proyecto.

const RUTA := "res://datos/controles.cfg"
const ZONA_MUERTA := 0.2

const RATON := {
	"raton_izq": MOUSE_BUTTON_LEFT,
	"raton_der": MOUSE_BUTTON_RIGHT,
	"raton_medio": MOUSE_BUTTON_MIDDLE,
	"rueda_arriba": MOUSE_BUTTON_WHEEL_UP,
	"rueda_abajo": MOUSE_BUTTON_WHEEL_DOWN,
}


func _ready() -> void:
	cargar(RUTA)


func cargar(ruta: String) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(ruta)
	if err != OK:
		push_error("Controles: no se pudo leer %s (error %d)" % [ruta, err])
		return
	for accion in cfg.get_sections():
		if InputMap.has_action(accion):
			InputMap.action_erase_events(accion)
		else:
			InputMap.add_action(accion, ZONA_MUERTA)
		for tecla in cfg.get_value(accion, "teclas", []):
			var codigo := OS.find_keycode_from_string(tecla)
			if codigo == KEY_NONE:
				push_warning("Controles: tecla desconocida '%s' en [%s]" % [tecla, accion])
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = codigo
			InputMap.action_add_event(accion, ev)
		for boton in cfg.get_value(accion, "botones", []):
			var ev := _boton(String(boton))
			if ev:
				InputMap.action_add_event(accion, ev)
			else:
				push_warning("Controles: botón desconocido '%s' en [%s]" % [boton, accion])
		for eje in cfg.get_value(accion, "ejes", []):
			# "joy_eje_1_-" = eje 1 hacia valores negativos
			var partes := String(eje).split("_")
			if partes.size() != 4:
				continue
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(partes[2]) as JoyAxis
			ev.axis_value = -1.0 if partes[3] == "-" else 1.0
			InputMap.action_add_event(accion, ev)


func _boton(nombre: String) -> InputEvent:
	if RATON.has(nombre):
		var ev := InputEventMouseButton.new()
		ev.button_index = RATON[nombre]
		return ev
	if nombre.begins_with("joy_"):
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(nombre.substr(4)) as JoyButton
		return ev
	return null
