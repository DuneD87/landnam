class_name SkinnedModel
extends Node3D

## Un animal con esqueleto de un pack (FaunaModelData) para la fauna ambiental: lo monta (escena,
## material, escala, giro y clips) y avanza sus clips a mano: cerca de la cámara, cada fotograma;
## lejos o fuera de cámara, uno de cada pocos (con el tiempo acumulado), que el esqueleto es lo que
## cuesta. Qué clip suena lo deciden SkinnedFaunaModel (por la marcha) y SkinnedBirdModel (por el
## vuelo).

## Cada cuánto se vuelve a mirar lo lejos que está la cámara (s), y de cada cuántos fotogramas se
## anima según la distancia (m) y fuera de cámara.
const DETAIL_CHECK := 0.5
const STRIDES := [[12.0, 1], [30.0, 2], [60.0, 3]]
const FAR_STRIDE := 4
const HIDDEN_STRIDE := 8

var data: FaunaModelData
## El clip que suena (las pruebas lo miran).
var current_clip: StringName = &""
var player: AnimationPlayer
var skeleton: Skeleton3D
## Dónde cuenta su coste en DebugStats.
var cost_label: StringName = &"fauna:skinned/anim"

var _skin: Node3D
var _rng := RandomNumberGenerator.new()
var _accum: float = 0.0
var _frame: int = 0
var _stride: int = 1
var _detail_timer: float = 0.0


## Monta el modelo de [model] (si es otro que el que tiene) y lo deja en su idle_clip, a una fase
## al azar.
func set_data(model: FaunaModelData, seed_value: int = 0) -> void:
	_rng.seed = seed_value
	if model != data:
		data = model
		if _skin != null:
			_skin.queue_free()
		_skin = model.scene.instantiate() as Node3D
		add_child(_skin)
		for node in _skin.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if not model.surface_materials.is_empty():
				for i in mini(model.surface_materials.size(), mesh_instance.mesh.get_surface_count()):
					mesh_instance.set_surface_override_material(i, model.surface_materials[i])
			elif model.material != null:
				mesh_instance.material_override = model.material
		skeleton = _skin.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		player = _skin.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for library in player.get_animation_library_list():
			player.remove_animation_library(library)
		player.add_animation_library(&"", model.animations)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skin.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(model.yaw)).scaled(Vector3.ONE * model.scale), Vector3.ZERO)
	_accum = 0.0
	_detail_timer = 0.0
	_stride = 1
	# Repartidos: los que animan uno de cada pocos fotogramas no lo hacen todos en el mismo.
	_frame = _rng.randi() % 8
	current_clip = &""
	_play(model.idle_clip, 0.0, 1.0)
	player.seek(_rng.randf() * player.current_animation_length, true)


func _process(delta: float) -> void:
	if data == null or player == null or not is_visible_in_tree():
		return
	_detail_timer -= delta
	if _detail_timer <= 0.0:
		_detail_timer = DETAIL_CHECK * _rng.randf_range(0.8, 1.2)
		_stride = _stride_for_camera()
	_accum += delta
	_frame += 1
	if _frame % _stride == 0:
		var start := Time.get_ticks_usec()
		player.advance(_accum)
		_accum = 0.0
		DebugStats.report_cost(cost_label, Time.get_ticks_usec() - start)


func _stride_for_camera() -> int:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return 1
	if not camera.is_position_in_frustum(global_position):
		return HIDDEN_STRIDE
	var distance := camera.global_position.distance_to(global_position)
	for step in STRIDES:
		if distance < step[0]:
			return step[1]
	return FAR_STRIDE


func _clip_done() -> bool:
	return player.current_animation == &"" \
		or player.current_animation_position >= player.current_animation_length - 0.05


## Pone [clip] (si no es ya el que suena) fundiéndolo en [blend] s, a ritmo [rate]. Uno sin bucle
## que ya ha acabado no vuelve a empezar: se queda en su último fotograma.
func _play(clip: StringName, blend: float, rate: float) -> void:
	player.speed_scale = rate
	if clip == current_clip and (player.is_playing() \
			or player.get_animation(clip).loop_mode == Animation.LOOP_NONE):
		return
	current_clip = clip
	player.play(clip, blend)
