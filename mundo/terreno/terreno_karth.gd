@tool
class_name TerrenoKarth
extends Node3D
## Terreno propio de Karth Open: una malla de alturas (1 m por casilla) cortada en bloques.
## Cada bloque es una malla con su colisión (HeightMapShape3D). Es la base que después
## editará el editor de terreno (pinceles para subir, bajar, aplanar y pintar), sin Terrain3D.
##
## Por ahora las alturas se generan con ruido desde datos/terreno.cfg. Si existe
## `archivo_alturas` (un .exr de un canal, el que guardará el editor), se usa ese.

const DATOS := "res://datos/terreno.cfg"
const SHADER := preload("res://mundo/terreno/terreno.gdshader")

## Vuelve a generar el terreno (útil en el editor después de cambiar datos/terreno.cfg).
@export var regenerar := false:
	set(v):
		if v and is_inside_tree():
			construir()

## Mapa de alturas guardado (.exr, canal R en metros). Vacío = generar con ruido.
@export_file("*.exr") var archivo_alturas := ""

var lado := 0                 # casillas por lado (bloques × tamaño de bloque)
var tamano_bloque := 64
var alturas := PackedFloat32Array()   # (lado + 1)² valores, fila por fila (z), en metros

var _material: ShaderMaterial


func _ready() -> void:
	construir()


## Lee datos, genera o carga las alturas y arma todos los bloques.
func construir() -> void:
	DatosCfg.olvidar()
	var g := DatosCfg.seccion(DATOS, "generador")
	tamano_bloque = int(g.get("tamano_bloque", 64))
	var bloques := int(g.get("bloques", 8))
	lado = bloques * tamano_bloque
	if archivo_alturas != "" and FileAccess.file_exists(archivo_alturas):
		_cargar_alturas(archivo_alturas)
	else:
		_generar_alturas(g)
	_armar_bloques(bloques)


## Altura del terreno en una posición del mundo (interpolada). Fuera del mapa: 0.
func altura_en(x: float, z: float) -> float:
	var lx := x - global_position.x
	var lz := z - global_position.z
	if lx < 0.0 or lz < 0.0 or lx > lado or lz > lado:
		return global_position.y
	var x0 := mini(int(lx), lado - 1)
	var z0 := mini(int(lz), lado - 1)
	var fx := lx - x0
	var fz := lz - z0
	var a := _h(x0, z0)
	var b := _h(x0 + 1, z0)
	var c := _h(x0, z0 + 1)
	var d := _h(x0 + 1, z0 + 1)
	return global_position.y + lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## Normal del terreno en una posición del mundo.
func normal_en(x: float, z: float) -> Vector3:
	var e := 1.0
	var hl := altura_en(x - e, z)
	var hr := altura_en(x + e, z)
	var hd := altura_en(x, z - e)
	var hu := altura_en(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## Centro del mapa en coordenadas del mundo, a ras de suelo.
func centro() -> Vector3:
	var c := lado * 0.5
	return Vector3(global_position.x + c, altura_en(global_position.x + c, global_position.z + c), global_position.z + c)


## Guarda las alturas actuales en un .exr (para el futuro editor de terreno).
func guardar_alturas(ruta: String) -> Error:
	var img := Image.create_empty(lado + 1, lado + 1, false, Image.FORMAT_RF)
	for z in lado + 1:
		for x in lado + 1:
			img.set_pixel(x, z, Color(_h(x, z), 0, 0))
	return img.save_exr(ruta, true)


# ================================================================ alturas

func _h(x: int, z: int) -> float:
	return alturas[z * (lado + 1) + x]


func _generar_alturas(g: Dictionary) -> void:
	var ruido := FastNoiseLite.new()
	ruido.seed = int(g.get("semilla", 1337))
	ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ruido.frequency = float(g.get("frecuencia", 0.0032))
	ruido.fractal_type = FastNoiseLite.FRACTAL_FBM
	ruido.fractal_octaves = int(g.get("octavas", 5))
	var n := lado + 1
	# get_image es nativo y mucho más rápido que pedir punto por punto.
	var img := ruido.get_image(n, n, false, false, false)
	var alto := float(g.get("altura_maxima", 55.0))
	var llano := float(g.get("llano_inicio", 40.0))
	var borde := float(g.get("borde", 24.0))
	var c := lado * 0.5
	alturas.resize(n * n)
	for z in n:
		for x in n:
			var v := img.get_pixel(x, z).r          # 0..1
			var h := pow(v, 1.6) * alto                # valles anchos, cerros más marcados
			# llano del inicio (centro), con transición suave
			var dist := Vector2(x - c, z - c).length()
			var t := smoothstep(llano, llano * 2.2, dist)
			var h_llano := alto * 0.18
			h = lerpf(h_llano, h, t)
			# la orilla del mapa sube para cerrar el mundo
			var orilla := minf(minf(x, z), minf(lado - x, lado - z))
			h += (1.0 - smoothstep(0.0, borde, orilla)) * alto * 0.6
			alturas[z * n + x] = h


func _cargar_alturas(ruta: String) -> void:
	var img := Image.load_from_file(ruta)
	if img == null or img.get_width() != lado + 1 or img.get_height() != lado + 1:
		push_error("TerrenoKarth: %s no mide %d×%d; se genera con ruido." % [ruta, lado + 1, lado + 1])
		_generar_alturas(DatosCfg.seccion(DATOS, "generador"))
		return
	var n := lado + 1
	alturas.resize(n * n)
	for z in n:
		for x in n:
			alturas[z * n + x] = img.get_pixel(x, z).r


# ================================================================ bloques

func _armar_bloques(bloques: int) -> void:
	for hijo in get_children():
		if hijo.name.begins_with("Bloque_"):
			remove_child(hijo)
			hijo.queue_free()
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	for bz in bloques:
		for bx in bloques:
			_armar_bloque(bx, bz)


func _armar_bloque(bx: int, bz: int) -> void:
	var t := tamano_bloque
	var x0 := bx * t
	var z0 := bz * t
	var n := t + 1
	var vertices := PackedVector3Array()
	var normales := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(n * n)
	normales.resize(n * n)
	uvs.resize(n * n)
	for z in n:
		for x in n:
			var gx := x0 + x
			var gz := z0 + z
			var i := z * n + x
			vertices[i] = Vector3(x, _h(gx, gz), z)
			var hl := _h(maxi(gx - 1, 0), gz)
			var hr := _h(mini(gx + 1, lado), gz)
			var hd := _h(gx, maxi(gz - 1, 0))
			var hu := _h(gx, mini(gz + 1, lado))
			normales[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()
			uvs[i] = Vector2(gx, gz)
	var indices := PackedInt32Array()
	indices.resize(t * t * 6)
	var k := 0
	for z in t:
		for x in t:
			var a := z * n + x
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices[k] = a; indices[k + 1] = b; indices[k + 2] = c
			indices[k + 3] = b; indices[k + 4] = d; indices[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normales
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var malla := ArrayMesh.new()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	malla.surface_set_material(0, _material)

	var bloque := StaticBody3D.new()
	bloque.name = "Bloque_%d_%d" % [bx, bz]
	bloque.position = Vector3(x0, 0, z0)
	add_child(bloque)
	var mi := MeshInstance3D.new()
	mi.name = "Malla"
	mi.mesh = malla
	bloque.add_child(mi)

	# Colisión: HeightMapShape3D va centrada en su nodo y usa 1 m entre muestras.
	var forma := HeightMapShape3D.new()
	forma.map_width = n
	forma.map_depth = n
	var datos := PackedFloat32Array()
	datos.resize(n * n)
	for z in n:
		for x in n:
			datos[z * n + x] = _h(x0 + x, z0 + z)
	forma.map_data = datos
	var col := CollisionShape3D.new()
	col.name = "Colision"
	col.shape = forma
	col.position = Vector3(t * 0.5, 0, t * 0.5)
	bloque.add_child(col)
