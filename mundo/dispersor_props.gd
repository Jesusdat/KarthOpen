@tool
class_name DispersorProps
extends Node3D
## Reparte los props de PropForge (modelos/terreno/<bioma>/obj_*.glb) sobre el terreno.
## Mismas reglas que Karth: los que empiezan con "obj_deco_" no tapan el paso; el resto
## (árboles, rocas grandes, troncos) lleva colisión. Siempre igual con la misma semilla.

const DATOS := "res://datos/terreno.cfg"

@export var terreno: TerrenoKarth

@export var regenerar := false:
	set(v):
		if v and is_inside_tree():
			dispersar()


func _ready() -> void:
	# El terreno se arma en su propio _ready; esperamos un cuadro por si va después.
	await get_tree().process_frame
	dispersar()


func dispersar() -> void:
	for hijo in get_children():
		remove_child(hijo)
		hijo.queue_free()
	if terreno == null or terreno.lado == 0:
		return
	DatosCfg.olvidar()
	var p := DatosCfg.seccion(DATOS, "props")
	var bioma := String(p.get("bioma", "llanura"))
	var modelos := _modelos(bioma)
	if modelos.is_empty():
		push_warning("DispersorProps: no hay obj_*.glb en modelos/terreno/%s" % bioma)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(DatosCfg.valor(DATOS, "generador", "semilla", 1)) + 7
	var cantidad := int(p.get("cantidad", 300))
	var pendiente_max := float(p.get("pendiente_maxima", 0.55))
	var radio_libre := float(p.get("radio_libre", 14.0))
	var e_base := float(p.get("escala_base", 1.9))
	var e_min := float(p.get("escala_min", 0.85))
	var e_max := float(p.get("escala_max", 1.35))
	var centro := terreno.centro()
	var margen := float(DatosCfg.valor(DATOS, "generador", "borde", 24.0))
	var puestos := 0
	var intentos := 0
	while puestos < cantidad and intentos < cantidad * 6:
		intentos += 1
		var x := terreno.global_position.x + rng.randf_range(margen, terreno.lado - margen)
		var z := terreno.global_position.z + rng.randf_range(margen, terreno.lado - margen)
		if Vector2(x - centro.x, z - centro.z).length() < radio_libre:
			continue
		var normal := terreno.normal_en(x, z)
		if 1.0 - normal.y > pendiente_max * 0.3:
			continue
		var ruta: String = modelos[rng.randi() % modelos.size()]
		var escena := load(ruta) as PackedScene
		if escena == null:
			continue
		var obj := escena.instantiate() as Node3D
		obj.name = "%s_%d" % [ruta.get_file().get_basename(), puestos]
		add_child(obj)
		obj.global_position = Vector3(x, terreno.altura_en(x, z) - 0.05, z)
		obj.rotation.y = rng.randf() * TAU
		obj.scale = Vector3.ONE * e_base * rng.randf_range(e_min, e_max)
		if not ruta.get_file().begins_with("obj_deco_"):
			_poner_colision(obj)
		puestos += 1


func _modelos(bioma: String) -> PackedStringArray:
	var lista := PackedStringArray()
	var carpeta := "res://modelos/terreno/%s/" % bioma
	for archivo in ResourceLoader.list_directory(carpeta):
		if archivo.begins_with("obj_") and archivo.ends_with(".glb"):
			lista.append(carpeta + archivo)
	return lista


## Cilindro con el ancho del modelo (árboles, rocas, troncos tapan el paso).
func _poner_colision(obj: Node3D) -> void:
	var caja := _caja(obj)
	if caja.size == Vector3.ZERO:
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Colision"
	var forma := CylinderShape3D.new()
	forma.radius = clampf(minf(caja.size.x, caja.size.z) * 0.35, 0.2, 3.0)
	forma.height = maxf(caja.size.y, 0.5)
	var col := CollisionShape3D.new()
	col.shape = forma
	col.position = Vector3(caja.get_center().x, forma.height * 0.5, caja.get_center().z)
	cuerpo.add_child(col)
	obj.add_child(cuerpo)


func _caja(raiz: Node3D) -> AABB:
	var total := AABB()
	var primera := true
	for mi in raiz.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := raiz.global_transform.affine_inverse() * m.global_transform
		var a := t * m.get_aabb()
		total = a if primera else total.merge(a)
		primera = false
	return total
