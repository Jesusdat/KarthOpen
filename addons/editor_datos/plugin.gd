@tool
extends EditorPlugin

const PanelDatos := preload("res://addons/editor_datos/panel_datos.gd")

var panel: Control

func _enter_tree() -> void:
	panel = PanelDatos.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)

func _exit_tree() -> void:
	if panel:
		panel.queue_free()
		panel = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if panel:
		panel.visible = visible

func _get_plugin_name() -> String:
	return "Datos"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Grid", "EditorIcons")
