@tool
class_name VegetationBaker
extends RefCounted

## Hornea impostores de árboles y tarjetas de hierba. Sus viewports son temporales;
## registra los materiales resultantes en el planeta para que reciban luz y viento.

const GrassPatchMipmaps = preload("res://scripts/planet/grass_patch_mipmaps.gd")

## Shader del impostor (aspa LOD3): unshaded pero con terminador día/noche.
const _IMPOSTOR_SHADER_PATH := "res://shaders/tree_impostor.gdshader"
var _impostor_shader: Shader = null

## Shaders de la tarjeta de parche de hierba: el de horneado (albedo plano dentro
## del SubViewport) y el de la tarjeta ya instanciada. Ver bake_grass_patch.
const _GRASS_PATCH_SHADER_PATH := "res://shaders/grass_patch_impostor.gdshader"
const _GRASS_PATCH_BAKE_SHADER_PATH := "res://shaders/grass_patch_bake.gdshader"
var _grass_patch_shader: Shader = null
var _grass_patch_bake_shader: Shader = null

var _planet: Planet


func _init(planet: Planet) -> void:
	_planet = planet


## Genera un impostor billboard en aspa (2 quads perpendiculares) como LOD3 de un árbol.
## Renderiza 'source_mesh' de lado a una textura RGBA (con alfa) usando un SubViewport de
## mundo propio, y construye el aspa mapeando esa textura. El AABB del aspa coincide con el
## del árbol para que no haya "pop" de tamaño al cruzar LOD2->LOD3.
## Async: espera 2 frames a que el render-target se dibuje antes de leer la imagen.
func bake_tree_impostor(source_mesh: Mesh, tex_size: int = 256) -> Mesh:
	if source_mesh == null or _planet.voxel_instancer == null or not _planet.voxel_instancer.is_inside_tree():
		return null

	var aabb: AABB = source_mesh.get_aabb()
	var center: Vector3 = aabb.get_center()
	# lado del encuadre ortográfico cuadrado (+5% de margen); el árbol queda centrado.
	var view_size: float = maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z)) * 1.05
	if view_size <= 0.0:
		return null

	# --- SubViewport aislado: renderiza SOLO el árbol + sus luces, no la escena real ---
	var vp := SubViewport.new()
	vp.size = Vector2i(tex_size, tex_size)
	vp.transparent_bg = true                 # imprescindible para capturar el alfa del follaje
	vp.own_world_3d = true                    # mundo propio -> sin fondo de la escena real
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = source_mesh
	vp.add_child(mesh_inst)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45, -30, 0)
	key_light.light_energy = 1.2
	key_light.shadow_enabled = false
	vp.add_child(key_light)

	# relleno suave para que la cara en sombra no quede completamente negra en la captura.
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20, 150, 0)
	fill_light.light_energy = 0.4
	fill_light.shadow_enabled = false
	vp.add_child(fill_light)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	var cam_dist: float = view_size * 2.0
	cam.near = maxf(cam_dist - view_size, 0.05)
	cam.far = cam_dist + view_size
	cam.position = center + Vector3(0.0, 0.0, cam_dist)
	cam.look_at_from_position(cam.position, center, Vector3.UP)
	vp.add_child(cam)

	_planet.voxel_instancer.add_child(vp)            # el viewport debe estar en el árbol para renderizar
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	vp.queue_free()

	if img == null or img.is_empty():
		push_warning("Planet: bake de impostor devolvió imagen vacía; se mantiene la geometría LOD3.")
		return null

	var tex := ImageTexture.create_from_image(img)
	return _build_impostor_cross_mesh(aabb, tex, view_size)


## Construye el aspa (2 quads perpendiculares) que abarca el AABB del árbol y mapea la textura
## del impostor. Como la textura es cuadrada (lado view_size) y el árbol ocupa solo su parte
## central, las UV recortan justo esa región (sin deformar y sin cambiar de tamaño aparente).
func _build_impostor_cross_mesh(aabb: AABB, tex: Texture2D, view_size: float) -> ArrayMesh:
	var center: Vector3 = aabb.get_center()
	var h: float = aabb.size.y
	var w: float = maxf(aabb.size.x, aabb.size.z)      # ancho común de ambos quads
	var hw: float = w * 0.5
	var y0: float = aabb.position.y                    # base (y~0)
	var y1: float = aabb.position.y + h                # copa

	# fracción central de la textura ocupada por el árbol (el resto es margen transparente)
	var fu: float = (w / view_size) if view_size > 0.0 else 1.0
	var fv: float = (h / view_size) if view_size > 0.0 else 1.0
	var u0: float = 0.5 - fu * 0.5
	var u1: float = 0.5 + fu * 0.5
	var v0: float = 0.5 - fv * 0.5                      # arriba (Y alto)
	var v1: float = 0.5 + fv * 0.5                      # abajo (Y bajo)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Quad en el plano XY (normal Z), centrado en X
	_add_impostor_quad(st,
		[Vector3(center.x - hw, y1, center.z), Vector3(center.x + hw, y1, center.z),
		 Vector3(center.x + hw, y0, center.z), Vector3(center.x - hw, y0, center.z)],
		[Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)],
		Vector3.BACK)
	# Quad en el plano ZY (normal X), centrado en Z (reutiliza la misma vista de lado)
	_add_impostor_quad(st,
		[Vector3(center.x, y1, center.z - hw), Vector3(center.x, y1, center.z + hw),
		 Vector3(center.x, y0, center.z + hw), Vector3(center.x, y0, center.z - hw)],
		[Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)],
		Vector3.RIGHT)

	# Shader propio: unshaded (barato) pero respeta el terminador día/noche del
	# planeta. Con StandardMaterial3D unshaded el impostor brillaba a albedo pleno
	# de noche, ignorando la sombra planetaria del resto de la vegetación.
	if _impostor_shader == null:
		_impostor_shader = load(_IMPOSTOR_SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = _impostor_shader
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("alpha_scissor_threshold", 0.5)
	# Registrar para recibir el push de sol (light_direction/planet_position) cada
	# frame; sin viento (wind_speed 0). _planet.item_transparent_materials ya está limpio
	# en este punto de la carga (_load_vegetation lo vació antes de registrar items).
	_planet.item_transparent_materials.append({"shader": mat, "wind_speed": 0.0})

	st.set_material(mat)

	return st.commit()


## Añade un quad (2 triángulos) a un SurfaceTool. corners/uvs en orden TL, TR, BR, BL.
func _add_impostor_quad(st: SurfaceTool, corners: Array, uvs: Array, normal: Vector3) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])


## Hornea la tarjeta que sustituye a un parche entero de hierba a distancia: reparte
## 'clump_count' matas en un cuadrado de 'size_m' y fotografía el clúster dos veces
## (de lado y en cenital) a las dos capas de un Texture2DArray. Devuelve el aspa +
## quad horizontal que las mapean, o null si el render falla.
## Una tarjeta vale por decenas de matas: es lo que compensa que las bandas de LOD
## altas den 4x menos instancias por m² cada una.
## La escala se multiplica en dos sitios y hay que cuadrar los dos o el parche sale de
## otro tamaño que la hierba real: 'clump_scale' ± 'clump_scale_jitter' debe reproducir
## el min_scale/max_scale del generador de HIERBA al que releva, y el generador de la
## TARJETA debe ir a min_scale = max_scale = 1.0 (la tarjeta ya trae sus metros).
## Async: cada vista espera 2 frames a que el render-target se dibuje.
func bake_grass_patch(source_mesh: Mesh, cfg: Dictionary) -> Mesh:
	if source_mesh == null or _planet.voxel_instancer == null or not _planet.voxel_instancer.is_inside_tree():
		return null

	# Lo que importa es la resolución por metro: el encuadre cubre el parche entero, así
	# que a 256 px sobre 5 m las briznas caen por debajo del píxel y los mips las borran.
	var tex_size: int = int(cfg.get("tex_size", 512))
	var scatter_size: float = float(cfg.get("size_m", 4.0))
	var clump_scale: float = float(cfg.get("clump_scale", 1.0))
	var scale_jitter: float = clampf(float(cfg.get("clump_scale_jitter", 0.35)), 0.0, 1.0)
	var aabb: AABB = source_mesh.get_aabb()
	var max_clump: float = clump_scale * (1.0 + scale_jitter)
	if scatter_size <= 0.0 or aabb.size.y <= 0.0 or max_clump <= 0.0:
		return null

	# Encuadre: peor caso teórico (las matas del borde sobresalen del cuadrado de reparto)
	# para no recortar nada. La tarjeta NO usa estas medidas, se ajusta luego a lo que de
	# verdad se haya dibujado: con reparto aleatorio el contenido se queda bastante corto.
	var frame_size: float = scatter_size + maxf(aabb.size.x, aabb.size.z) * max_clump
	var frame_height: float = aabb.size.y * max_clump
	var view_size: float = maxf(frame_size, frame_height) * 1.05
	var side_cam_y: float = frame_height * 0.5

	var cluster := _build_grass_patch_cluster(source_mesh, cfg)
	if cluster == null:
		return null

	# Lateral: alimenta el aspa. Centrada a media altura para que el parche quede
	# centrado también en vertical dentro de la textura.
	var side_img := await _render_ortho_to_image(cluster,
		Vector3(0.0, side_cam_y, view_size), Vector3(0.0, side_cam_y, 0.0),
		Vector3.UP, view_size, tex_size)
	# Cenital pura: es la única proyección que mapea EXACTO sobre el quad horizontal
	# (ortográfica = afín, el cuadrado del suelo cae en un rectángulo sin deformar).
	var top_img := await _render_ortho_to_image(cluster,
		Vector3(0.0, view_size, 0.0), Vector3.ZERO,
		Vector3.FORWARD, view_size, tex_size)

	cluster.queue_free()

	if side_img == null or top_img == null:
		push_warning("Planet: bake de parche de hierba devolvió imagen vacía; el item se queda sin tarjeta.")
		return null

	# Recuadro realmente pintado en cada vista: de ahí salen las medidas y las UV de la
	# tarjeta, en vez del peor caso, que dejaba ~0.5 m de margen transparente por lado.
	var side_rect: Rect2i = side_img.get_used_rect()
	var top_rect: Rect2i = top_img.get_used_rect()
	if side_rect.size.x <= 0 or side_rect.size.y <= 0 or top_rect.size.x <= 0 or top_rect.size.y <= 0:
		push_warning("Planet: el parche de hierba se horneó vacío; el item se queda sin tarjeta.")
		return null

	side_img = _fill_transparent_rgb(side_img)
	top_img = _fill_transparent_rgb(top_img)
	var alpha_threshold: float = float(cfg.get("alpha_scissor", 0.25))
	side_img = GrassPatchMipmaps.generate(side_img, alpha_threshold)
	top_img = GrassPatchMipmaps.generate(top_img, alpha_threshold)
	# Texture2DArray y no un atlas en una sola imagen: con atlas los mips mezclan las
	# dos vistas entre sí y el aspa acaba con manchas de la cenital.
	var atlas := Texture2DArray.new()
	if atlas.create_from_images([side_img, top_img]) != OK:
		push_warning("Planet: no se pudo crear el Texture2DArray del parche de hierba.")
		return null

	var card := _build_grass_patch_card(side_rect, top_rect, tex_size, view_size, side_cam_y, atlas, cfg)
	_apply_grass_handoff(card, source_mesh, cfg)
	return card


## Completa la transición a tarjetas antes del límite de distancia de la hierba.
## Actualiza ambos materiales para que la tarjeta sea visible antes de desvanecer la hierba.
func _apply_grass_handoff(card: Mesh, source_mesh: Mesh, cfg: Dictionary) -> void:
	var card_width: float = float(cfg.get("fade_width_m", 20.0))
	var grass_width: float = float(cfg.get("grass_fade_width_m", 20.0))

	# 'handoff_end_m' pincha el final a mano; si no, se deduce del alcance real de la
	# banda menos un margen, para cerrar antes de que empiecen a caerse bloques.
	var grass_end: float = float(cfg.get("handoff_end_m", 0.0))
	if grass_end <= 0.0:
		var band: float = _planet._get_lod_view_distance(int(cfg.get("handoff_lod_index", 1)))
		grass_end = band - float(cfg.get("handoff_margin_m", 8.0))
	var grass_start: float = maxf(grass_end - grass_width, 1.0)

	var grass_mat := source_mesh.surface_get_material(0) as ShaderMaterial
	if grass_mat != null:
		grass_mat.set_shader_parameter("fade_start", grass_start)
		grass_mat.set_shader_parameter("fade_end", grass_end)

	var card_mat := card.surface_get_material(0) as ShaderMaterial
	if card_mat != null:
		card_mat.set_shader_parameter("fade_start", maxf(grass_start - card_width, 1.0))
		card_mat.set_shader_parameter("fade_width", card_width)


## Pinta de color medio el RGB de los píxeles transparentes, conservando el alfa.
## Cada nivel de mipmap promedia RGB sin mirar el alfa, así que con el fondo negro del
## render la tarjeta se ensucia hacia negro según se aleja, y peor cuanto más hueco
## tenga la vista (la cenital, llena de claros, se ennegrecía antes que la lateral).
## El color se saca de la propia imagen y no de los uniforms del material para no tener
## que adivinar en qué espacio de color viene el render.
func _fill_transparent_rgb(img: Image) -> Image:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = img.get_data()

	var sum_r: int = 0
	var sum_g: int = 0
	var sum_b: int = 0
	var opaque: int = 0
	var i: int = 0
	while i < data.size():
		if data[i + 3] >= 128:
			sum_r += data[i]
			sum_g += data[i + 1]
			sum_b += data[i + 2]
			opaque += 1
		i += 4
	if opaque == 0:
		return img

	var avg_r: int = sum_r / opaque
	var avg_g: int = sum_g / opaque
	var avg_b: int = sum_b / opaque
	i = 0
	while i < data.size():
		if data[i + 3] < 128:
			data[i] = avg_r
			data[i + 1] = avg_g
			data[i + 2] = avg_b
		i += 4

	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Nodo temporal con 'clump_count' copias de la mata repartidas en un cuadrado de
## 'size_m' (rejilla con jitter), con giro y escala deterministas ('seed'). Apoyadas en y=0.
func _build_grass_patch_cluster(source_mesh: Mesh, cfg: Dictionary) -> Node3D:
	var bake_mat := _build_grass_patch_bake_material(source_mesh, cfg)
	if bake_mat == null:
		return null

	var half: float = float(cfg.get("size_m", 4.0)) * 0.5
	var count: int = maxi(int(cfg.get("clump_count", 36)), 1)
	var clump_scale: float = float(cfg.get("clump_scale", 1.0))
	var scale_jitter: float = clampf(float(cfg.get("clump_scale_jitter", 0.35)), 0.0, 1.0)
	var base_y: float = source_mesh.get_aabb().position.y

	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 1337))

	# Rejilla con jitter en vez de azar puro: con dos docenas de muestras el azar deja
	# calvas grandes (la vista cenital horneada salía con un mordisco). Los recuentos que
	# llenan la rejilla entera (16, 20, 25...) reparten mejor que los que dejan coja la
	# última fila.
	var cols: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(cols)))
	var cell_x: float = half * 2.0 / float(cols)
	var cell_z: float = half * 2.0 / float(rows)

	var root := Node3D.new()
	for i in count:
		var inst := MeshInstance3D.new()
		inst.mesh = source_mesh
		inst.material_override = bake_mat
		var s: float = clump_scale * rng.randf_range(1.0 - scale_jitter, 1.0 + scale_jitter)
		var t := Transform3D.IDENTITY.scaled(Vector3(s, s, s)).rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		# El AABB del modelo no arranca en y=0: se sube para apoyarlo en el suelo.
		t.origin = Vector3(
			-half + (float(i % cols) + rng.randf()) * cell_x,
			-base_y * s,
			-half + (float(i / cols) + rng.randf()) * cell_z)
		inst.transform = t
		root.add_child(inst)
	return root


## Material de horneado del parche: hereda el degradado del shader de hierba del item
## para que cada variante (verde / verde-amarillo / amarillo) hornee su propio color.
func _build_grass_patch_bake_material(source_mesh: Mesh, cfg: Dictionary) -> ShaderMaterial:
	if _grass_patch_bake_shader == null:
		_grass_patch_bake_shader = load(_GRASS_PATCH_BAKE_SHADER_PATH)
	if _grass_patch_bake_shader == null:
		return null

	var mat := ShaderMaterial.new()
	mat.shader = _grass_patch_bake_shader
	var src := source_mesh.surface_get_material(0) as ShaderMaterial
	if src != null:
		for param in ["base_color", "tip_color", "grass_height"]:
			var value = src.get_shader_parameter(param)
			if value != null:
				mat.set_shader_parameter(param, value)
	mat.set_shader_parameter("ao_strength", float(cfg.get("bake_ao", 0.35)))
	return mat


## Fotografía 'content' con una cámara ortográfica que encuadra 'view_size' metros,
## sobre fondo transparente y en un mundo 3D propio (no se cuela la escena real).
## 'content' entra y sale del viewport: el llamante conserva su propiedad.
## No añade luces: el material de horneado es unshaded.
func _render_ortho_to_image(content: Node3D, eye: Vector3, target: Vector3, up: Vector3,
		view_size: float, tex_size: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(tex_size, tex_size)
	vp.transparent_bg = true                  # imprescindible para capturar el alfa
	vp.own_world_3d = true                    # mundo propio -> sin fondo de la escena real
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.add_child(content)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_size
	cam.near = 0.05
	cam.far = eye.distance_to(target) + view_size * 2.0
	cam.look_at_from_position(eye, target, up)
	vp.add_child(cam)

	_planet.voxel_instancer.add_child(vp)             # el viewport debe estar en el árbol para renderizar
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	vp.remove_child(content)
	vp.queue_free()

	if img == null or img.is_empty():
		return null
	return img


## Aspa vertical + quad horizontal que mapean las dos capas del atlas del parche.
## COLOR.r marca la capa (0 = lateral en el aspa, 1 = cenital en el horizontal).
## Cada quad se ajusta al recuadro que la vista correspondiente pintó de verdad, así que
## no queda margen transparente y la escala es exacta: los píxeles del recuadro se
## deshacen a metros con la misma proyección ortográfica que los generó.
func _build_grass_patch_card(side_rect: Rect2i, top_rect: Rect2i, tex_size: int,
		view_size: float, side_cam_y: float, atlas: Texture2DArray, cfg: Dictionary) -> ArrayMesh:
	# Lateral: cámara en +Z mirando a -Z, centrada en (0, side_cam_y). u sigue a +X y v
	# baja en pantalla, así que v crece hacia Y bajo.
	var su0: float = float(side_rect.position.x) / tex_size
	var su1: float = float(side_rect.end.x) / tex_size
	var sv0: float = float(side_rect.position.y) / tex_size
	var sv1: float = float(side_rect.end.y) / tex_size
	var x_min: float = (su0 - 0.5) * view_size
	var x_max: float = (su1 - 0.5) * view_size
	var y_max: float = side_cam_y + (0.5 - sv0) * view_size
	var y_min: float = side_cam_y + (0.5 - sv1) * view_size

	# Cenital: cámara encima con up = FORWARD, así que u sigue a +X y v a +Z.
	var tu0: float = float(top_rect.position.x) / tex_size
	var tu1: float = float(top_rect.end.x) / tex_size
	var tv0: float = float(top_rect.position.y) / tex_size
	var tv1: float = float(top_rect.end.y) / tex_size
	var gx_min: float = (tu0 - 0.5) * view_size
	var gx_max: float = (tu1 - 0.5) * view_size
	var gz_min: float = (tv0 - 0.5) * view_size
	var gz_max: float = (tv1 - 0.5) * view_size

	# Medio píxel hacia dentro: evita arrastrar la fila transparente del borde al filtrar.
	var half_px: float = 0.5 / float(tex_size)
	var uvs_side: Array = [
		Vector2(su0 + half_px, sv0 + half_px), Vector2(su1 - half_px, sv0 + half_px),
		Vector2(su1 - half_px, sv1 - half_px), Vector2(su0 + half_px, sv1 - half_px)]
	var uvs_top: Array = [
		Vector2(tu0 + half_px, tv0 + half_px), Vector2(tu1 - half_px, tv0 + half_px),
		Vector2(tu1 - half_px, tv1 - half_px), Vector2(tu0 + half_px, tv1 - half_px)]
	var layer_side := Color(0.0, 0.0, 0.0, 1.0)
	var layer_top := Color(1.0, 0.0, 0.0, 1.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Aspa: quad en el plano XY y quad en el plano ZY, ambos con la vista lateral. El
	# segundo reutiliza el ancho del primero, girado 90º.
	_add_patch_quad(st,
		[Vector3(x_min, y_max, 0.0), Vector3(x_max, y_max, 0.0),
		 Vector3(x_max, y_min, 0.0), Vector3(x_min, y_min, 0.0)],
		uvs_side, Vector3.BACK, layer_side)
	_add_patch_quad(st,
		[Vector3(0.0, y_max, x_min), Vector3(0.0, y_max, x_max),
		 Vector3(0.0, y_min, x_max), Vector3(0.0, y_min, x_min)],
		uvs_side, Vector3.RIGHT, layer_side)

	# Quad horizontal, algo elevado para no pelearse con el terreno en el z-buffer.
	# Con vertical_alignment radial se apoya en el plano tangente, así que en
	# pendientes fuertes se hunde por un lado: limitar max_slope_degrees del generador.
	var gy: float = (y_max - y_min) * float(cfg.get("ground_quad_height", 0.25))
	_add_patch_quad(st,
		[Vector3(gx_min, gy, gz_min), Vector3(gx_max, gy, gz_min),
		 Vector3(gx_max, gy, gz_max), Vector3(gx_min, gy, gz_max)],
		uvs_top, Vector3.UP, layer_top)

	if _grass_patch_shader == null:
		_grass_patch_shader = load(_GRASS_PATCH_SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = _grass_patch_shader
	mat.set_shader_parameter("patch_atlas", atlas)
	# Bajo a propósito: el alfa se promedia en cada mip, así que un umbral alto se come
	# las briznas finas de lejos y deja solo la base maciza.
	mat.set_shader_parameter("alpha_scissor_threshold", float(cfg.get("alpha_scissor", 0.25)))
	# Registrar para recibir el push de sol (light_direction/planet_position) cada
	# frame; sin viento (a esta distancia el balanceo es subpíxel).
	_planet.item_transparent_materials.append({"shader": mat, "wind_speed": 0.0})

	st.set_material(mat)
	return st.commit()


## Como _add_impostor_quad pero marcando la capa del atlas en el color del vértice.
func _add_patch_quad(st: SurfaceTool, corners: Array, uvs: Array, normal: Vector3, layer: Color) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(layer)
		st.set_normal(normal)
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])
