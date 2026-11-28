class_name Golpe
## Utilidades del combate cuerpo a cuerpo (jugador y criaturas usan las mismas).
##
## Un golpe es un diccionario:
##   {"dano", "aturdir", "empuje", "origen": Node3D, "fuerte": bool, "punto": Vector3}
## Quien lo recibe implementa `recibir_golpe(golpe) -> String` y devuelve qué pasó:
##   "dano", "bloqueado", "guardia_rota", "esquivado", "muerto" o "" (no le afectó).


## Busca en `grupo` los cuerpos vivos dentro de la esfera (centro, radio) que todavía
## no estén en `ya_golpeados`, les aplica el golpe y los anota. Devuelve los resultados.
static func aplicar_en_area(arbol: SceneTree, grupo: String, centro: Vector3, radio: float,
		golpe: Dictionary, ya_golpeados: Dictionary) -> Array:
	var resultados := []
	for n in arbol.get_nodes_in_group(grupo):
		var cuerpo := n as Node3D
		if cuerpo == null or ya_golpeados.has(cuerpo) or not cuerpo.get("vivo"):
			continue
		var r_objetivo := float(cuerpo.get("radio_golpe")) if cuerpo.get("radio_golpe") != null else 0.5
		var alto := float(cuerpo.get("alto_golpe")) if cuerpo.get("alto_golpe") != null else 1.6
		# distancia al eje vertical del cuerpo (como una cápsula)
		var base := cuerpo.global_position
		var y := clampf(centro.y, base.y, base.y + alto)
		var punto_cercano := Vector3(base.x, y, base.z)
		var plano := Vector2(centro.x - base.x, centro.z - base.z).length()
		if plano > radio + r_objetivo or absf(centro.y - y) > radio:
			continue
		ya_golpeados[cuerpo] = true
		var g := golpe.duplicate()
		g["punto"] = punto_cercano.lerp(centro, 0.4)
		var res: String = cuerpo.recibir_golpe(g)
		resultados.append({"cuerpo": cuerpo, "resultado": res, "punto": g["punto"]})
	return resultados


## ¿`desde` está de frente al punto, dentro de un ángulo (grados)? `frente` = vector hacia delante.
static func de_frente(desde: Vector3, frente: Vector3, punto: Vector3, angulo: float) -> bool:
	var hacia := Vector3(punto.x - desde.x, 0, punto.z - desde.z)
	var f := Vector3(frente.x, 0, frente.z)
	if hacia.length() < 0.01 or f.length() < 0.01:
		return true
	return rad_to_deg(f.normalized().angle_to(hacia.normalized())) <= angulo * 0.5
