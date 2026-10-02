extends Node3D

## Banco de pruebas de los árboles con el VoxelInstancer real y los items del planeta.
##
##   godot --path . res://tests/vegetation/tree_quality_preview.tscn -- --capture --tag=before
##   ... -- --lineup --tag=before      retratos por especie y hojas de LOD0..LOD3
##   ... -- --perf                     coste de GPU de los árboles (con/sin instancer)
##   ... -- --relay --tag=x            relevo LOD2/impostor: pares a 110 m y recorrido
##
## El bosque sale de los generadores del bosque verde y de los bosquetes de frutales
## (FOREST_GENERATORS) sobre un terreno plano, sin la
## máscara de bioma, con la hierba del planeta alrededor (salvo en --perf, que carga solo
## árboles para que ocultar el instancer reste exactamente su coste). Las palmeras solo
## entran en --lineup: su generador es el de arena.
## Capturas en build/tree_quality/<tag>_<vista>.png.
## Sin argumentos: WASD para moverse, Q/E bajar/subir, Shift acelerar, Escape salir.

const GrassPreview = preload("res://tests/vegetation/grass_lod_preview.gd")
const OUT_DIR := "res://build/tree_quality"
const FOREST_GENERATORS := ["tree_generator_green", "tree_generator_almond_grove", "tree_generator_apple_grove"]
const PERF_FRAMES := 200
const PORTRAIT_SIZE := Vector2i(720, 1080)

var _planet: Planet
var _terrain: VoxelLodTerrain
var _camera: Camera3D
var _light: DirectionalLight3D
var _environment: Environment
var _sun := Vector3(0.4, 0.8, 0.3).normalized()
var _tag := "after"
var _mode := ""
## Por especie (escena): {"name", "ids": [library ids], "scale": escala media del generador}
var _species: Array[Dictionary] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg in ["--capture", "--lineup", "--perf", "--relay"]:
			_mode = arg.substr(2)
	if _mode == "perf":
		get_window().size = Vector2i(2560, 1440)
	else:
		get_window().size = Vector2i(1920, 1080)
	var world := WorldEnvironment.new()
	var field = GrassPreview.new()
	_environment = field._build_environment()
	field.free()
	world.environment = _environment
	add_child(world)
	_light = DirectionalLight3D.new()
	add_child(_light)
	_light.shadow_enabled = true
	_light.shadow_normal_bias = 2.627
	_light.shadow_opacity = 0.85
	_light.directional_shadow_split_1 = 0.02
	_light.directional_shadow_split_2 = 0.07
	_light.directional_shadow_blend_splits = true
	_light.directional_shadow_fade_start = 0.761
	_light.directional_shadow_max_distance = 1500.0
	_terrain = VoxelLodTerrain.new()
	_terrain.name = "TreeTestTerrain"
	_terrain.position.y = -30000.0
	_terrain.lod_count = 5
	_terrain.secondary_lod_distance = 32.0
	_terrain.view_distance = 1024
	_terrain.streaming_system = 1
	_terrain.generate_collisions = false
	var generator := VoxelGeneratorFlat.new()
	generator.height = 30000.0
	_terrain.generator = generator
	_terrain.mesher = VoxelMesherTransvoxel.new()
	_terrain.material = GrassPreview.meadow_ground_material()
	_planet = Planet.new(_terrain)
	_planet.radius = 30000.0
	_planet.planet_position = _terrain.position
	_planet.wind_direction = Vector3(1, 0, 0.3).normalized()
	_set_sun(_sun)
	# El impostor del LOD3 se hornea con el instancer ya en el árbol de escena.
	add_child(_terrain)
	await _load_items()
	_camera = Camera3D.new()
	_camera.far = 3000.0
	add_child(_camera)
	_camera.position = Vector3(0, 1.7, 0)
	_camera.look_at(Vector3(0, 1.7, -100))
	_camera.current = true
	var viewer := VoxelViewer.new()
	viewer.view_distance = 1024
	viewer.requires_collisions = false
	_camera.add_child(viewer)
	_planet._update_planet()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	match _mode:
		"capture":
			await _capture_forest()
		"lineup":
			await _capture_lineup()
		"perf":
			await _measure_perf()
		"relay":
			await _capture_relay()
		_:
			return
	print("TREE QUALITY PREVIEW COMPLETE")
	get_tree().quit()


func _load_items() -> void:
	var config := JSON.new()
	config.parse(FileAccess.get_file_as_string("res://data/planet/planet_earth.json"))
	var vegetation: Dictionary = config.data.vegetation_settings
	var seen := {}
	var item_index := 0
	for item in vegetation.items:
		var scene: String = item.scene
		var is_tree := scene.contains("/vegetation/trees/")
		var gens: Array = item.generator if item.generator is Array else [item.generator]
		var loaded: Dictionary = item.duplicate(true)
		if is_tree:
			if seen.has(scene):
				continue
			seen[scene] = true
			var forest: Array = gens.filter(func(gen) -> bool: return gen in FOREST_GENERATORS)
			if not forest.is_empty():
				loaded.generator = [forest[0]]
			elif _mode != "lineup":
				continue
		elif _mode == "perf" or _mode == "lineup" or not item.has("grass_lods"):
			continue
		var first_id: int = _planet._next_library_id
		await _planet._load_vegetation_item(item_index, loaded, vegetation.generators, [])
		item_index += 1
		if is_tree:
			var ids: Array = range(first_id, _planet._next_library_id)
			var gen: VoxelInstanceGenerator = _planet.voxel_instancer.library.get_item(ids[0]).generator
			_species.append({
				"name": scene.get_file().get_basename(),
				"ids": ids,
				"scale": (gen.min_scale + gen.max_scale) * 0.5,
			})


func _set_sun(direction: Vector3) -> void:
	_sun = direction.normalized()
	_light.look_at_from_position(Vector3.ZERO, -_sun, Vector3.UP if absf(_sun.y) < 0.99 else Vector3.FORWARD)
	_planet.sun_dir = _sun
	RenderingServer.global_shader_parameter_set("sky_sun_direction", _sun)
	if _planet != null:
		_planet._update_planet()


func _process(delta: float) -> void:
	if _planet != null:
		_planet._update_planet()
	if _camera == null or _mode != "":
		return
	var direction := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	_camera.position += _camera.basis * direction * delta * (35.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0)
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().quit()


# --- Bosque ---------------------------------------------------------------------------

## Vistas del bosque: [nombre, posición, punto al que mira, dirección del sol].
func _forest_views() -> Array:
	var noon := Vector3(0.4, 0.8, 0.3)
	return [
		["ground", Vector3(0, 1.7, 0), Vector3(0, 3.0, -100), noon],
		["ground_side", Vector3(0, 1.7, 0), Vector3(100, 4.0, -30), noon],
		["elevated", Vector3(0, 25.0, 40), Vector3(0, 0.0, -120), noon],
		["high", Vector3(0, 90.0, 120), Vector3(0, 0.0, -400), noon],
		["golden", Vector3(0, 1.7, 0), Vector3(-100, 5.0, -40), Vector3(-0.2, 0.12, -1.0)],
		["backlit", Vector3(0, 1.7, 0), Vector3(0, 8.0, -100), Vector3(0.1, 0.22, -1.0)],
	]


func _capture_forest() -> void:
	await _wait(10.0)
	for view in _forest_views():
		_set_sun(view[3])
		_camera.position = view[1]
		_camera.look_at(view[2])
		await _wait(2.0)
		await _save_main(view[0])


func _measure_perf() -> void:
	await _wait(10.0)
	var counts: Dictionary = _planet.voxel_instancer.debug_get_instance_counts()
	var total := 0
	for id in counts:
		total += int(counts[id])
	print("PERF instances=%d" % total)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for view in _forest_views():
		if view[0] in ["golden", "backlit", "ground_side"]:
			continue
		_set_sun(view[3])
		_camera.position = view[1]
		_camera.look_at(view[2])
		_set_forest_visible(true)
		await _wait(2.0)
		var with_trees := await _gpu_median(rid)
		var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		_set_forest_visible(false)
		await _wait(0.5)
		var without := await _gpu_median(rid)
		var prims_off := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		print("PERF %s trees_ms=%.3f frame_ms=%.3f prims=%d draws=%d" % [
			view[0], with_trees - without, with_trees, prims - prims_off, draws])
	_set_forest_visible(true)


func _gpu_median(rid: RID) -> float:
	for i in 10:
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	for i in PERF_FRAMES:
		await RenderingServer.frame_post_draw
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	samples.sort()
	return samples[samples.size() / 2]


# --- Relevo geometría / impostor --------------------------------------------------------

## Comprueba el relevo LOD2/impostor: (1) cada especie en LOD2 y como impostor, lado a lado
## a 110 m con teleobjetivo (mismo aspecto); (2) la cámara retrocede a pasos desde 30 m
## mirando copas a ~90-130 m (no deben aparecer ni desaparecer árboles).
func _capture_relay() -> void:
	await _wait(10.0)
	_set_sun(Vector3(0.4, 0.8, 0.3))
	var shots: Array[Image] = []
	for step in 8:
		_camera.position = Vector3(0, 30.0, 20.0 + step * 4.0)
		_camera.look_at(Vector3(0, 0.0, -80.0))
		await _wait(0.6)
		await RenderingServer.frame_post_draw
		shots.append(get_viewport().get_texture().get_image().get_region(Rect2i(480, 300, 960, 400)))
	_save_strip(shots, "relay_walk")

	_set_forest_visible(false)
	_camera.fov = 12.0
	_camera.position = Vector3(0, 3.0, 110.0)
	_camera.look_at(Vector3(0, 3.0, 0))
	var holder := Node3D.new()
	add_child(holder)
	var pairs: Array[Image] = []
	for sp in _species:
		if _planet.tree_detail_renderer == null or _planet.tree_detail_renderer.lod_meshes(sp.ids[0]).is_empty():
			continue
		for child in holder.get_children():
			child.free()
		for side in 2:
			var inst := MeshInstance3D.new()
			inst.mesh = _without_band_fade(_species_lod(sp, 2 if side == 0 else 3))
			inst.scale = Vector3.ONE * sp.scale
			inst.position = Vector3(-6.0 if side == 0 else 6.0, 0, 0)
			holder.add_child(inst)
		await _wait(0.5)
		await RenderingServer.frame_post_draw
		pairs.append(get_viewport().get_texture().get_image().get_region(Rect2i(360, 140, 1200, 800)))
	_save_sheet(pairs, 3, "relay_pairs")


func _save_strip(shots: Array[Image], name: String) -> void:
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var sheet := Image.create(w * 2, h * ceili(shots.size() / 2.0), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var img := shots[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, name]
	sheet.save_png(path)
	print("CAPTURE ", path)


# --- Retratos y LODs ------------------------------------------------------------------

## Cada especie a su escala media en el planeta, junto a una figura de 1,8 m, en una hoja
## de retratos; y sus cuatro LODs lado a lado en hojas de cuatro especies.
func _capture_lineup() -> void:
	_set_forest_visible(false)
	var vp := SubViewport.new()
	vp.size = PORTRAIT_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.far = 3000.0
	vp.add_child(cam)
	cam.current = true
	var holder := Node3D.new()
	add_child(holder)
	var human := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	human.mesh = capsule
	var human_mat := StandardMaterial3D.new()
	human_mat.albedo_color = Color(0.75, 0.3, 0.25)
	human.material_override = human_mat
	await _wait(6.0)

	var lights := {"noon": Vector3(0.4, 0.8, 0.3), "backlit": Vector3(0.15, 0.25, -1.0)}
	for light_name in lights:
		_set_sun(lights[light_name])
		var shots: Array[Image] = []
		for sp in _species:
			var mesh: Mesh = _species_lod(sp, 0)
			_place_tree(holder, mesh, sp.scale, 0.0)
			holder.add_child(human)
			var size: Vector3 = mesh.get_aabb().size * sp.scale
			human.position = Vector3(maxf(size.x, size.z) * 0.5 + 1.0, 0.9, 0.0)
			_frame(cam, mesh.get_aabb(), sp.scale, human.position.x)
			shots.append(await _grab(vp))
			holder.remove_child(human)
		_save_sheet(shots, 6, "portraits_%s" % light_name)

	_set_sun(lights.noon)
	var per_sheet := 4
	for sheet in ceili(_species.size() / float(per_sheet)):
		var shots: Array[Image] = []
		for k in per_sheet:
			var index := sheet * per_sheet + k
			if index >= _species.size():
				break
			var sp: Dictionary = _species[index]
			for lod in 4:
				var mesh: Mesh = _without_band_fade(_species_lod(sp, lod))
				_place_tree(holder, mesh, sp.scale, 0.0)
				_frame(cam, _species_lod(sp, 0).get_aabb(), sp.scale, 0.0)
				shots.append(await _grab(vp))
		_save_sheet(shots, 4, "lods_%d" % sheet)
	human.free()


## Instancer (impostores, hierba) y geometría cercana de los árboles.
func _set_forest_visible(visible: bool) -> void:
	_planet.voxel_instancer.visible = visible
	if _planet.tree_detail_renderer != null:
		_planet.tree_detail_renderer.visible = visible


## LOD0-2 del detalle cercano o, con lod 3, el impostor del item del instancer. Los árboles
## sin detalle (palmeras) usan las cuatro mallas del item.
func _species_lod(sp: Dictionary, lod: int) -> Mesh:
	var item = _planet.voxel_instancer.library.get_item(sp.ids[0])
	var renderer: TreeDetailRenderer = _planet.tree_detail_renderer
	var detail: Array = renderer.lod_meshes(sp.ids[0]) if renderer != null else []
	if detail.is_empty():
		return item.get_mesh(lod)
	return item.get_mesh(0) if lod == 3 else detail[lod]


## El impostor y los LOD solo aparecen en su tramo de distancia: en el retrato se quita.
func _without_band_fade(mesh: Mesh) -> Mesh:
	var copy: ArrayMesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var material = copy.surface_get_material(s)
		if material is ShaderMaterial:
			var dup: ShaderMaterial = material.duplicate()
			for key in ["fade_in_start", "fade_in_end", "fade_out_start", "fade_out_end"]:
				dup.set_shader_parameter(key, 0.0)
			dup.set_shader_parameter("planet_position", _planet.planet_position)
			dup.set_shader_parameter("light_direction", _sun)
			copy.surface_set_material(s, dup)
	return copy


func _place_tree(holder: Node3D, mesh: Mesh, scale: float, x: float) -> void:
	for child in holder.get_children():
		if child is MeshInstance3D and child.name.begins_with("Tree"):
			child.free()
	var inst := MeshInstance3D.new()
	inst.name = "Tree"
	inst.mesh = mesh
	inst.scale = Vector3.ONE * scale
	inst.position = Vector3(x, 0, 0)
	holder.add_child(inst)


## Encuadra el árbol (y la figura, si extra_x > 0) de lado, un poco por encima del suelo.
func _frame(cam: Camera3D, aabb: AABB, scale: float, extra_x: float) -> void:
	var height := aabb.end.y * scale
	var width := maxf(aabb.size.x, aabb.size.z) * scale + maxf(extra_x, 0.0)
	var half_fov := deg_to_rad(cam.fov * 0.5)
	var aspect := float(PORTRAIT_SIZE.x) / PORTRAIT_SIZE.y
	var dist := maxf(height * 0.58 / tan(half_fov), width * 0.6 / (tan(half_fov) * aspect))
	var target := Vector3(extra_x * 0.25, height * 0.5, 0.0)
	cam.position = target + Vector3(0.0, height * 0.08, dist)
	cam.look_at(target)


func _grab(vp: SubViewport) -> Image:
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func _save_sheet(shots: Array[Image], columns: int, name: String) -> void:
	if shots.is_empty():
		return
	var w := shots[0].get_width() / 2
	var h := shots[0].get_height() / 2
	var rows := ceili(shots.size() / float(columns))
	var sheet := Image.create(w * columns, h * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var img := shots[i]
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % columns) * w, (i / columns) * h))
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, name]
	sheet.save_png(path)
	print("CAPTURE ", path)


# --- Utilidades -----------------------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func _save_main(view: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [OUT_DIR, _tag, view]
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)


func _exit_tree() -> void:
	if is_instance_valid(_planet):
		_planet.free()
