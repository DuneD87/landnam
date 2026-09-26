class_name TreeOctaImpostor
extends RefCounted

## Impostores octaédricos de los árboles Branching.
##
## El horneado (bake) fotografía el LOD0 desde FRAMES×FRAMES direcciones del hemisferio
## superior en dos atlas: color con cobertura, y normal de copa (octaédrica, RG) con la
## oclusión (B). Lo lanza tools/vegetation/bake_tree_impostors.gd y los atlas se guardan
## junto a las texturas de árbol: hornear 64 vistas en cada arranque tardaría segundos.
## En juego, build_mesh() crea el quad y el material de tree_octa_impostor.gdshader.
## La codificación es la de shaders/lib/octahedral.gdshaderinc.

const FRAMES := 8
const FRAME_PX := 192
const BAKE_SUPERSAMPLE := 2
const ATLAS_DIR := "res://textures/planet/vegetation/tree/impostors/"
const IMPOSTOR_SHADER := preload("res://shaders/vegetation/tree_octa_impostor.gdshader")
const BAKE_SHADER := preload("res://shaders/vegetation/tree_impostor_bake.gdshader")
## Parámetros del follaje que el impostor copia para que el tinte y la luz casen.
const SHARED_FOLIAGE_PARAMETERS := ["tint_variation", "variation_cool_tint", "variation_warm_tint",
	"diffuse_wrap", "transmission_strength", "transmission_sharpness", "transmission_color",
	"transmission_through_shadow",
	"ao_strength", "direct_occlusion"]


static func atlas_paths(scene_name: String) -> Array[String]:
	return [ATLAS_DIR + scene_name + "_albedo.png", ATLAS_DIR + scene_name + "_normal.png"]


static func has_atlases(scene_name: String) -> bool:
	for path in atlas_paths(scene_name):
		if not ResourceLoader.exists(path):
			return false
	return true


## Centro y radio de la esfera que envuelve la malla: cada vista la encuadra entera. El
## radio sale de los vértices y no de la diagonal del AABB, que dejaba el árbol en la mitad
## de cada vista. Horneado y juego deben usar exactamente esta función.
static func bounds(mesh: Mesh) -> Dictionary:
	var center := mesh.get_aabb().get_center()
	var radius_sq := 0.0
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			radius_sq = maxf(radius_sq, center.distance_squared_to(v))
	return {"center": center, "radius": sqrt(radius_sq) * 1.02}


static func hemi_oct_decode(uv: Vector2) -> Vector3:
	var e := uv * 2.0 - Vector2.ONE
	var d := Vector3((e.x + e.y) * 0.5, 0.0, (e.x - e.y) * 0.5)
	d.y = 1.0 - absf(d.x) - absf(d.z)
	return d.normalized()


## Base de la vista: cámara mirando hacia -d, x a la derecha, y arriba en la imagen.
static func frame_basis(d: Vector3) -> Basis:
	var ref := Vector3(0, 0, -1) if absf(d.y) > 0.999 else Vector3.UP
	var right := ref.cross(d).normalized()
	var up := d.cross(right)
	return Basis(right, up, d)


static func build_mesh(lod0: Mesh, scene_name: String, foliage_material: ShaderMaterial) -> ArrayMesh:
	var paths := atlas_paths(scene_name)
	var b := bounds(lod0)
	var material := ShaderMaterial.new()
	material.shader = IMPOSTOR_SHADER
	material.set_shader_parameter("albedo_atlas", load(paths[0]))
	material.set_shader_parameter("normal_atlas", load(paths[1]))
	material.set_shader_parameter("frames", FRAMES)
	material.set_shader_parameter("center", b.center)
	material.set_shader_parameter("radius", b.radius)
	if foliage_material != null:
		for key in SHARED_FOLIAGE_PARAMETERS:
			var value = foliage_material.get_shader_parameter(key)
			if value != null:
				material.set_shader_parameter(key, value)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# El vertex shader coloca las esquinas; aquí solo cuentan las UV.
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		st.set_uv(uv)
		st.set_normal(Vector3.UP)
		st.add_vertex(b.center)
	st.set_material(material)
	var mesh := st.commit()
	# El quad se mueve en el vertex shader: el AABB debe cubrir la esfera entera.
	var r: float = b.radius * 1.5
	mesh.custom_aabb = AABB(b.center - Vector3.ONE * r, Vector3.ONE * r * 2.0)
	return mesh


## Hornea los dos atlas de `mesh` (LOD0 con sus materiales de juego). `host` debe estar en
## el árbol de escena. Devuelve {"albedo": Image, "normal": Image}.
static func bake(mesh: Mesh, host: Node) -> Dictionary:
	var b := bounds(mesh)
	var center: Vector3 = b.center
	var radius: float = b.radius
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	world.environment = env
	var bake_materials := _bake_materials(mesh)

	var px := FRAME_PX * BAKE_SUPERSAMPLE
	var viewports: Array[SubViewport] = []
	var root := Node3D.new()
	for j in FRAMES:
		for i in FRAMES:
			var vp := SubViewport.new()
			vp.size = Vector2i(px, px)
			vp.transparent_bg = true
			vp.world_3d = world
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = radius * 2.0
			cam.near = 0.05
			cam.far = radius * 6.0
			var d := hemi_oct_decode(Vector2(i, j) / float(FRAMES - 1))
			cam.transform = Transform3D(frame_basis(d), center + d * radius * 3.0)
			vp.add_child(cam)
			host.add_child(vp)
			viewports.append(vp)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	root.add_child(inst)
	viewports[0].add_child(root)

	var result := {}
	for mode in 2:
		for s in mesh.get_surface_count():
			var material: ShaderMaterial = bake_materials[s]
			material.set_shader_parameter("mode", mode)
			inst.set_surface_override_material(s, material)
		for vp in viewports:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var atlas := Image.create(FRAMES * FRAME_PX, FRAMES * FRAME_PX, false, Image.FORMAT_RGBA8)
		for k in viewports.size():
			var img := viewports[k].get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.fix_alpha_edges()
			img.resize(FRAME_PX, FRAME_PX, Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(img, Rect2i(0, 0, FRAME_PX, FRAME_PX),
				Vector2i((k % FRAMES) * FRAME_PX, (k / FRAMES) * FRAME_PX))
		result["albedo" if mode == 0 else "normal"] = atlas
	for vp in viewports:
		vp.queue_free()
	return result


static func _bake_materials(mesh: Mesh) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for s in mesh.get_surface_count():
		var source = mesh.surface_get_material(s)
		var bake := ShaderMaterial.new()
		bake.shader = BAKE_SHADER
		if source is ShaderMaterial:
			var src: ShaderMaterial = source
			var foliage: bool = src.shader.resource_path.ends_with("tree_foliage.gdshader")
			bake.set_shader_parameter("is_foliage", foliage)
			bake.set_shader_parameter("texture_albedo", src.get_shader_parameter("texture_albedo"))
			var tint = src.get_shader_parameter("albedo_tint" if foliage else "albedo")
			if tint != null:
				bake.set_shader_parameter("albedo_tint", tint)
			for key in ["saturation", "alpha_scissor_threshold"]:
				var value = src.get_shader_parameter(key)
				if value != null:
					bake.set_shader_parameter(key, value)
		materials.append(bake)
	return materials
