extends Node3D

## Lo que se planta en el suelo, asentado con GroundFit en un suelo de prueba (llano, una ladera de
## unos 15° y baches), al atardecer: tres hogueras encendidas y, detrás, tres bancos de trabajo. Para
## ver cómo asientan, la ceniza y el fuego, y el banco con lo que lleva encima.
##   godot --path . res://tests/world/placeables_review.tscn [-- --capture=<carpeta>]
## Con --capture saca unas fotos de cerca y se cierra.

const SIZE := 12.0
const CELLS := 96

var _spots := [Vector3(-3.0, 0, 0), Vector3(0.0, 0, 0), Vector3(3.0, 0, 0)]
## Los bancos, detrás de cada hoguera.
const BENCH_BEHIND := Vector3(0, 0, -2.2)


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-12, 60, 0)
	sun.light_energy = 0.45
	sun.light_color = Color(1.0, 0.75, 0.55)
	sun.shadow_enabled = true
	add_child(sun)
	# "Planeta": el centro muy abajo, para que la vertical sea +Y.
	var planet := Node3D.new()
	planet.position = Vector3(0, -6000, 0)
	add_child(planet)
	add_child(_ground())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for spot: Vector3 in _spots:
		var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 5, spot + Vector3.DOWN * 5, 1)
		var hit := space.intersect_ray(query)
		var fit := GroundFit.fit(space, hit.position, Vector3.UP, Vector3(0, 0, 1), CampfireVisual.RADIUS, 1, exclude)
		print("hoguera en ", spot.x, ": ", "ok" if fit.ok else "NO", " pendiente %.1f° desnivel %.2f m" % [fit.get("tilt", 0.0), fit.get("rough", 0.0)])
		var fire: Campfire = (load("res://scenes/world/campfire.tscn") as PackedScene).instantiate()
		planet.add_child(fire)
		fire.global_transform = fit.transform
		fire.fuel_left = 999.0
		fire.ignite()
	var bench_data: ItemData = ItemCatalog.get_item(&"stone_workbench")
	var ground := bench_data.get_trait(GroundPlaceableTrait) as GroundPlaceableTrait
	for spot: Vector3 in _spots:
		var at: Vector3 = spot + BENCH_BEHIND
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5, at + Vector3.DOWN * 5, 1)
		var hit := space.intersect_ray(query)
		var fit := GroundFit.fit(space, hit.position, Vector3.UP, Vector3(0, 0, 1), ground.radius, 1, exclude,
			ground.max_tilt, ground.settle, ground.max_settle)
		print("banco en ", spot.x, ": ", "ok" if fit.ok else "NO", " pendiente %.1f° desnivel %.2f m" % [fit.get("tilt", 0.0), fit.get("rough", 0.0)])
		var bench: Node3D = (load(ground.scene_path) as PackedScene).instantiate()
		planet.add_child(bench)
		bench.global_transform = fit.transform
	var capture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.substr(10)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 2.4, 6.5), Vector3(0, 0, 0))
	if capture == "":
		return
	var views := [["all", Vector3(0, 2.4, 6.5), Vector3(0, 0.1, 0)]]
	for i in _spots.size():
		var s: Vector3 = _spots[i]
		views.append(["near_%d" % i, s + Vector3(0.5, 0.55, 1.6), s + Vector3(0, 0.12, 0)])
		views.append(["low_%d" % i, s + Vector3(-1.4, 0.18, 0.6), s + Vector3(0, 0.1, 0)])
		var b: Vector3 = s + BENCH_BEHIND
		views.append(["bench_%d" % i, b + Vector3(0.9, 1.3, 2.0), b + Vector3(0, 0.6, 0)])
		views.append(["bench_side_%d" % i, b + Vector3(-2.2, 0.7, 0.4), b + Vector3(0, 0.4, 0)])
	for view in views:
		cam.look_at_from_position(view[1], view[2])
		for k in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture.path_join("placed_%s.png" % view[0]))
	get_tree().quit()


## Suelo de 12 m: llano a la izquierda, ladera en el centro y baches a la derecha.
func _ground() -> StaticBody3D:
	var heights := PackedFloat32Array()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.9
	for j in CELLS + 1:
		for i in CELLS + 1:
			var x := (float(i) / CELLS - 0.5) * SIZE
			var z := (float(j) / CELLS - 0.5) * SIZE
			var h := 0.0
			var slope := smoothstep(-2.0, -1.0, x) * (1.0 - smoothstep(1.0, 2.0, x))
			h += slope * z * -0.27
			var bumps := smoothstep(1.6, 2.4, x)
			h += bumps * noise.get_noise_2d(x, z) * 0.22
			heights.append(h)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in CELLS:
		for i in CELLS:
			var quad := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var c: Vector2i = quad[idx]
				var x := (float(c.x) / CELLS - 0.5) * SIZE
				var z := (float(c.y) / CELLS - 0.5) * SIZE
				st.set_uv(Vector2(x, z) * 0.5)
				st.add_vertex(Vector3(x, heights[c.y * (CELLS + 1) + c.x], z))
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	var tex := NoiseTexture2D.new()
	tex.noise = FastNoiseLite.new()
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.26, 0.12))
	ramp.set_color(1, Color(0.36, 0.42, 0.22))
	tex.color_ramp = ramp
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(2, 2, 2)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	body.add_child(mi)
	return body
