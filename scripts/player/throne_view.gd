class_name ThroneView
extends CanvasLayer

## Sentado en el trono (Throne): E junto a uno sienta al jugador (village/throne_sit, luego
## village/throne_idle en bucle, con su AnimationPlayer y el árbol de animación parado, como al
## dormir) y abre la vista de la base: una cámara ortográfica desde arriba, inclinada (R y F, o arrastrando
## con el botón central, que además la gira), con los
## colonos que viven cerca (Throne.MANAGE_RADIUS) señalados con su nombre, sus zonas de trabajo
## pintadas en el suelo y, a la derecha, la lista para elegirlos (uno o varios) y mandarles trabajo
## (SettlerWork): talar, picar o limpiar una zona que se marca con un círculo (clic; la rueda cambia el
## radio), o dejarlo. Talar y picar también se mandan alrededor de su base (clic derecho). La vista se
## mueve con WASD y se acerca con la rueda. E o Escape lo levantan (sentarse al revés); un golpe
## también. Ver docs/villagers.md.

enum Phase {NONE, SITTING, SEATED, STANDING}

const SIT_ANIM := &"village/throne_sit"
const IDLE_ANIM := &"village/throne_idle"
const HIPS := &"mixamorig_Hips"
## La vista: inclinada VIEW_PITCH rad sobre el horizonte (R y F, o el botón central, entre PITCH, a
## TILT_SPEED rad/s o DRAG rad por píxel), con VIEW_SIZE m de alto en el centro (la rueda, entre ZOOM);
## WASD la mueve PAN_SPEED veces su alto por segundo, hasta PAN_LIMIT m del trono. En perspectiva de
## teleobjetivo (VIEW_FOV°), casi como una isométrica: la ortográfica dejaba el cielo y la atmósfera en
## negro. Por eso la distancia va con lo que se ve; los cuerpos de los árboles y las rocas solo están
## cerca de la cámara (VoxelInstancer.collision_distance, ~200 m), así que alejada del todo el trabajo
## espera (SettlerWork._zone_loaded). Nunca baja de CLEARANCE m sobre el suelo que tiene debajo.
const VIEW_PITCH := 0.95
const PITCH := Vector2(0.45, 1.5)
const TILT_SPEED := 1.2
const DRAG := 0.006
const VIEW_FOV := 35.0
const VIEW_SIZE := 80.0
const ZOOM := Vector2(25.0, 170.0)
const CLEARANCE := 12.0
const PAN_SPEED := 0.6
const PAN_LIMIT := 90.0
## La marca bajo cada colono (se ve a través de los árboles): un aro fino de radio (fracción del alto de la
## vista, al menos 0,8 m); el nombre va encima, desplazado hacia arriba en pantalla LABEL_LIFT px.
const MARKER_RADIUS := 0.014
const LABEL_LIFT := 26.0
## El tamaño de los nombres en pantalla (Label3D.fixed_size, en perspectiva) y, con la vista más alejada
## que NAME_ONLY m de alto, solo el nombre (sin el oficio), que si no se amontonan.
const LABEL_PIXEL := 0.0004
const NAME_ONLY := 110.0
## Las zonas que se marcan (m) y lo que cambia la rueda cada paso.
const ZONE_RADIUS := Vector2(4.0, 60.0)
const ZONE_STEP := 2.0
## Los círculos en el suelo: segmentos, ancho (fracción del alto de la vista) y colores por trabajo.
const RING_SEGMENTS := 72
const RING_WIDTH := 0.006
const JOB_COLORS := {SettlerWork.Job.FELL: Color(0.55, 0.9, 0.35, 0.85),
	SettlerWork.Job.MINE: Color(0.72, 0.8, 0.95, 0.85), SettlerWork.Job.CLEAR: Color(1.0, 0.72, 0.25, 0.9),
	SettlerWork.Job.BUILD: Color(0.95, 0.85, 0.45, 0.85), SettlerWork.Job.GUARD: Color(0.95, 0.3, 0.3, 0.85),
	SettlerWork.Job.HUNT: Color(0.75, 0.5, 0.3, 0.85), SettlerWork.Job.FISH: Color(0.35, 0.9, 0.9, 0.85)}
## Los trabajos que piden marcar una zona sí o sí (los demás valen alrededor de la base, con clic derecho).
const NEEDS_ZONE: Array[SettlerWork.Job] = [SettlerWork.Job.CLEAR, SettlerWork.Job.GUARD]
const SELECTED_COLOR := Color(1.0, 0.88, 0.35)
const LABEL_COLOR := Color(0.95, 0.93, 0.88)
## Se elige un colono pinchando a menos de esto (px) de su nombre.
const PICK_PIXELS := 48.0
const REFRESH := 0.5

var _player: PlayerController
var _throne: Throne
var _phase := Phase.NONE
var _clip_time := 0.0
var _clip_length := 1.0
## El cuerpo del jugador de pie (al empezar) y sentado, en el marco del trono; y cómo estaba.
var _stand_pose := Transform3D.IDENTITY
var _seat_pose := Transform3D.IDENTITY
var _model_transform := Transform3D.IDENTITY
var _tree_was_active := false
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _camera: Camera3D
var _pan := Vector3.ZERO
var _size := VIEW_SIZE
var _pitch := VIEW_PITCH
var _yaw := 0.0
var _dragging := false
var _markers: MeshInstance3D
## Marcando una zona para [_placing] (Job.NONE: no), con su radio y dónde está el ratón (mundo).
var _placing := SettlerWork.Job.NONE
## El turno del guardia que se está marcando (0 de día, 1 de noche).
var _placing_shift := 0
var _zone_radius := 12.0
var _cursor := Vector3.INF
var _cursor_ring: MeshInstance3D
var _zones: MeshInstance3D
var _ring_material: StandardMaterial3D
var _labels := {}
var _selected := {}
var _settlers: Array[Companion] = []
var _refresh_left := 0.0
## El fotograma en que se sentó: la E que lo sienta no lo levanta.
var _sat_frame := -1

var _root: Control
var _panel: PanelContainer
var _margin: MarginContainer
var _box: VBoxContainer
var _list: VBoxContainer
var _rows := {}
var _empty: Label
var _hint: Label
var _orders: Array[Button] = []
var _stop_button: Button
var _follow_button: Button


func _ready() -> void:
	layer = 5
	visible = false
	_build_ui()


func setup(player: PlayerController) -> void:
	_player = player
	_player.health_component.damaged.connect(func(_amount: float, _source: Node) -> void: stand_up())
	_player.health_component.died.connect(_force_close)
	GameManager.state_changed.connect(func(_state: GameManager.State) -> void: _force_close())


## Sentado o sentándose/levantándose: el jugador no se mueve (PlayerController._physics_step).
func is_busy() -> bool:
	return _phase != Phase.NONE


func is_open() -> bool:
	return _phase != Phase.NONE


## E junto a un trono: se sienta. Falso si no hay ninguno al alcance.
func try_open() -> bool:
	var throne := Throne.nearest(get_tree(), _player.global_position)
	if throne == null or is_busy() or not _player.is_on_floor() or _player.health_component.is_dead:
		return false
	_sit(throne)
	return true


func _sit(throne: Throne) -> void:
	_throne = throne
	var animator := _animator()
	var model := _player.player_model
	if animator == null or model == null:
		return
	if not animator.has_animation_library(&"village"):
		animator.add_animation_library(&"village", load(Villager.ANIMS))
	_model_transform = model.transform
	var tree := _anim_tree()
	_tree_was_active = tree != null and tree.active
	if tree != null:
		tree.active = false
	_player.velocity = Vector3.ZERO
	_player.movement.velocity = Vector3.ZERO
	var scale := model.global_basis.get_scale()
	var to_throne := throne.global_transform.affine_inverse()
	_stand_pose = to_throne * model.global_transform
	# Sentado: las caderas, en el asiento. Se mide con la pose sentada puesta.
	animator.play(IDLE_ANIM)
	animator.advance(0.0)
	_seat_pose = Transform3D(Basis.from_scale(scale), Throne.SEAT - Basis.from_scale(scale) * _hips_in_model())
	animator.play(SIT_ANIM, 0.0)
	animator.advance(0.0)
	_clip_length = animator.current_animation_length
	_clip_time = 0.0
	_phase = Phase.SITTING
	_sat_frame = Engine.get_process_frames()
	_previous_mouse_mode = Input.get_mouse_mode()


## Se levanta: sentarse al revés, y de pie delante del trono.
func stand_up() -> void:
	if _phase != Phase.SEATED and _phase != Phase.SITTING:
		return
	_close_view()
	var animator := _animator()
	animator.play_backwards(SIT_ANIM, 0.2)
	_clip_length = animator.get_animation(SIT_ANIM).length
	_clip_time = 0.0
	_phase = Phase.STANDING
	# De pie acaba delante del trono, mirando hacia fuera.
	_stand_pose = Transform3D(Basis.from_scale(_seat_pose.basis.get_scale()), Throne.STAND)


## De golpe (al morir, al cargar o al volver al menú).
func _force_close() -> void:
	if _phase == Phase.NONE:
		return
	_close_view()
	_finish_standing()


func _finish_standing() -> void:
	_phase = Phase.NONE
	var animator := _animator()
	if animator != null:
		animator.stop()
	if is_instance_valid(_player.player_model):
		_player.player_model.transform = _model_transform
	if _anim_tree() != null:
		_anim_tree().active = _tree_was_active
	if is_instance_valid(_throne):
		var frame := _throne.global_transform
		_player.global_position = frame * Throne.STAND
		_player.velocity = Vector3.ZERO
		_player.movement.velocity = Vector3.ZERO
	_throne = null


func _process(delta: float) -> void:
	if _phase == Phase.NONE:
		return
	if not is_instance_valid(_throne) or _throne.is_queued_for_deletion():
		_force_close()
		return
	var model := _player.player_model
	var frame := _throne.global_transform
	match _phase:
		Phase.SITTING:
			_clip_time += delta
			var s := smoothstep(0.0, 1.0, clampf(_clip_time / _clip_length, 0.0, 1.0))
			model.global_transform = frame * _stand_pose.interpolate_with(_seat_pose, s)
			if _clip_time >= _clip_length:
				_animator().play(IDLE_ANIM, 0.3)
				_phase = Phase.SEATED
				_open_view()
		Phase.SEATED:
			model.global_transform = frame * _seat_pose
			_update_view(delta)
		Phase.STANDING:
			_clip_time += delta
			var s := smoothstep(0.0, 1.0, clampf(_clip_time / _clip_length, 0.0, 1.0))
			model.global_transform = frame * _seat_pose.interpolate_with(_stand_pose, s)
			if _clip_time >= _clip_length:
				_finish_standing()


## Dónde quedan las caderas en el marco del cuerpo (sin su escala), con la pose que tiene ahora.
func _hips_in_model() -> Vector3:
	var model := _player.player_model
	var skeleton := model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if skeleton == null:
		return Vector3(0.0, 0.55, 0.0)
	var bone := skeleton.find_bone(HIPS)
	if bone < 0:
		return Vector3(0.0, 0.55, 0.0)
	var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	var local := model.global_transform.affine_inverse() * world
	return local * model.global_basis.get_scale()


## El árbol de animación del jugador (el de AnimationController: PlayerController.animator_tree no
## siempre está puesto).
func _anim_tree() -> AnimationTree:
	if _player.animation_controller != null and _player.animation_controller.animation_tree != null:
		return _player.animation_controller.animation_tree
	return _player.animator_tree


func _animator() -> AnimationPlayer:
	return _player.animation_controller.animator if _player != null and _player.animation_controller != null else null


# --- La vista -------------------------------------------------------------------------------------

func _open_view() -> void:
	_camera = Camera3D.new()
	_camera.name = "ThroneCamera"
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = VIEW_FOV
	_camera.near = 0.5
	_camera.far = 4000.0
	# Se coloca en _process (cada fotograma), no en la física: sin interpolar.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_throne.add_child(_camera)
	_pan = Vector3.ZERO
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.no_depth_test = true
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.vertex_color_use_as_albedo = true
	_ring_material.render_priority = 10
	_zones = _ring_node()
	_cursor_ring = _ring_node()
	_markers = _ring_node()
	_pitch = VIEW_PITCH
	_yaw = 0.0
	_dragging = false
	_update_camera()
	_camera.make_current()
	_selected.clear()
	_placing = SettlerWork.Job.NONE
	_refresh_left = 0.0
	visible = true
	_layout()
	_player.capture_mouse(false)
	_refresh()


func _close_view() -> void:
	if not visible:
		return
	visible = false
	_placing = SettlerWork.Job.NONE
	for label in _labels.values():
		if is_instance_valid(label):
			(label as Node).queue_free()
	_labels.clear()
	for node in [_camera, _zones, _cursor_ring, _markers]:
		if is_instance_valid(node):
			(node as Node).queue_free()
	_camera = null
	if is_instance_valid(_player.camera):
		_player.camera.make_current()
	_player.capture_mouse(_previous_mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _ring_node() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = ImmediateMesh.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_throne.add_child(node)
	return node


func _update_view(delta: float) -> void:
	var move := Vector2(Input.get_axis(&"move_left", &"move_right"), Input.get_axis(&"move_back", &"move_forward"))
	if move != Vector2.ZERO:
		# Adelante es hacia donde mira la cámara, sobre el suelo.
		var up := _up()
		var right := _camera.global_basis.x.slide(up).normalized()
		var ahead := (-_camera.global_basis.z).slide(up).normalized()
		var step := (right * move.x + ahead * move.y) * _size * PAN_SPEED * delta
		_pan += _throne.global_basis.inverse() * step
		var flat := Vector3(_pan.x, 0.0, _pan.z)
		if flat.length() > PAN_LIMIT:
			flat = flat.normalized() * PAN_LIMIT
		_pan = Vector3(flat.x, 0.0, flat.z)
	var tilt := float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
	if tilt != 0.0:
		_pitch = clampf(_pitch + tilt * TILT_SPEED * delta, PITCH.x, PITCH.y)
	_update_camera()
	_draw_markers()
	_cursor = _mouse_ground()
	_draw_cursor()
	_update_labels()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		_refresh()


## El arriba del planeta en el trono (mundo).
func _up() -> Vector3:
	var terrain := _terrain()
	return (_throne.global_position - terrain.global_position).normalized() if terrain != null \
		else _throne.global_basis.y.normalized()


func _terrain() -> Node3D:
	return _settlers[0]._terrain if not _settlers.is_empty() else (_player.get("planet").get("planet").voxel_terrain
		if _player.get("planet") != null else null)


func _update_camera() -> void:
	var up := _up()
	var center := _throne.global_transform * _pan
	var forward := _throne.global_basis.z.normalized()
	forward = (forward - up * forward.dot(up)).normalized().rotated(up, _yaw)
	# Desde delante del trono (girada _yaw) y por encima, mirando hacia él, a la distancia a la que el
	# centro de la vista tiene _size m de alto.
	var eye := center + (forward * cos(_pitch) + up * sin(_pitch)) * _view_distance()
	# Sin meterse en una ladera: sobre el suelo que tenga debajo, al menos CLEARANCE m.
	var space := _throne.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye + up * 400.0, eye - up * 400.0,
		PhysicsLayers.WORLD))
	if not hit.is_empty():
		var above := (eye - (hit.position as Vector3)).dot(up)
		if above < CLEARANCE:
			eye += up * (CLEARANCE - above)
	_camera.look_at_from_position(eye, center, up)


## La distancia de la cámara al centro (m) a la que este se ve con _size m de alto.
func _view_distance() -> float:
	return _size * 0.5 / tan(deg_to_rad(VIEW_FOV) * 0.5)


## Dónde toca el suelo el rayo del ratón (mundo), o INF.
func _mouse_ground() -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	if _panel.get_global_rect().has_point(mouse):
		return Vector3.INF
	var from := _camera.project_ray_origin(mouse)
	var to := from + _camera.project_ray_normal(mouse) * (_view_distance() * 3.0 + 200.0)
	var hit := _throne.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD))
	return hit.position if not hit.is_empty() else Vector3.INF


## El círculo de la zona que se marca, bajo el ratón.
func _draw_cursor() -> void:
	var mesh := _cursor_ring.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _placing == SettlerWork.Job.NONE or not _cursor.is_finite():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _ring_material)
	_ring(mesh, _cursor, _zone_radius, JOB_COLORS[_placing])
	mesh.surface_end()


## Un aro bajo cada colono, en el plano de sus pies (sin buscar el suelo: va cada fotograma), que se ve
## a través de los árboles; el de los elegidos, en amarillo.
func _draw_markers() -> void:
	var mesh := _markers.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _settlers.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _ring_material)
	var radius := maxf(_size * MARKER_RADIUS, 0.8)
	for c in _settlers:
		if is_instance_valid(c):
			_ring(mesh, c.global_position, radius, SELECTED_COLOR if _selected.has(c) else LABEL_COLOR, false, 24,
				radius * 0.18)
	mesh.surface_end()


## Las zonas de los colonos: la marcada o, sin ella, su radio alrededor de la base (más tenue).
func _draw_zones() -> void:
	var mesh := _zones.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var drawn := {}
	var started := false
	for c in _settlers:
		var work := c.work
		# El cocinero no tiene zona.
		if not work.active() or work.job == SettlerWork.Job.COOK:
			continue
		var center: Vector3 = c._terrain.global_transform * (work.zone if work.zone.is_finite() else c.base)
		var key := "%d:%.0f:%.0f:%.0f" % [work.job, center.x, center.y, center.z]
		if drawn.has(key):
			continue
		drawn[key] = true
		if not started:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _ring_material)
			started = true
		var color: Color = JOB_COLORS.get(work.job, Color.WHITE)
		if not work.zone.is_finite():
			color.a *= 0.45
		_ring(mesh, center, work.zone_radius, color)
	if started:
		mesh.surface_end()


## Un aro de [radius] m alrededor de [center] (mundo), pegado al suelo ([ground]; si no, en el plano de
## [center]), de [segments] tramos, en [mesh] (marco del trono).
func _ring(mesh: ImmediateMesh, center: Vector3, radius: float, color: Color, ground := true,
		segments := RING_SEGMENTS, width := -1.0) -> void:
	var up := (center - _terrain().global_position).normalized() if _terrain() != null else _up()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var space := _throne.get_world_3d().direct_space_state
	var to_local := _throne.global_transform.affine_inverse()
	var half := width * 0.5 if width > 0.0 else maxf(_size * RING_WIDTH, 0.15)
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	for i in segments + 1:
		var dir := side.rotated(up, TAU * i / segments)
		var p := center + dir * radius
		if ground:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + up * 40.0, p - up * 40.0, PhysicsLayers.WORLD))
			if not hit.is_empty():
				p = hit.position
		p += up * 0.2
		inner.append(to_local * (p - dir * half))
		outer.append(to_local * (p + dir * half))
	for i in segments:
		for v in [inner[i], outer[i], outer[i + 1], inner[i], outer[i + 1], inner[i + 1]]:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(v)


## El nombre de cada colono sobre su cabeza, y lo que hace.
func _update_labels() -> void:
	for c in _settlers:
		if not is_instance_valid(c):
			continue
		var label: Label3D = _labels.get(c)
		if label == null:
			label = Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.fixed_size = true
			label.pixel_size = LABEL_PIXEL
			label.font_size = 28
			label.outline_size = 8
			label.render_priority = 11
			# Encima de su aro, no sobre él.
			label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			label.offset = Vector2(0.0, LABEL_LIFT)
			_throne.add_child(label)
			_labels[c] = label
		label.global_position = c.global_position + c.up_direction * 1.9
		var job: String = tr(SettlerWork.JOB_NAMES.get(c.work.job, "SETTLER_JOB_NONE"))
		if c.work.job == SettlerWork.Job.GUARD:
			job = tr("SETTLER_JOB_GUARD_NIGHT" if c.work.shift == 1 else "SETTLER_JOB_GUARD_DAY")
		var name := String(c.resident.get("name", ""))
		label.text = name if _size > NAME_ONLY else "%s\n%s" % [name, job]
		label.modulate = SELECTED_COLOR if _selected.has(c) else LABEL_COLOR


# --- Entrada --------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _phase == Phase.NONE or Engine.get_process_frames() == _sat_frame:
		return
	if event.is_action_pressed(&"action"):
		stand_up()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		if _placing != SettlerWork.Job.NONE:
			_placing = SettlerWork.Job.NONE
			_refresh()
		else:
			stand_up()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _phase != Phase.SEATED:
		return
	# Arrastrando con el botón central: arriba y abajo inclina, a los lados gira.
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			_pitch = clampf(_pitch + motion.relative.y * DRAG, PITCH.x, PITCH.y)
			_yaw -= motion.relative.x * DRAG
			get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = button.pressed
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			var sign := -1.0 if click.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if _placing != SettlerWork.Job.NONE:
				_zone_radius = clampf(_zone_radius - sign * ZONE_STEP, ZONE_RADIUS.x, ZONE_RADIUS.y)
				_refresh()
			else:
				_size = clampf(_size * (1.0 + sign * 0.12), ZOOM.x, ZOOM.y)
		MOUSE_BUTTON_LEFT:
			if _placing != SettlerWork.Job.NONE:
				if _cursor.is_finite():
					_assign(_placing, _cursor, _zone_radius)
			else:
				_pick(click.position)
		MOUSE_BUTTON_RIGHT:
			# Alrededor de su base; limpiar y la guardia piden zona: se cancela.
			if _placing != SettlerWork.Job.NONE and not NEEDS_ZONE.has(_placing):
				_assign(_placing, Vector3.INF, -1.0)
			_placing = SettlerWork.Job.NONE
			_refresh()
		_:
			return
	get_viewport().set_input_as_handled()


## Elige (o deja) al colono cuyo nombre está bajo [at] (pantalla).
func _pick(at: Vector2) -> void:
	var best: Companion
	var best_d := PICK_PIXELS
	for c in _settlers:
		var label: Label3D = _labels.get(c)
		if label == null or _camera.is_position_behind(label.global_position):
			continue
		var d := _camera.unproject_position(label.global_position).distance_to(at)
		if d < best_d:
			best = c
			best_d = d
	if best == null:
		return
	if _selected.has(best):
		_selected.erase(best)
	else:
		_selected[best] = true
	_refresh()


## Manda [job] a los elegidos: en la zona de [at] (mundo; INF, alrededor de su base) de [radius] m.
func _assign(job: SettlerWork.Job, at: Vector3, radius: float) -> void:
	for c in _selected.keys():
		if not is_instance_valid(c) or (c as Companion).dead:
			continue
		var companion := c as Companion
		var local := companion._terrain.global_transform.affine_inverse() * at if at.is_finite() else Vector3.INF
		companion.work.assign(job, local, radius, _placing_shift if job == SettlerWork.Job.GUARD else 0)
	_placing = SettlerWork.Job.NONE
	_refresh()


func _on_order(job: SettlerWork.Job, shift := 0) -> void:
	if _selected.is_empty():
		return
	if job == SettlerWork.Job.NONE:
		for c in _selected.keys():
			if is_instance_valid(c):
				(c as Companion).work.stop()
		_placing = SettlerWork.Job.NONE
	elif job == SettlerWork.Job.COOK:
		# El cocinero no tiene zona: la hoguera de su base.
		_assign(job, Vector3.INF, -1.0)
	else:
		_placing = job
		_placing_shift = shift
	_refresh()


## Los elegidos se van con el jugador (los que quepan en el grupo): lo siguen en cuanto se levante.
func _on_follow() -> void:
	var companions := get_tree().get_first_node_in_group(SettlementCompanions.GROUP) as SettlementCompanions
	if companions == null or _selected.is_empty():
		return
	var went := 0
	var left := 0
	for c in _selected.keys():
		if not is_instance_valid(c) or (c as Companion).dead:
			continue
		if companions.is_full():
			left += 1
			continue
		(c as Companion).follow()
		went += 1
	_placing = SettlerWork.Job.NONE
	if went > 0 or left > 0:
		_player.hotbar.notify(tr("THRONE_FOLLOW_SOME") % [went, left] if left > 0 else tr("THRONE_FOLLOW_DONE") % went)
	_refresh()


func _select_all(on: bool) -> void:
	_selected.clear()
	if on:
		for c in _settlers:
			_selected[c] = true
	_refresh()


# --- La lista -------------------------------------------------------------------------------------

## Los colonos de este trono: viven en la base, con ella a menos de Throne.MANAGE_RADIUS m.
func _gather() -> void:
	_settlers.clear()
	var companions := get_tree().get_first_node_in_group(SettlementCompanions.GROUP) as SettlementCompanions
	if companions == null or not is_instance_valid(_throne):
		return
	for c in companions.get_companions():
		if c.mode != Companion.Mode.SETTLE or not c.base.is_finite():
			continue
		if (c._terrain.global_transform * c.base).distance_to(_throne.global_position) <= Throne.MANAGE_RADIUS:
			_settlers.append(c)
	for c in _selected.keys():
		if not _settlers.has(c):
			_selected.erase(c)
	for c in _labels.keys():
		if not _settlers.has(c):
			if is_instance_valid(_labels[c]):
				(_labels[c] as Node).queue_free()
			_labels.erase(c)


func _refresh() -> void:
	if not visible:
		return
	_gather()
	for c in _rows.keys():
		if not _settlers.has(c):
			(_rows[c].row as Node).queue_free()
			_rows.erase(c)
	for c in _settlers:
		if not _rows.has(c):
			_rows[c] = _make_row(c)
		var row: Dictionary = _rows[c]
		(row.check as CheckBox).set_pressed_no_signal(_selected.has(c))
		(row.check as CheckBox).text = String(c.resident.get("name", ""))
		var status := c.work.describe()
		if status == "":
			status = tr("THRONE_IDLE") + (tr("SETTLER_HUNGRY") if c.meals.hungry() else "")
		(row.status as Label).text = status
	_empty.visible = _settlers.is_empty()
	for button in _orders:
		button.disabled = _selected.is_empty()
	_stop_button.disabled = _selected.is_empty()
	_follow_button.disabled = _selected.is_empty()
	if _placing == SettlerWork.Job.GUARD:
		_hint.text = tr("THRONE_HINT_GUARD") % [roundi(_zone_radius), roundi(SettlerGuard.POST_RADIUS)]
	elif _placing != SettlerWork.Job.NONE:
		_hint.text = tr("THRONE_HINT_CLEAR" if _placing == SettlerWork.Job.CLEAR else "THRONE_HINT_ZONE") % roundi(_zone_radius)
	elif _selected.is_empty():
		_hint.text = tr("THRONE_HINT_SELECT")
	else:
		_hint.text = tr("THRONE_HINT_ORDER") % _selected.size()
	_draw_zones()


func _make_row(c: Companion) -> Dictionary:
	var row := VBoxContainer.new()
	_list.add_child(row)
	var check := CheckBox.new()
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void:
		if on:
			_selected[c] = true
		else:
			_selected.erase(c)
		_refresh())
	row.add_child(check)
	var status := Label.new()
	status.theme_type_variation = &"HintLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(status)
	return {"row": row, "check": check, "status": status}


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"WindowPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	_box = VBoxContainer.new()
	_margin.add_child(_box)
	var title := Label.new()
	title.text = "THRONE_TITLE"
	title.theme_type_variation = &"HeaderLabel"
	_box.add_child(title)
	_box.add_child(HSeparator.new())
	var all_row := HBoxContainer.new()
	_box.add_child(all_row)
	for pair in [["THRONE_ALL", true], ["THRONE_NONE", false]]:
		var button := Button.new()
		button.text = pair[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_all.bind(pair[1]))
		all_row.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_empty = Label.new()
	_empty.text = "THRONE_EMPTY"
	_empty.theme_type_variation = &"HintLabel"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(_empty)
	_box.add_child(HSeparator.new())
	var orders_title := Label.new()
	orders_title.text = "THRONE_ORDERS"
	orders_title.theme_type_variation = &"SectionLabel"
	_box.add_child(orders_title)
	var orders := HFlowContainer.new()
	_box.add_child(orders)
	for pair in [["SETTLER_ORDER_FELL", SettlerWork.Job.FELL, 0], ["SETTLER_ORDER_MINE", SettlerWork.Job.MINE, 0],
			["THRONE_ORDER_CLEAR", SettlerWork.Job.CLEAR, 0], ["SETTLER_ORDER_BUILD", SettlerWork.Job.BUILD, 0],
			["SETTLER_ORDER_HUNT", SettlerWork.Job.HUNT, 0], ["SETTLER_ORDER_FISH", SettlerWork.Job.FISH, 0],
			["SETTLER_ORDER_COOK", SettlerWork.Job.COOK, 0], ["THRONE_ORDER_GUARD_DAY", SettlerWork.Job.GUARD, 0],
			["THRONE_ORDER_GUARD_NIGHT", SettlerWork.Job.GUARD, 1]]:
		var button := Button.new()
		button.text = pair[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_order.bind(pair[1], pair[2]))
		orders.add_child(button)
		_orders.append(button)
	_stop_button = Button.new()
	_stop_button.text = "SETTLER_ORDER_STOP"
	_stop_button.focus_mode = Control.FOCUS_NONE
	_stop_button.pressed.connect(_on_order.bind(SettlerWork.Job.NONE))
	orders.add_child(_stop_button)
	_follow_button = Button.new()
	_follow_button.text = "THRONE_ORDER_FOLLOW"
	_follow_button.tooltip_text = "THRONE_ORDER_FOLLOW_TIP"
	_follow_button.focus_mode = Control.FOCUS_NONE
	_follow_button.pressed.connect(_on_follow)
	orders.add_child(_follow_button)
	_hint = Label.new()
	_hint.theme_type_variation = &"HintLabel"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_hint)
	_box.add_child(HSeparator.new())
	var keys := Label.new()
	keys.text = "THRONE_KEYS"
	keys.theme_type_variation = &"HintLabel"
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(keys)


func _layout() -> void:
	var ui_scale := GameTheme.scale_for(get_viewport())
	_root.theme = GameTheme.build(ui_scale)
	_panel.custom_minimum_size.x = 420.0 * ui_scale
	_panel.offset_left = -420.0 * ui_scale
	_box.add_theme_constant_override("separation", roundi(10.0 * ui_scale))
	for side in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, roundi(20.0 * ui_scale))
