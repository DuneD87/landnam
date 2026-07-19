## Hornea el atlas de billboards de árboles para PlanetForest (un slot por
## especie, SubViewport ortográfico) y construye la malla de cruz unitaria.
class_name TreeImpostorBaker extends RefCounted

const SLOT_SIZE := 512
const ATLAS_GRID := 4
const BAKE_SHADER := preload("res://shaders/impostor_bake.gdshader")


## Quad unitario [-0.5, 0.5] en el plano XY, pivote en el centro. El shader del
## impostor lo orienta hacia la cámara (billboard cilíndrico alrededor del up).
static func build_billboard_quad_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0), Vector3(0.5, 0.5, 0.0), Vector3(-0.5, 0.5, 0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
	])
	var normals := PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Renderiza cada especie a su slot (vista lateral + cenital en slot+8, para el
## blend por elevación del shader) y devuelve el atlas con mipmaps corregidos.
static func bake_atlas(host: Node, types: Array) -> ImageTexture:
	var half_slots := ATLAS_GRID * ATLAS_GRID / 2
	var atlas := Image.create(SLOT_SIZE * ATLAS_GRID, SLOT_SIZE * ATLAS_GRID, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.15, 0.25, 0.1, 0.0)) # slots vacíos: verde neutro, no negro
	for i in types.size():
		if i >= half_slots:
			push_warning("TreeImpostorBaker: más especies (%d) que slots con cenital (%d)" % [types.size(), half_slots])
			break
		var img: Image = await _bake_single_image(host, types[i])
		if img == null:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		_bleed_background(img)
		types[i].bb_fit = _content_fit(img)
		var dst := Vector2i((i % ATLAS_GRID) * SLOT_SIZE, (i / ATLAS_GRID) * SLOT_SIZE)
		atlas.blit_rect(img, Rect2i(0, 0, SLOT_SIZE, SLOT_SIZE), dst)
		var top: Image = await _bake_single_image(host, types[i], true)
		if top == null:
			continue
		if top.get_format() != Image.FORMAT_RGBA8:
			top.convert(Image.FORMAT_RGBA8)
		_bleed_background(top)
		var tf := _content_fit(top)
		types[i].bb_fit_top = maxf(tf.x, tf.y)
		var j := i + half_slots
		var dst_top := Vector2i((j % ATLAS_GRID) * SLOT_SIZE, (j / ATLAS_GRID) * SLOT_SIZE)
		atlas.blit_rect(top, Rect2i(0, 0, SLOT_SIZE, SLOT_SIZE), dst_top)
	atlas.generate_mipmaps()
	return ImageTexture.create_from_image(atlas)


## Rellena los texels transparentes con el color medio del follaje. El viewport
## hornea sobre negro transparente y los mips profundos promedian esas zonas:
## sin este relleno los billboards se oscurecen con la distancia (el alpha sigue
## definiendo la silueta; solo cambia el color que arrastran los mips).
static func _bleed_background(img: Image) -> void:
	var data: PackedByteArray = img.get_data()
	var size := data.size()
	var sr := 0
	var sg := 0
	var sb := 0
	var n := 0
	for i in range(0, size, 4):
		if data[i + 3] > 128:
			sr += data[i]
			sg += data[i + 1]
			sb += data[i + 2]
			n += 1
	if n == 0:
		return
	var r := sr / n
	var g := sg / n
	var b := sb / n
	for i in range(0, size, 4):
		if data[i + 3] < 32:
			data[i] = r
			data[i + 1] = g
			data[i + 2] = b
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Fracción del slot que ocupa realmente el contenido alrededor del centro,
## por eje [0..1]. El billboard encoge el quad a ese rectángulo: menos texels
## transparentes que rasterizar y descartar (el frame cuadrado de un pino alto
## y estrecho es mayormente vacío).
static func _content_fit(img: Image) -> Vector2:
	var w := img.get_width()
	var h := img.get_height()
	var data: PackedByteArray = img.get_data()
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	var max_dx := 0.0
	var max_dy := 0.0
	for y in h:
		var row := y * w * 4
		for x in w:
			if data[row + x * 4 + 3] > 8:
				max_dx = maxf(max_dx, absf(float(x) + 0.5 - cx))
				max_dy = maxf(max_dy, absf(float(y) + 0.5 - cy))
	if max_dx <= 0.0:
		return Vector2.ONE
	return Vector2(
		clampf((max_dx + 2.0) / cx, 0.05, 1.0),
		clampf((max_dy + 2.0) / cy, 0.05, 1.0))


## Un frame de la especie: lateral por defecto, o cenital (cámara mirando -Y).
static func _bake_single_image(host: Node, type: Dictionary, from_top := false) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(SLOT_SIZE, SLOT_SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var mesh: Mesh = type.mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for s in mesh.get_surface_count():
		mi.set_surface_override_material(s, _build_bake_material(mesh.surface_get_material(s)))
	vp.add_child(mi)

	var frame_size: float = type.frame_size
	var aabb: AABB = mesh.get_aabb()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = frame_size
	cam.near = 0.05
	cam.far = frame_size * 4.0
	if from_top:
		cam.position = aabb.get_center() + Vector3(0.0, frame_size * 1.5, 0.0)
		cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		cam.position = aabb.get_center() + Vector3(0.0, 0.0, frame_size * 1.5)
	vp.add_child(cam)
	cam.current = true

	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


static func _build_bake_material(src: Material) -> Material:
	if src is ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = BAKE_SHADER
		var tex = (src as ShaderMaterial).get_shader_parameter("texture_albedo")
		if tex != null:
			m.set_shader_parameter("texture_albedo", tex)
		# OJO: no copiar el uniform "albedo": transparent_material_shader lo
		# declara pero NO lo usa (ALBEDO = textura sin tinte), y los .tscn lo
		# tienen guardado en NEGRO — copiarlo horneaba todo el follaje negro.
		return m
	if src is BaseMaterial3D:
		var dup: BaseMaterial3D = src.duplicate()
		dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return dup
	var fallback := ShaderMaterial.new()
	fallback.shader = BAKE_SHADER
	return fallback
