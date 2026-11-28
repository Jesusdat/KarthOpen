extends Node3D
## Escena de prueba: terreno propio, props de PropForge, el jugador en tercera persona
## y guaridas de Nidales para probar el combate. Abre el HUD (UIBuilder).

const HUD := ["res://ui/hud.json", "res://ui/hud_objetivo.json", "res://ui/aviso.json"]

@onready var terreno: TerrenoKarth = $Terreno
@onready var jugador: Jugador = $Jugador


func _ready() -> void:
	Efectos.usar_mundo(self, jugador)
	jugador.colocar(terreno.centro() + Vector3.UP * 0.5)
	# Las guaridas se colocan relativas al punto de inicio (centro del llano).
	var c := terreno.centro()
	for g in get_tree().get_nodes_in_group("guaridas_prueba"):
		var gu := g as Guarida
		gu.global_position = Vector3(c.x + gu.position.x, c.y, c.z + gu.position.z)
	UIBuilder.estado.fusionar("objetivo", {"visible": false})
	UIBuilder.estado.fusionar("aviso", {"visible": false, "texto": ""})
	for h in HUD:
		UIBuilder.abrir(h)
