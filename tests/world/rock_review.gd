extends Node

## Las rocas del planeta (scenes/planet/planet_items/rocks/) a su escala de juego sobre un suelo con
## la pradera y la roca de ladera del terreno, calibradas como en planet_earth.json: para ver la
## forma y si el color casa con el suelo.
##   godot --path . res://tests/world/rock_review.tscn [-- --capture=<carpeta>] [-- --old=<carpeta>]
## Con --capture saca unas fotos y se cierra. Con --old pone detrás, para comparar, las escenas de esa
## carpeta (las de antes, sacadas de git) con el mismo nombre.

const SIZE := Vector2i(1600, 900)
const PLANET := Vector3(0.0, -6000.0, 0.0)
const ROCKS := "res://scenes/planet/planet_items/rocks/"
## Escena, escala (la media del generador del JSON) y sitio.
const LAYOUT := [
	["rock_04", 5.0, Vector3(-16, 0, 0)], ["rock_05", 5.0, Vector3(-7, 0, 0)],
	["rock_06", 5.0, Vector3(2, 0, 0)], ["rock_07", 5.0, Vector3(10, 0, 0)],
	["outcrop_flint_01", 2.0, Vector3(-12, 0, 9)], ["outcrop_flint_02", 2.0, Vector3(-8, 0, 9)],
	["outcrop_copper_01", 2.0, Vector3(-3, 0, 9)], ["outcrop_copper_02", 2.0, Vector3(1, 0, 9)],
	["outcrop_obsidian_01", 2.2, Vector3(6, 0, 9)], ["outcrop_obsidian_02", 2.2, Vector3(10, 0, 9)],
	["ice_block_01", 4.0, Vector3(16, 0, 9)],
]
const GROUND_SHADER := """
shader_type spatial;
#include "res://shaders/lib/planet_lighting.gdshaderinc"
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_gain = 1.4;
uniform float rock_gain = 0.55;
uniform vec3 rock_tint = vec3(1.05, 1.0, 0.92);
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_position_global = world;
	planet_normal = normalize(world - planet_position);
}
void fragment() {
	vec2 uv = world.xz * 0.5;
	vec3 g = texture(grass, uv).rgb * grass_gain;
	vec3 r = texture(rock, uv).rgb * rock_gain * rock_tint;
	// Franja de roca de ladera, para comparar con las rocas.
	float strip = smoothstep(-21.0, -20.5, world.z) * (1.0 - smoothstep(-15.5, -15.0, world.z));
	ALBEDO = mix(g, r, strip);
	ROUGHNESS = 0.95;
}
void light() {
	vec3 up_view = normalize((VIEW_MATRIX * vec4(planet_normal, 0.0)).xyz);
	vec3 d, s;
	compute_planet_light(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, ALBEDO, METALLIC, ROUGHNESS,
		0.0, up_view, LIGHT_IS_DIRECTIONAL, 0.0, d, s);
	DIFFUSE_LIGHT += d;
}
"""

var _viewport: SubViewport
var _camera: Camera3D
var _sun: DirectionalLight3D


func _ready() -> void:
	var capture := ""
	var old := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.substr(10)
		elif arg.begins_with("--old="):
			old = arg.substr(6)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(view)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	# Como el Environment del juego (scenes/maps/sun.tscn): ambiente del cielo, sin reflejos (con
	# ellos el disco del sol del cielo procedural quema todo lo que tiene especular) y ACES.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	_viewport.add_child(env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38, 35, 0)
	_sun.light_energy = 1.1
	_sun.light_color = Color(1.0, 0.96, 0.9)
	_sun.shadow_enabled = true
	_sun.shadow_opacity = 0.85
	_sun.directional_shadow_max_distance = 120.0
	_viewport.add_child(_sun)
	_viewport.add_child(_ground())

	var materials: Array[ShaderMaterial] = []
	for entry in LAYOUT:
		_place(ROCKS + entry[0] + ".tscn", entry[1], entry[2], materials)
		if old != "":
			_place(old.path_join(entry[0] + ".tscn"), entry[1], entry[2] + Vector3(0, 0, -6), materials)
	# Piedras sueltas: un puñado, a la escala del generador (1-3).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var at := Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(15.0, 21.0))
		_place(ROCKS + "small_rock_01.tscn", rng.randf_range(1.0, 3.0), at, materials, rng.randf() * TAU)
		if old != "":
			_place(old.path_join("small_rock_01.tscn"), rng.randf_range(1.0, 3.0), at + Vector3(14, 0, 0),
				materials, rng.randf() * TAU)
	# Con el centro del planeta justo debajo, esto es el polo: sin apagar la nieve del clima, todas
	# las rocas salen nevadas.
	for mat in materials:
		mat.set_shader_parameter(&"planet_position", PLANET)
		mat.set_shader_parameter(&"climate_snow_amount", 0.0)

	_camera = Camera3D.new()
	_camera.fov = 55.0
	_viewport.add_child(_camera)
	_camera.look_at_from_position(Vector3(-2, 9, 30), Vector3(-2, 1, 4))
	if capture == "":
		return
	DirAccess.make_dir_recursive_absolute(capture)
	var views := [
		["overview", Vector3(-2, 9, 30), Vector3(-2, 1, 4)],
		["big", Vector3(-3, 4.5, 14), Vector3(-3, 1.5, 0)],
		["big_low", Vector3(5, 1.6, 9), Vector3(-6, 1.8, -1)],
		["outcrops", Vector3(2, 3.2, 17), Vector3(2, 0.6, 9)],
		["pebbles", Vector3(0, 1.6, 24), Vector3(0, 0, 18)],
		["pebbles_close", Vector3(-1, 0.8, 19.5), Vector3(-1, 0.05, 17.5)],
	]
	if old != "":
		views.append(["old_vs_new", Vector3(-3, 5, 18), Vector3(-3, 1.2, -3)])
		views.append(["old_pebbles", Vector3(14, 1.6, 24), Vector3(14, 0, 18)])
	for sun in [["noon", Vector3(-55, 35, 0)], ["low", Vector3(-14, 120, 0)]]:
		_sun.rotation_degrees = sun[1]
		for v in views:
			_camera.look_at_from_position(v[1], v[2])
			for k in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_viewport.get_texture().get_image().save_png(capture.path_join("rocks_%s_%s.png" % [v[0], sun[0]]))
	get_tree().quit()


## La malla de la roca de la escena [path], a escala [scale] y girada [yaw], plantada en [at].
func _place(path: String, scale: float, at: Vector3, materials: Array[ShaderMaterial], yaw := 0.6) -> void:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("No está: %s" % path)
		return
	var root: Node = (load(path) as PackedScene).instantiate()
	var source := root.get_child(0)
	var mesh: Mesh = null
	var material: Material = null
	if source is ProceduralRock:
		mesh = (source as ProceduralRock).get_rock_instance().mesh
		material = (source as ProceduralRock).material_rock
	elif source.has_method("get_rock_instance"):
		# Rock3D del addon (las escenas de antes): esfera centrada en el origen, media enterrada.
		mesh = (source.get_rock_instance() as MeshInstance3D).mesh
		material = source.get("material_rock")
	root.free()
	if mesh == null:
		return
	var instance := RockFracture.mesh_instance(mesh)
	instance.material_override = material
	instance.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), at)
	_viewport.add_child(instance)
	if material is ShaderMaterial and not materials.has(material):
		materials.append(material)


func _ground() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"grass", load("res://textures/terrain/whispy-grass-meadow-bl/wispy-grass-meadow_albedo.png"))
	mat.set_shader_parameter(&"rock", load("res://textures/terrain/bumpy-worn-ground-bl/bumpy_worn_ground_albedo.png"))
	mat.set_shader_parameter(&"planet_position", PLANET)
	mi.material_override = mat
	return mi
