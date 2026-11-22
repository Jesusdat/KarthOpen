class_name FxBanco
extends Node
## Banco de efectos visuales del kit (FXForge). Lee efectos definidos por datos
## (JSON) y los arma en 3D: partículas, luces, anillos en el piso y destellos.
## También lanza proyectiles con cuerpo, estela y un efecto al llegar.
##
##   var fx := FxBanco.new()
##   add_child(fx)
##   fx.raiz = mi_mundo_3d
##   fx.cargar("res://datos/efectos.json")
##   fx.lanzar("golpe_enjambre", punto)
##   fx.lanzar("eco", punto, {"color": Color.CYAN})       # efectos teñibles
##   fx.proyectil("disparo_colonos", desde, hasta)
##
## Nombres con sufijo: si "golpe_fisura" no existe se prueba "golpe".
## El formato está en kit/fx/LEEME.md.

## Nodo 3D donde se cuelgan los efectos.
var raiz: Node3D
## Apagado: no arma nada (servidor sin pantalla).
var apagado := false
## Tope de efectos vivos a la vez; el siguiente borra al más viejo.
var max_vivos := 48
## Multiplica todas las cantidades de partículas (calidad baja: 0.5).
var densidad := 1.0
## Multiplica el tamaño de todas las partículas (según qué tan lejos va la cámara).
var tam_particulas := 1.0

var efectos := {}        # nombre -> definición ya resuelta (herencia aplicada)
var _crudo := {}         # nombre -> definición tal cual del JSON
var _plantillas := {}
var _resuelto := {}      # nombre pedido -> nombre de efecto o ""
var _vivos: Array = []   # contenedores vivos, del más viejo al más nuevo
var _textura_suave: Texture2D
var _quads := {}         # forma -> QuadMesh/PrismMesh compartida

const FORMAS := ["mota", "chispa", "gota", "humo", "esquirla"]

# ---------------------------------------------------------------- carga
func cargar(ruta: String) -> int:
	var texto := FileAccess.get_file_as_string(ruta)
	if texto == "":
		push_warning("FxBanco: no se pudo leer %s" % ruta)
		return ERR_FILE_CANT_OPEN
	var datos = JSON.parse_string(texto)
	if not datos is Dictionary:
		push_warning("FxBanco: %s no es un JSON válido" % ruta)
		return ERR_PARSE_ERROR
	return cargar_datos(datos)

func cargar_datos(datos: Dictionary) -> int:
	_plantillas = datos.get("plantillas", {})
	_crudo = datos.get("efectos", {})
	efectos.clear()
	_resuelto.clear()
	for nombre in _crudo:
		var e := _heredar(nombre, [])
		if e.has("capas"):
			e["capas"] = (e["capas"] as Array).map(_capa)
		if e.has("proyectil") and (e["proyectil"] as Dictionary).has("estela"):
			e["proyectil"]["estela"] = _capa(e["proyectil"]["estela"])
		efectos[nombre] = e
	return OK

# Una capa puede partir de una plantilla: {"hereda": "chispas_metal", "cantidad": 20}
func _capa(c: Dictionary) -> Dictionary:
	var padre := str(c.get("hereda", ""))
	if padre == "" or not _plantillas.has(padre):
		return c
	var base := _capa(_plantillas[padre]).duplicate(true)
	for k in c:
		if k != "hereda":
			base[k] = c[k]
	return base

func _heredar(nombre: String, visto: Array) -> Dictionary:
	var r: Dictionary = _crudo.get(nombre, _plantillas.get(nombre, {}))
	var padre := str(r.get("hereda", ""))
	if padre == "" or visto.has(nombre):
		return r.duplicate(true)
	var base := _heredar(padre, visto + [nombre])
	for k in r:
		if k != "hereda":
			base[k] = r[k].duplicate(true) if (r[k] is Dictionary or r[k] is Array) else r[k]
	return base

func existe(nombre: String) -> bool:
	return efectos.has(nombre)

## Nombre del efecto que se usará: el pedido, o el mismo quitando sufijos ("_fisura").
func resolver(nombre: String) -> String:
	if _resuelto.has(nombre):
		return _resuelto[nombre]
	var n := nombre
	while n != "" and not efectos.has(n):
		var corte := n.rfind("_")
		n = n.substr(0, corte) if corte > 0 else ""
	if n != "" and efectos[n].has("igual_a"):
		n = resolver(str(efectos[n]["igual_a"]))
	_resuelto[nombre] = n
	return n

## Cuánto dura un efecto (segundos) hasta que desaparece su última partícula.
func duracion(nombre: String) -> float:
	var n := resolver(nombre)
	if n == "":
		return 0.0
	var d := 0.0
	for c in efectos[n].get("capas", []):
		var vida := float(c.get("vida", c.get("dur", 0.3)))
		d = maxf(d, float(c.get("retraso", 0.0)) + vida * (1.0 + float(c.get("vida_azar", 0.0))))
	return d

# ---------------------------------------------------------------- lanzar
## opciones: "color" (tiñe las capas con "tinte": true), "escala", "direccion" (Vector3).
func lanzar(nombre: String, punto: Vector3, opciones := {}) -> Node3D:
	if not _listo():
		return null
	var n := resolver(nombre)
	if n == "":
		return null
	var e: Dictionary = efectos[n]
	var cont := Node3D.new()
	cont.name = "fx_" + n
	raiz.add_child(cont)
	cont.global_position = punto + Vector3.UP * float(e.get("altura", 0.0))
	var escala := float(opciones.get("escala", 1.0)) * float(e.get("escala", 1.0))
	if escala != 1.0:
		cont.scale = Vector3.ONE * escala
	var dir: Vector3 = opciones.get("direccion", Vector3.ZERO)
	if dir.length_squared() > 0.0001 and e.get("orientar", false):
		var plano := Vector3(dir.x, 0.0, dir.z)
		if plano.length_squared() > 0.0001:
			cont.look_at(cont.global_position + plano, Vector3.UP)
	for c in e.get("capas", []):
		_armar_capa(cont, c, opciones)
	_registrar(cont, duracion(n) + 0.25)
	return cont

## Proyectil: un cuerpo brillante con estela que va de "desde" a "hasta" y al llegar lanza "impacto".
func proyectil(nombre: String, desde: Vector3, hasta: Vector3, opciones := {}) -> Node3D:
	if not _listo():
		return null
	var n := resolver(nombre)
	if n == "" or not efectos[n].has("proyectil"):
		return lanzar(nombre, hasta, opciones)
	var p: Dictionary = efectos[n]["proyectil"]
	var alto := Vector3.UP * float(p.get("altura", 0.55))
	var a := desde + alto
	var b := hasta + alto
	var dist := a.distance_to(b)
	var t := clampf(dist / maxf(float(p.get("velocidad", 14.0)), 0.1), float(p.get("dur_min", 0.08)), float(p.get("dur_max", 0.6)))
	var cont := Node3D.new()
	cont.name = "fxp_" + n
	raiz.add_child(cont)
	cont.global_position = a
	var tinte: Color = opciones.get("color", Color(0, 0, 0, 0))
	if p.has("cuerpo"):
		var cu: Dictionary = p["cuerpo"]
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(cu.get("tam", 0.18))
		m.mesh = q
		var col := _color(cu.get("color", "#ffffff"))
		if tinte.a > 0.0 and cu.get("tinte", false):
			col = tinte
		m.material_override = _material(str(cu.get("forma", "mota")), float(cu.get("brillo", 3.0)), str(cu.get("mezcla", "suma")), col, BaseMaterial3D.BILLBOARD_ENABLED)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cont.add_child(m)
	if p.has("estela"):
		var est: Dictionary = (p["estela"] as Dictionary).duplicate(true)
		est["continuo"] = true
		est["vida"] = float(est.get("vida", 0.25))
		# Estela pareja: suficientes partículas para cubrir el camino (por_casilla) en lo que viven
		var vel := dist / maxf(t, 0.01)
		est["cantidad"] = maxi(int(est.get("cantidad", 16)), int(ceil(vel * float(est["vida"]) * float(est.get("por_casilla", 12.0)))))
		var gpu := _armar_capa(cont, est, opciones)
		if gpu is GPUParticles3D:
			# Las partículas de GPU dejan huecos con un emisor tan rápido; las de CPU
			# emiten en cada cuadro sobre el camino. Misma configuración, copiada.
			var cpu := CPUParticles3D.new()
			cpu.convert_from_particles(gpu)
			cpu.mesh = gpu.draw_pass_1
			cpu.material_override = gpu.material_override
			cpu.local_coords = false
			cpu.fixed_fps = 0
			cpu.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cpu.emitting = true
			cont.add_child(cpu)
			gpu.queue_free()
	if p.has("luz"):
		var l: Dictionary = (p["luz"] as Dictionary).duplicate()
		l["dur"] = t + 0.05
		_armar_capa(cont, dict_tipo(l, "luz"), opciones)
	var arco := float(p.get("arco", 0.0)) * dist
	var cinta := _cinta(cont, p, tinte)
	var tw := cont.create_tween()
	tw.tween_method(func(k: float):
		cont.global_position = a.lerp(b, k) + Vector3.UP * arco * 4.0 * k * (1.0 - k)
		if cinta != null:
			_mover_cinta(cinta, cont.global_position), 0.0, 1.0, t)
	var impacto := str(p.get("impacto", ""))
	tw.tween_callback(func():
		for h in cont.get_children():
			if h is GPUParticles3D or h is CPUParticles3D:
				h.emitting = false        # la estela termina de caer sola
			elif h is MeshInstance3D:
				h.visible = false
		if impacto != "":
			lanzar(impacto, hasta, opciones))
	var vida_estela := float(p.get("estela", {}).get("vida", 0.25)) * 1.5
	_registrar(cont, t + vida_estela + 0.2)
	return cont

# Cinta: tira brillante que sigue al proyectil y se adelgaza hacia atrás. No depende de
# los cuadros por segundo (las partículas sí dejan huecos si el juego va lento).
func _cinta(cont: Node3D, p: Dictionary, tinte: Color) -> MeshInstance3D:
	var cfg = p.get("cinta", {})
	if cfg == null or (cfg is bool and not cfg):
		return null
	if not cfg is Dictionary:
		cfg = {}
	var cu: Dictionary = p.get("cuerpo", {})
	# Por defecto, el color de en medio de la estela (más saturado que el cuerpo, que brilla casi blanco)
	var por_defecto = cu.get("color", "#ffffff")
	var est_cols = p.get("estela", {}).get("color", [])
	if est_cols is Array and est_cols.size() >= 2:
		por_defecto = est_cols[1]
	var col := _color(cfg.get("color", por_defecto))
	if tinte.a > 0.0 and (cfg.get("tinte", cu.get("tinte", false))):
		col = tinte
	var m := MeshInstance3D.new()
	m.top_level = true            # sus puntos van en coordenadas del mundo
	m.mesh = ImmediateMesh.new()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _material("cinta", float(cfg.get("brillo", 2.2)), "suma", col, BaseMaterial3D.BILLBOARD_DISABLED)
	mat.albedo_texture = null
	m.material_override = mat
	m.set_meta("puntos", [])
	m.set_meta("largo", float(cfg.get("largo", 0.9)))
	m.set_meta("ancho", float(cfg.get("ancho", float(cu.get("tam", 0.18)) * 0.7)))
	cont.add_child(m)
	m.global_transform = Transform3D.IDENTITY
	return m

func _mover_cinta(m: MeshInstance3D, punto: Vector3) -> void:
	var pts: Array = m.get_meta("puntos")
	pts.append(punto)
	var largo: float = m.get_meta("largo")
	var total := 0.0
	for i in range(pts.size() - 1, 0, -1):
		total += (pts[i] as Vector3).distance_to(pts[i - 1])
		if total > largo:
			pts = pts.slice(i - 1)
			break
	m.set_meta("puntos", pts)
	var im: ImmediateMesh = m.mesh
	im.clear_surfaces()
	if pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var ancho: float = m.get_meta("ancho")
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p: Vector3 = pts[i]
		var sig: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var ant: Vector3 = pts[maxi(i - 1, 0)]
		var tan := (sig - ant).normalized()
		var vista := (cam.global_position - p).normalized() if cam != null else Vector3.UP
		var lado := tan.cross(vista)
		if lado.length_squared() < 0.0001:
			lado = tan.cross(Vector3.UP)
		lado = lado.normalized()
		var k := float(i) / float(pts.size() - 1)     # 0 = cola, 1 = cabeza
		var w := ancho * 0.5 * k
		im.surface_set_color(Color(1, 1, 1, k * k))
		im.surface_add_vertex(p - lado * w)
		im.surface_set_color(Color(1, 1, 1, k * k))
		im.surface_add_vertex(p + lado * w)
	im.surface_end()

static func dict_tipo(d: Dictionary, tipo: String) -> Dictionary:
	var r := d.duplicate()
	r["tipo"] = tipo
	return r

func vivos() -> int:
	_vivos = _vivos.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
	return _vivos.size()

func limpiar() -> void:
	for c in _vivos:
		if is_instance_valid(c):
			c.queue_free()
	_vivos.clear()

# ---------------------------------------------------------------- interno
func _listo() -> bool:
	return not apagado and is_inside_tree() and raiz != null and is_instance_valid(raiz) and raiz.is_inside_tree()

func _registrar(cont: Node3D, vida: float) -> void:
	vivos()
	while _vivos.size() >= max_vivos:
		var viejo = _vivos.pop_front()
		if is_instance_valid(viejo):
			viejo.queue_free()
	_vivos.append(cont)
	var ref: WeakRef = weakref(cont)   # el efecto pudo borrarse antes (tope, limpiar)
	get_tree().create_timer(vida, false).timeout.connect(func():
		var c = ref.get_ref()
		if c != null:
			c.queue_free())

func _armar_capa(cont: Node3D, c: Dictionary, opciones: Dictionary) -> Node:
	var tipo := str(c.get("tipo", "particulas"))
	var tinte: Color = opciones.get("color", Color(0, 0, 0, 0))
	var usar_tinte := tinte.a > 0.0 and bool(c.get("tinte", false))
	var nodo: Node = null
	match tipo:
		"particulas":
			nodo = _particulas(c, tinte if usar_tinte else Color(0, 0, 0, 0))
		"luz":
			nodo = _luz(c, tinte if usar_tinte else _color(c.get("color", "#ffffff")))
		"anillo":
			nodo = _anillo(c, tinte if usar_tinte else _color(c.get("color", "#ffffff")))
		"destello":
			nodo = _destello(c, tinte if usar_tinte else _color(c.get("color", "#ffffff")))
		_:
			push_warning("FxBanco: capa desconocida '%s'" % tipo)
			return null
	var off = c.get("pos", null)
	cont.add_child(nodo)
	if off is Array and off.size() == 3:
		nodo.position = Vector3(float(off[0]), float(off[1]), float(off[2]))
	var retraso := float(c.get("retraso", 0.0))
	if retraso > 0.0 and nodo is GPUParticles3D:
		nodo.emitting = false
		var ref: WeakRef = weakref(nodo)
		get_tree().create_timer(retraso, false).timeout.connect(func():
			var n = ref.get_ref()
			if n != null:
				n.emitting = true)
	return nodo

func _particulas(c: Dictionary, tinte: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var continuo := bool(c.get("continuo", false))
	p.amount = maxi(1, int(round(float(c.get("cantidad", 12)) * densidad)))
	p.lifetime = maxf(0.02, float(c.get("vida", 0.5)))
	p.one_shot = not continuo
	p.explosiveness = 0.0 if continuo else float(c.get("explosividad", 0.95))
	p.local_coords = bool(c.get("local", false))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var m := ParticleProcessMaterial.new()
	var d = c.get("direccion", [0, 1, 0])
	m.direction = Vector3(float(d[0]), float(d[1]), float(d[2])).normalized()
	m.spread = float(c.get("dispersion", 60.0))
	var vel = c.get("velocidad", [1.0, 2.5])
	m.initial_velocity_min = float(vel[0])
	m.initial_velocity_max = float(vel[1])
	m.gravity = Vector3(0, float(c.get("gravedad", 0.0)), 0)
	m.damping_min = float(c.get("amortiguar", 0.0))
	m.damping_max = float(c.get("amortiguar", 0.0)) * 1.3
	m.lifetime_randomness = clampf(float(c.get("vida_azar", 0.3)), 0.0, 1.0)
	var sube := float(c.get("sube", 0.0))     # aceleración hacia arriba (motas que flotan)
	if sube != 0.0:
		m.linear_accel_min = 0.0
		m.linear_accel_max = 0.0
		m.gravity += Vector3(0, sube, 0)
	var remolino := float(c.get("remolino", 0.0))
	if remolino != 0.0:
		m.orbit_velocity_min = remolino * 0.7
		m.orbit_velocity_max = remolino
	var tang := float(c.get("hacia_centro", 0.0))
	if tang != 0.0:
		m.radial_accel_min = -tang
		m.radial_accel_max = -tang * 0.6
	var em: Dictionary = c.get("emision", {})
	if em.has("anillo"):
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		m.emission_ring_axis = Vector3.UP
		m.emission_ring_radius = float(em["anillo"])
		m.emission_ring_inner_radius = float(em["anillo"]) * float(em.get("interior", 0.85))
		m.emission_ring_height = float(em.get("alto", 0.05))
	elif em.has("caja"):
		var cj = em["caja"]
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(float(cj[0]), float(cj[1]), float(cj[2]))
	else:
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = maxf(0.001, float(em.get("esfera", 0.08)))
	var tam = c.get("tam", [0.08, 0.02])
	var t0 := float(tam[0]) if tam is Array else float(tam)
	var t1 := float(tam[1]) if tam is Array and tam.size() > 1 else t0
	m.scale_min = 1.0 - float(c.get("tam_azar", 0.3))
	m.scale_max = 1.0
	var curva := Curve.new()
	curva.max_value = maxf(1.0, t1 / maxf(t0, 0.0001))
	curva.add_point(Vector2(0.0, 1.0))
	if c.has("tam_medio"):
		curva.add_point(Vector2(0.4, float(c["tam_medio"]) / maxf(t0, 0.0001)))
	curva.add_point(Vector2(1.0, t1 / maxf(t0, 0.0001)))
	var ct := CurveTexture.new()
	ct.curve = curva
	m.scale_curve = ct
	m.color_ramp = _rampa(c, tinte)
	var forma := str(c.get("forma", "mota"))
	if forma == "esquirla":
		m.particle_flag_rotate_y = true
		m.angle_min = 0.0
		m.angle_max = 360.0
		m.angular_velocity_min = -float(c.get("giro", 360.0))
		m.angular_velocity_max = float(c.get("giro", 360.0))
	elif forma == "chispa":
		m.particle_flag_align_y = true
	else:
		m.angle_min = 0.0
		m.angle_max = 360.0
		m.angular_velocity_min = -float(c.get("giro", 0.0))
		m.angular_velocity_max = float(c.get("giro", 0.0))
	p.process_material = m
	p.draw_pass_1 = _malla(forma, t0 * tam_particulas)
	var mezcla := str(c.get("mezcla", "mezcla" if forma in ["gota", "humo", "esquirla"] else "suma"))
	var bb := BaseMaterial3D.BILLBOARD_PARTICLES
	if forma == "chispa":
		bb = BaseMaterial3D.BILLBOARD_FIXED_Y
	elif forma == "esquirla":
		bb = BaseMaterial3D.BILLBOARD_DISABLED
	p.material_override = _material(forma, float(c.get("brillo", 1.5)), mezcla, Color.WHITE, bb)
	p.emitting = true
	return p

func _rampa(c: Dictionary, tinte: Color) -> GradientTexture1D:
	var cols: Array = c.get("color", ["#ffffff"])
	if not cols is Array:
		cols = [cols]
	var g := Gradient.new()
	var lista: Array = []
	for x in cols:
		var col := _color(x)
		if tinte.a > 0.0:
			# conserva la luz de cada parada, con el color del tinte
			var l := col.get_luminance()
			col = Color(tinte.r * l * 1.6, tinte.g * l * 1.6, tinte.b * l * 1.6, col.a)
		lista.append(col)
	if not c.get("sin_fundido", false):
		var ultimo: Color = lista[-1]
		lista.append(Color(ultimo, 0.0))
	var offs := PackedFloat32Array()
	var colores := PackedColorArray()
	var fundido_desde := float(c.get("fundido", 0.6))
	for i in lista.size():
		var k := float(i) / float(maxi(lista.size() - 1, 1))
		if not c.get("sin_fundido", false) and i == lista.size() - 2 and lista.size() > 2:
			k = maxf(k, fundido_desde)
		offs.append(k)
		colores.append(lista[i])
	g.offsets = offs
	g.colors = colores
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 64
	return gt

func _malla(forma: String, tam: float) -> Mesh:
	var clave := "%s_%.3f" % [forma, tam]
	if _quads.has(clave):
		return _quads[clave]
	var malla: Mesh
	match forma:
		"chispa":
			var q := QuadMesh.new()
			q.size = Vector2(tam * 0.3, tam * 1.6)
			malla = q
		"esquirla":
			var pr := PrismMesh.new()
			pr.size = Vector3(tam * 0.6, tam * 1.4, tam * 0.4)
			malla = pr
		_:
			var q := QuadMesh.new()
			q.size = Vector2.ONE * tam
			malla = q
	_quads[clave] = malla
	return malla

func _material(forma: String, brillo: float, mezcla: String, col: Color, bb: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	# El brillo empuja el color sobre 1 para que lo tome el resplandor (glow), sin lavarlo a blanco
	var k := 1.0 + (brillo - 1.0) * 0.35
	mat.albedo_color = Color(col.r * k, col.g * k, col.b * k, col.a)
	mat.billboard_mode = bb
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if mezcla == "suma":
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if forma != "esquirla":
		mat.albedo_texture = _suave(forma == "humo")
	return mat

func _suave(difuso := false) -> Texture2D:
	if _textura_suave != null and not difuso:
		return _textura_suave
	var g := Gradient.new()
	if difuso:
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	if not difuso:
		_textura_suave = t
	return t

func _luz(c: Dictionary, col: Color) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	var e := float(c.get("energia", 2.0))
	l.light_energy = e
	l.omni_range = float(c.get("alcance", 3.0))
	l.shadow_enabled = false
	var tw := _tween(l)
	tw.tween_interval(float(c.get("retraso", 0.0)))
	tw.tween_property(l, "light_energy", 0.0, maxf(0.02, float(c.get("dur", 0.25)))).from(e).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return l

func _anillo(c: Dictionary, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var toro := TorusMesh.new()
	var gros := float(c.get("grosor", 0.06))
	toro.inner_radius = 1.0 - gros
	toro.outer_radius = 1.0
	toro.rings = 48
	toro.ring_segments = 6
	m.mesh = toro
	var mat := _material("anillo", 1.0 + (float(c.get("brillo", 1.8)) - 1.0) * 0.5, str(c.get("mezcla", "suma")), col, BaseMaterial3D.BILLBOARD_DISABLED)
	mat.albedo_texture = null
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r = c.get("radio", [0.2, 2.0])
	var r0 := float(r[0])
	var r1 := float(r[1])
	m.scale = Vector3(r0, 0.25, r0)
	var dur := maxf(0.02, float(c.get("dur", 0.4)))
	var tw := _tween(m)
	tw.tween_interval(float(c.get("retraso", 0.0)))
	tw.tween_property(m, "scale", Vector3(r1, 0.25, r1), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur).from(col.a).set_ease(Tween.EASE_IN)
	return m

func _destello(c: Dictionary, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	m.mesh = q
	var mat := _material("mota", float(c.get("brillo", 3.0)), "suma", col, BaseMaterial3D.BILLBOARD_ENABLED)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tam = c.get("tam", [0.8, 0.2])
	m.scale = Vector3.ONE * float(tam[0])
	var dur := maxf(0.02, float(c.get("dur", 0.12)))
	var tw := _tween(m)
	tw.tween_interval(float(c.get("retraso", 0.0)))
	tw.tween_property(m, "scale", Vector3.ONE * float(tam[1]), dur)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur).from(col.a)
	return m

# Tween ligado al nodo (muere con él) que se puede crear antes de meter el nodo al árbol.
func _tween(n: Node) -> Tween:
	return raiz.create_tween().bind_node(n)

static func _color(v) -> Color:
	if v is Color:
		return v
	if v is Array:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return Color.from_string(str(v), Color.WHITE)
