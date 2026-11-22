extends Node3D
## Escena de prueba del paso 1: terreno propio, props de PropForge y el jugador en
## tercera persona. Coloca al jugador en el centro del llano y abre el HUD (UIBuilder).

const HUD := "res://ui/hud.json"

@onready var terreno: TerrenoKarth = $Terreno
@onready var jugador: Jugador = $Jugador


func _ready() -> void:
	jugador.colocar(terreno.centro() + Vector3.UP * 0.5)
	UIBuilder.abrir(HUD)
