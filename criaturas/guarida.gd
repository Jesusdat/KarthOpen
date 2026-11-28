class_name Guarida
extends Node3D
## Punto del mundo donde viven criaturas de un tipo. Las crea alrededor, sobre el
## terreno, y repone las que mueren después de un tiempo.

signal criatura_creada(c: Criatura)

@export var tipo := "nidal"
@export var cantidad := 3
@export var radio := 6.0
@export var reaparicion := 25.0   ## segundos para reponer una criatura muerta

var vivas: Array[Criatura] = []
var _pendientes: Array[float] = []


func _ready() -> void:
	# Espera un cuadro para que el terreno ya esté armado.
	await get_tree().process_frame
	_pegar_al_suelo()
	for i in cantidad:
		crear()


func _process(delta: float) -> void:
	for i in range(_pendientes.size() - 1, -1, -1):
		_pendientes[i] -= delta
		if _pendientes[i] <= 0.0:
			_pendientes.remove_at(i)
			crear()


func crear() -> Criatura:
	var c := Criatura.new()
	c.name = "%s_%d" % [tipo.capitalize(), Time.get_ticks_usec() % 100000]
	c.configurar(tipo, global_position)
	var a := randf() * TAU
	var r := randf_range(0.0, radio)
	var x := global_position.x + cos(a) * r
	var z := global_position.z + sin(a) * r
	var terreno := get_tree().get_first_node_in_group("terreno") as TerrenoKarth
	var y := terreno.altura_en(x, z) if terreno else global_position.y
	get_parent().add_child(c)
	c.global_position = Vector3(x, y + 0.3, z)
	c.rotation.y = randf() * TAU
	c.murio.connect(_al_morir)
	vivas.append(c)
	criatura_creada.emit(c)
	return c


func _al_morir(c: Criatura) -> void:
	vivas.erase(c)
	_pendientes.append(reaparicion)


func _pegar_al_suelo() -> void:
	var terreno := get_tree().get_first_node_in_group("terreno") as TerrenoKarth
	if terreno:
		global_position.y = terreno.altura_en(global_position.x, global_position.z)
