extends SceneTree

## Escenario de animación: el cuerpo real del jugador sobre un suelo plano, con las poses de
## combate conducidas por una línea de tiempo fija (sin juego ni física de por medio), visto a
## la vez desde varias cámaras. Sirve para comparar antes/después de tocar una animación.
##   godot --path . --audio-driver Dummy --fixed-fps 30 --script res://tests/combat/anim_stage.gd \
##       -- --tag=x --scene=bow [--background] [--frames] [--armor=leather_armor] [--twist]
## Guarda build/combat/stage/<tag>_<scene>_<vista>.png (tira de fotogramas por vista) y, con
## --frames, cada fotograma en build/combat/stage/frames/ para montar un GIF.
## --fixed-fps hace que cada fotograma avance exactamente 1/30 s (muelles deterministas).
## --armor viste un conjunto de scenes/items/armor/ (las deformaciones se ven mucho más con
## armadura); --twist imprime cuánto se retuercen los huesos de los brazos en el arco.
## --scene=run|sprint --item=<arma> corre con el arma en la mano (CombatPose.carry; --no-carry la
## quita) e imprime la holgura mínima entre el arma y cada parte del cuerpo.

const MODEL := "res://scenes/character/character_model.tscn"
const OUT := "res://build/combat/stage"
const FPS := 30.0
const CELL := Vector2i(360, 450)
const SHEET_COLS := 10

## Vistas: posición de la cámara y punto al que mira, en el marco del personaje (+Z adelante,
## +X a su izquierda). El blanco está hacia +Z.
const VIEWS := {
	"front": [Vector3(-2.3, 1.55, 2.3), Vector3(0.0, 1.15, 0.2)],
	"side": [Vector3(-3.4, 1.35, 0.3), Vector3(0.0, 1.1, 0.3)],
	"game": [Vector3(-0.75, 1.85, -2.3), Vector3(0.1, 1.45, 3.0)],
	"back": [Vector3(1.6, 1.6, -2.6), Vector3(0.0, 1.2, 0.2)],
	"top": [Vector3(-1.2, 3.2, 0.6), Vector3(0.0, 1.2, 0.4)],
}
## Primeros planos que siguen a un hueso: [hueso, desplazamiento de la cámara (marco del personaje)].
const FOLLOW_VIEWS := {
	"lhand": ["mixamorig_LeftHandMiddle1", Vector3(-0.5, 0.12, 0.3)],
	"rhand": ["mixamorig_RightHandMiddle1", Vector3(-0.5, 0.1, 0.2)],
	"head": ["mixamorig_Head", Vector3(-0.7, 0.1, 0.35)],
	"rhand_in": ["mixamorig_RightHandMiddle1", Vector3(0.35, 0.15, 0.45)],
	"rh_front": ["mixamorig_RightHandMiddle1", Vector3(-0.05, 0.05, 0.5)],
	"rh_back": ["mixamorig_RightHandMiddle1", Vector3(-0.05, 0.05, -0.5)],
	"rh_out": ["mixamorig_RightHandMiddle1", Vector3(-0.5, 0.05, 0.02)],
	"rh_down": ["mixamorig_RightHandMiddle1", Vector3(-0.1, -0.5, 0.05)],
	"relbow": ["mixamorig_RightForeArm", Vector3(-0.35, 0.25, -0.45)],
	"relbow_out": ["mixamorig_RightForeArm", Vector3(0.1, 0.15, -0.6)],
}

var _tag := "preview"
var _scene := "bow"
var _save_frames := false
var _views: PackedStringArray = ["front", "side", "game"]
## Conjunto de armadura puesto (carpeta de scenes/items/armor/, p. ej. leather_armor), o "".
var _armor := ""
## Imprime la torsión de los huesos de los brazos durante el arco (--twist).
var _twist_log := false
## Monta un LookAtIK como el del jugador, mirando al blanco (--look).
var _look := false
var _look_full := false
## Imprime la altura y el cabeceo de la cabeza en cada fotograma del arco (--head-log).
var _head_log := false
var look_ik: LookAtIK
## Corrección de llevar el arma al correr (CombatPose.carry); --no-carry la apaga para comparar.
var _carry := true

var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var pose: CombatPose
var bow: RangedWeaponVisual
var arrow: MeshInstance3D
var right_item: Node3D
var quiver: QuiverVisual
var _viewports: Dictionary = {}
var _cams: Dictionary = {}
## Giro del cuerpo (grados) que en el juego pone PlayerCombat: de perfil al apuntar quieto.
var stance_yaw: float = 0.0
## Colocación de visuales de la escena tras posar (dentro del modificador).
var _placer: Callable
## Posiciones de huesos medidas dentro del modificador (fuera, el esqueleto no las tiene).
var _bone_world: Dictionary = {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--scene="):
			_scene = arg.substr(8)
		elif arg.begins_with("--views="):
			_views = arg.substr(8).split(",")
		elif arg.begins_with("--stance="):
			_stance_override = float(arg.substr(9))
		elif arg.begins_with("--pitch="):
			_aim_pitch = float(arg.substr(8))
		elif arg.begins_with("--armor="):
			_armor = arg.substr(8)
		elif arg == "--head-log":
			_head_log = true
		elif arg == "--look":
			_look = true
		elif arg == "--look-full":
			# La mirada sin apagar al apuntar (como antes), para comparar.
			_look = true
			_look_full = true
		elif arg == "--no-carry":
			_carry = false
		elif arg == "--twist":
			_twist_log = true
		elif arg == "--frames":
			_save_frames = true
		elif arg == "--background":
			root.unfocusable = true
			root.position = Vector2i(-4000, -4000)
	_run.call_deferred()


func _build_world() -> void:
	root.size = CELL
	var world := Node3D.new()
	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.42, 0.52, 0.60)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -140, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var ground_mat := StandardMaterial3D.new()
	var checker := Image.create(2, 2, false, Image.FORMAT_RGB8)
	checker.set_pixel(0, 0, Color(0.62, 0.52, 0.38))
	checker.set_pixel(1, 1, Color(0.62, 0.52, 0.38))
	checker.set_pixel(1, 0, Color(0.55, 0.46, 0.33))
	checker.set_pixel(0, 1, Color(0.55, 0.46, 0.33))
	ground_mat.albedo_texture = ImageTexture.create_from_image(checker)
	ground_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground_mat.uv1_scale = Vector3(20, 20, 1)
	plane.material = ground_mat
	ground.mesh = plane
	world.add_child(ground)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	# Diana a lo lejos, para ver hacia dónde apunta.
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 1.6, 0.1)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.75, 0.2, 0.15)
	box.material = post_mat
	post.mesh = box
	post.position = Vector3(0, 0.8, 14)
	world.add_child(post)

	model = load(MODEL).instantiate()
	var holder: Node3D = world
	if _look:
		# LookAtIK como en el jugador (antes de CombatPose), mirando al blanco: necesita un cuerpo.
		holder = CharacterBody3D.new()
		world.add_child(holder)
	holder.add_child(model)
	(model.get_node("AppearanceRig") as CharacterAppearanceRig).apply(CharacterAppearance.new())
	skel = model.get_node("Armature/Skeleton3D")
	anim = model.get_node("AnimationPlayer")
	if _look:
		var target := Node3D.new()
		target.name = "LookTarget"
		world.add_child(target)
		target.position = Vector3(0, 1.5, 0) + Vector3(0, sin(deg_to_rad(_aim_pitch)), cos(deg_to_rad(_aim_pitch))) * 20.0
		look_ik = LookAtIK.new()
		look_ik.name = "LookAtIK"
		look_ik.body_forward = Vector3.BACK
		skel.add_child(look_ik)
		look_ik.target_path = look_ik.get_path_to(target)
	pose = CombatPose.new()
	pose.frame_node = model
	pose.after_pose = _after_pose
	skel.add_child(pose)

	for view in _views:
		var vp := SubViewport.new()
		vp.size = CELL
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		root.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 42
		vp.add_child(cam)
		cam.current = true
		if VIEWS.has(view):
			var v: Array = VIEWS[view]
			cam.look_at_from_position(v[0], v[1])
		else:
			cam.fov = 30
		_viewports[view] = vp
		_cams[view] = cam


func _add_bow() -> void:
	bow = load("res://scenes/items/weapons/combat/hunting_bow.tscn").instantiate()
	bow.top_level = true
	model.add_child(bow)
	arrow = MeshInstance3D.new()
	arrow.mesh = load("res://data/items/meshes/weapons/arrow.res")
	arrow.top_level = true
	arrow.visible = false
	model.add_child(arrow)
	quiver = QuiverVisual.new()
	quiver.top_level = true
	model.add_child(quiver)


var _right_grip: Node3D


func _add_right_item(item: String) -> void:
	_right_grip = Node3D.new()
	_right_grip.top_level = true
	model.add_child(_right_grip)
	right_item = load("res://scenes/items/weapons/combat/%s.tscn" % item).instantiate()
	_right_grip.add_child(right_item)
	pose.grip_right = true


## Viste al personaje con todas las piezas del conjunto [_armor], ajustadas a su cuerpo como en
## el juego (CharacterAppearanceRig.dress), y espera a que acabe el ajuste.
func _dress() -> void:
	if _armor == "":
		return
	var rig := model.get_node("AppearanceRig") as CharacterAppearanceRig
	var dir := "res://scenes/items/armor/%s" % _armor
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with("_equipable.tscn"):
			continue
		var item: Node = load(dir + "/" + file).instantiate()
		skel.add_child(item)
		rig.dress(item, file.contains("hood") or file.contains("helmet"))
	while rig.is_dressing():
		await process_frame


func _run() -> void:
	_build_world()
	await _dress()
	var duration := 1.0
	var driver: Callable
	var base_anim := "idle"
	match _scene:
		"bow", "bow_walk":
			_add_bow()
			duration = 5.1
			driver = _drive_bow
			if _scene == "bow_walk":
				base_anim = "running"
				_walking = true
		"bow_anim", "bow_hold":
			_add_bow()
			anim.add_animation_library(&"combat", load("res://models/player/mixamo/combat_anims.tres"))
			duration = 5.6
			if _scene == "bow_hold":
				# Tensar y sostener a tope unos segundos.
				_bow_timeline = [["bow_draw", 4.8]]
				duration = 4.8
			driver = _drive_bow_anim
		"fingers":
			duration = 1.0
			driver = _drive_fingers
		"stagger":
			duration = 2.4
			driver = _drive_stagger
			_add_right_item("iron_sword")
		"backstep":
			duration = 1.6
			driver = _drive_backstep
			_add_right_item("iron_sword")
		"grip":
			var item := "iron_sword"
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--item="):
					item = arg.substr(7)
			_add_right_item(item)
			duration = 0.2
			driver = func(_t: float) -> void: pass
		"melee_h", "melee_v":
			var item := "iron_sword"
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--item="):
					item = arg.substr(7)
			_add_right_item(item)
			base_anim = "attack_horizontal" if _scene == "melee_h" else "attack_vertical"
			duration = anim.get_animation(base_anim).length
			driver = func(_t: float) -> void: pass
		"run", "sprint":
			# Correr con un arma en la mano (--item=): la hoja no debe meterse en el cuerpo.
			var item := "iron_sword"
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--item="):
					item = arg.substr(7)
			_add_right_item(item)
			if item == "spear":
				pose.carry_perpendicular = false
			base_anim = "running" if _scene == "run" else "sprinting"
			duration = anim.get_animation(base_anim).length
			driver = func(_t: float) -> void:
				pose.carry = 1.0 if _carry else 0.0
			_placer = _measure_clearance
		"death":
			duration = 3.0
			driver = _drive_death
			_add_right_item("iron_mace")
		"throw":
			_add_right_item("spear")
			duration = 3.0
			driver = _drive_throw
		_:
			push_error("escena desconocida " + _scene)
			quit(1)
			return
	anim.play(base_anim)
	DirAccess.make_dir_recursive_absolute(OUT + "/frames")
	var frames := int(ceil(duration * FPS))
	var sheet_every := maxi(1, int(round(frames / float(SHEET_COLS * 2))))
	var sheet_frames: Array[int] = []
	for f in range(0, frames, sheet_every):
		sheet_frames.append(f)
	var rows := int(ceil(sheet_frames.size() / float(SHEET_COLS)))
	var sheets := {}
	for view in _views:
		sheets[view] = Image.create(CELL.x * SHEET_COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	# Unos fotogramas para que la animación base y los modificadores arranquen.
	driver.call(0.0)
	for i in 3:
		await process_frame
	for f in frames:
		var t := f / FPS
		driver.call(t)
		model.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(stance_yaw)), body_offset)
		await process_frame
		for view in _views:
			if VIEWS.has(view):
				var v: Array = VIEWS[view]
				(_cams[view] as Camera3D).look_at_from_position(v[0] + body_offset, v[1] + body_offset)
			if FOLLOW_VIEWS.has(view):
				var fv: Array = FOLLOW_VIEWS[view]
				var target: Vector3 = _bone_world.get(fv[0], Vector3.ZERO)
				(_cams[view] as Camera3D).look_at_from_position(target + fv[1], target)
		await RenderingServer.frame_post_draw
		var slot := sheet_frames.find(f)
		for view in _views:
			var img: Image = (_viewports[view] as SubViewport).get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			_stamp_time(img, t)
			if slot >= 0:
				sheets[view].blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
					Vector2i((slot % SHEET_COLS) * CELL.x, (slot / SHEET_COLS) * CELL.y))
			if _save_frames:
				img.save_png("%s/frames/%s_%s_%s_%03d.png" % [OUT, _tag, _scene, view, f])
	for part in _clearance:
		print("holgura %s: %.3f m" % [part, _clearance[part]])
	if not _clearance.is_empty():
		print("arma-antebrazo: %.0f..%.0f grados" % [_forearm_angle.x, _forearm_angle.y])
	for view in _views:
		var path := "%s/%s_%s_%s.png" % [OUT, _tag, _scene, view]
		sheets[view].save_png(path)
		print("saved ", path)
	quit()


## Holgura (m) entre el arma de la mano derecha y el cuerpo, por partes: el eje del arma (fuera
## del puño) contra cada segmento de hueso, menos el grosor de la carne. Negativo = se mete.
## Se imprime el mínimo de cada parte al acabar.
const CLEARANCE_BONES := {
	"muslo": ["mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.09],
	"espinilla": ["mixamorig_RightLeg", "mixamorig_RightFoot", 0.06],
	"muslo_izq": ["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.09],
	"tronco": ["mixamorig_Hips", "mixamorig_Neck", 0.16],
	"cabeza": ["mixamorig_Neck", "mixamorig_HeadTop_End", 0.11],
}
var _clearance: Dictionary = {}
## Ángulo (grados) entre el arma y el antebrazo: mínimo y máximo.
var _forearm_angle := Vector2(INF, -INF)


func _measure_clearance(p: CombatPose) -> void:
	if right_item == null:
		return
	var span := Vector2(INF, -INF)
	for mesh_node in right_item.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		var box := right_item.transform * mi.transform * mi.get_aabb()
		span = Vector2(minf(span.x, box.position.y), maxf(span.y, box.end.y))
	var grip := p.right_grip_xform
	var forearm := p.bone_world("mixamorig_RightHand") - p.bone_world("mixamorig_RightForeArm")
	var angle := rad_to_deg(forearm.angle_to(grip.basis.y))
	_forearm_angle = Vector2(minf(_forearm_angle.x, angle), maxf(_forearm_angle.y, angle))
	# Fuera del puño (unos 6 cm a cada lado del agarre).
	var ends := {}
	if span.y > 0.06:
		ends[""] = [grip * Vector3(0, 0.06, 0), grip * Vector3(0, span.y, 0)]
	if span.x < -0.06:
		ends[" (pomo)"] = [grip * Vector3(0, -0.06, 0), grip * Vector3(0, span.x, 0)]
	# La mano (muñeca a nudillos, unos 4 cm de grosor) también cuenta.
	ends[" (mano)"] = [p.bone_world("mixamorig_RightHand"), p.bone_world("mixamorig_RightHandMiddle1")]
	for part in CLEARANCE_BONES:
		var bone: Array = CLEARANCE_BONES[part]
		var a := p.bone_world(bone[0])
		var b := p.bone_world(bone[1])
		for end in ends:
			var seg: Array = ends[end]
			var pts := Geometry3D.get_closest_points_between_segments(seg[0], seg[1], a, b)
			var d: float = pts[0].distance_to(pts[1]) - bone[2] - (0.04 if end == " (mano)" else 0.0)
			_clearance[part + end] = minf(_clearance.get(part + end, INF), d)


## Marca de tiempo: una raya por décima de segundo (roja cada segundo).
func _stamp_time(img: Image, t: float) -> void:
	var tenth := int(round(t * 10.0))
	for d in range(mini(tenth, 60)):
		img.fill_rect(Rect2i(4 + (d % 30) * 7, 4 + (d / 30) * 7, 5, 5),
			Color(0.1, 0.1, 0.1) if d % 10 != 9 else Color(0.8, 0.1, 0.1))


static func _ramp(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t)


# ---------------------------------------------------------------------------------------------
# Líneas de tiempo


## Arco, como lo lleva PlayerCombat: sube el arco sacando la primera flecha, tensa, sostiene,
## suelta, recarga, vuelve a tensar, suelta y baja.
var _walking := false
## Giro del cuerpo al apuntar quieto (--stance=N), como BOW_STANCE_YAW.
var _stance_override := -50.0
## Inclinación del tiro en grados (--pitch=N): positivo hacia arriba, como en una ladera.
var _aim_pitch := 0.0


func _drive_bow(t: float) -> void:
	var a := pose.archery
	var aim := _ramp(t, 0.0, 0.3) * (1.0 - _ramp(t, 4.6, 5.0))
	stance_yaw = 0.0 if _walking else _stance_override * aim
	if _walking:
		anim.speed_scale = 0.6
	a.draw = 0.0
	a.release_t = -1.0
	a.reload = -1.0
	a.hold_t = 0.0
	var reload_rate := 1.0 / ArcheryPose.RELOAD_TIME
	if t < 0.55:
		a.reload = minf(0.25 + t * reload_rate, 1.0)
	elif t < 2.3:
		a.draw = clampf((t - 0.6) / 0.8, 0.0, 1.0)
		a.hold_t = maxf(0.0, t - 1.4)
	elif t < 2.55:
		a.release_t = t - 2.3
	elif t < 2.55 + ArcheryPose.RELOAD_TIME:
		a.release_t = t - 2.3
		a.reload = (t - 2.55) * reload_rate
	elif t < 4.2:
		a.draw = clampf((t - 3.3) / 0.8, 0.0, 1.0)
	else:
		a.release_t = t - 4.2
	a.nocked = true
	pose.aim_weight = aim
	pose.aim_style = &"bow"
	pose.aim_dir = Vector3(0, sin(deg_to_rad(_aim_pitch)), cos(deg_to_rad(_aim_pitch)))
	pose.draw = a.draw
	_placer = _place_bow


## Arco con las animaciones de Mixamo (cuerpo entero, como quieto en el juego): saca la
## flecha, tensa, sostiene, suelta y repite. Los clips se encadenan sin saltos.
## Clip y cuánto dura; bow_draw más largo que el clip se queda en su final (sostener a tope).
const BOW_ANIM_TIMELINE := [["bow_draw", 2.4333], ["bow_recoil", 0.7], ["bow_draw", 1.5333],
	["bow_recoil", 0.7]]
var _bow_timeline: Array = BOW_ANIM_TIMELINE


func _drive_bow_anim(t: float) -> void:
	var rig := pose.bow_rig
	var start := 0.0
	for i in _bow_timeline.size():
		var entry: Array = _bow_timeline[i]
		if t < start + entry[1] or i == _bow_timeline.size() - 1:
			rig.clip = StringName(entry[0])
			rig.time = minf(minf(t - start, entry[1]), anim.get_animation("combat/" + entry[0]).length)
			break
		start += entry[1]
	anim.play("combat/" + String(rig.clip))
	anim.seek(rig.time, true)
	anim.pause()
	stance_yaw = 0.0
	pose.aim_weight = _ramp(t, 0.0, 0.2)
	if look_ik and not _look_full:
		look_ik.influence = 1.0 - pose.aim_weight
	pose.aim_style = &"bow"
	pose.aim_arms_ik = false
	pose.upper_hips_yaw = NAN
	pose.aim_dir = Vector3(0, sin(deg_to_rad(_aim_pitch)), cos(deg_to_rad(_aim_pitch)))
	_placer = func(p: CombatPose) -> void:
		_show_bow(p, p.bow_rig)


func _after_pose(p: CombatPose) -> void:
	if p.grip_right and _right_grip != null:
		_right_grip.global_transform = p.right_grip_xform
	for fv in FOLLOW_VIEWS.values():
		_bone_world[fv[0]] = p.bone_world(fv[0])
	if _placer.is_valid():
		_placer.call(p)


func _place_bow(p: CombatPose) -> void:
	var a := p.archery
	if Engine.get_process_frames() % 10 == 0 and p.aim_weight > 0.99:
		var ls := p.bone_world("mixamorig_LeftArm")
		var rs := p.bone_world("mixamorig_RightArm")
		var re := p.bone_world("mixamorig_RightForeArm")
		var lh := p.bone_world("mixamorig_LeftHand")
		var rh := p.bone_world("mixamorig_RightHand")
		var flat := func(v: Vector3) -> Vector3: return Vector3(v.x, 0, v.z)
		var aim := Vector3(0, 0, 1)
		print("draw=%.2f hombros-vs-flecha %.0f°  brazo izq-vs-flecha %.0f°  codo der detrás del hombro %.2f m, a su lado %.2f m, altura codo-hombro %.2f m, mano der-hombro der %.2f m" % [a.draw,
			rad_to_deg((flat.call(ls - rs) as Vector3).angle_to(aim)), rad_to_deg((flat.call(lh - ls) as Vector3).angle_to(aim)),
			-(re - rs).dot(aim), (re - rs).dot(Vector3(-1, 0, 0)), (re - rs).y, rh.distance_to(rs)])
	if _twist_log and Engine.get_process_frames() % 6 == 0:
		# Torsión (sobre su eje) y giro del resto de cada hueso del brazo respecto a su reposo: sin
		# huesos de torsión, más de unos 80° en el antebrazo estruja la piel del codo.
		var out := "draw=%.2f recarga=%.2f" % [a.draw, a.reload]
		for bn in ["mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"]:
			var i := skel.find_bone(bn)
			var q := skel.get_bone_rest(i).basis.get_rotation_quaternion().inverse() * skel.get_bone_pose_rotation(i)
			var tw := rad_to_deg(2.0 * atan2(q.y, q.w))
			var sw := rad_to_deg(2.0 * acos(clampf(sqrt(q.w * q.w + q.y * q.y), 0.0, 1.0)))
			out += "  %s tw=%.0f sw=%.0f" % [bn.replace("mixamorig_", ""), wrapf(tw, -180, 180), sw]
		print(out)
	_show_bow(p, a)


## Arco, cuerda, flecha y aljaba donde los deja [a] (ArcheryPose o BowAnimRig).
func _show_bow(p: CombatPose, a: Object) -> void:
	var q := ArcheryPose.quiver_skel(p)
	var skel_xf := skel.global_transform
	quiver.global_transform = Transform3D((skel_xf.basis * q.basis).orthonormalized(), skel_xf * q.origin)
	quiver.set_count(5)
	if p.aim_weight <= 0.01:
		bow.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, -5, 0))
		arrow.visible = false
		return
	if _scene == "bow_hold" and Engine.get_process_frames() % 3 == 0:
		_print_draw_arm(p, a)
	if _head_log:
		# Altura (mm, marco del personaje) y cabeceo (grados) de la cabeza, en cada fotograma.
		var hb := p.bone_world_basis("mixamorig_Head")
		var fwd := model.global_basis.inverse() * (hb * Vector3.FORWARD)
		print("head %s %.3f %.1f %.2f" % [a.clip, a.time, (model.global_transform.affine_inverse() * p.bone_world("mixamorig_Head")).y * 1000.0,
			rad_to_deg(asin(clampf(fwd.normalized().y, -1.0, 1.0)))])
	bow.global_transform = a.bow_xform
	bow.flex = a.bow_flex
	bow.set_draw_point(a.string_point)
	arrow.visible = a.arrow_mode != &""
	if arrow.visible:
		arrow.global_transform = a.arrow_xform


## Sostener a tope (bow_hold): holgura del antebrazo derecho con la cabeza (cápsula de 11 cm
## sobre cuello-coronilla) y tensión de la cuerda (1 = anclaje al final de bow_draw).
func _print_draw_arm(p: CombatPose, a: Object) -> void:
	var neck := p.bone_world("mixamorig_Neck")
	var top := p.bone_world("mixamorig_HeadTop_End")
	var elbow := p.bone_world("mixamorig_RightForeArm")
	var wrist := p.bone_world("mixamorig_RightHand")
	var pts := Geometry3D.get_closest_points_between_segments(elbow, wrist, neck, top)
	var pull := p.bone_world("mixamorig_LeftHand").distance_to(
		(p.bone_world("mixamorig_RightHandIndex2") + p.bone_world("mixamorig_RightHandMiddle2")) * 0.5)
	# Dedos de la cuerda contra el cuello (cápsula de 6 cm de cuello a cabeza).
	var fingers := (p.bone_world("mixamorig_RightHandIndex2") + p.bone_world("mixamorig_RightHandMiddle2")) * 0.5
	var on_neck := Geometry3D.get_closest_point_to_segment(fingers, neck, p.bone_world("mixamorig_Head"))
	print("%s %.2f  antebrazo-cabeza %.3f m  dedos-cuello %.3f m  mano-mano %.3f m  flex %.2f" % [a.clip,
		a.time, pts[0].distance_to(pts[1]) - 0.11, fingers.distance_to(on_neck) - 0.06, pull, a.bow_flex])


var ragdoll: Ragdoll
## El cuerpo se mueve como lo movería PlayerCombat (para ver si los pies patinan).
var body_offset: Vector3 = Vector3.ZERO


## Tambaleo: golpe de frente a los 0,2 s y otro desde la izquierda a los 1,2 s (0,55 s cada uno,
## retrocediendo 0,67 m como en el juego).
func _drive_stagger(t: float) -> void:
	pose.motion = BodyMotion.STAGGER
	pose.motion_travel = BodyMotion.stagger_travel
	pose.motion_distance = 0.67
	pose.motion_power = 1.0
	var hits := [[0.2, Vector3(0, 0, -1)], [1.2, Vector3(-0.8, 0, -0.6)]]
	pose.motion_x = -1.0
	for h in hits:
		var x: float = (t - h[0]) / 0.55
		if x >= 0.0 and x <= 1.0:
			pose.motion_x = x
			pose.motion_push = (h[1] as Vector3).normalized()
	_move_body(pose.motion_x, pose.motion_push, BodyMotion.stagger_travel(maxf(pose.motion_x, 0.0)) * 0.67)


## Paso atrás a los 0,3 s (0,42 s, 2,1 m) y otro a los 1,0 s.
func _drive_backstep(t: float) -> void:
	pose.motion = BodyMotion.BACKSTEP
	pose.motion_travel = BodyMotion.backstep_travel
	pose.motion_distance = 2.1
	pose.motion_power = 1.0
	pose.motion_x = -1.0
	for start in [0.3, 1.0]:
		var x: float = (t - start) / 0.42
		if x >= 0.0 and x <= 1.0:
			pose.motion_x = x
			pose.motion_push = Vector3(0, 0, -1)
	_move_body(pose.motion_x, pose.motion_push, BodyMotion.backstep_travel(maxf(pose.motion_x, 0.0)) * 2.1)


var _segment_base: Vector3 = Vector3.ZERO
var _in_segment: bool = false


func _move_body(x: float, push: Vector3, travelled: float) -> void:
	if x >= 0.0:
		if not _in_segment:
			_in_segment = true
			_segment_base = body_offset
		body_offset = _segment_base + push * travelled
	else:
		_in_segment = false


## Muerte: de pie, a los 0,4 s le llega el golpe de frente y cae como un muñeco.
func _drive_death(t: float) -> void:
	if ragdoll == null:
		ragdoll = Ragdoll.new()
		ragdoll.frame_node = model
		skel.add_child(ragdoll)
	if t >= 0.4 and not ragdoll.is_running():
		ragdoll.start(Vector3.ZERO, model.global_basis * Vector3(0.25, 0.1, -1.0).normalized() * 55.0)


## Prueba de dedos: las dos manos cerrándose en puño (sin arma), para ver el sentido del giro.
func _drive_fingers(t: float) -> void:
	pose.aim_weight = 0.0
	_placer = func(p: CombatPose) -> void:
		var k := clampf(t, 0.0, 1.0)
		if _frame_logged < 1:
			_frame_logged += 1
			for side in ["Left", "Right"]:
				var hf := p.hand_frame(side)
				var to_model := model.global_basis.inverse() * skel.global_basis
				print(side, " dir=", (to_model * hf.x).normalized(), " palma=", (to_model * hf.y).normalized())
		p.pose_fingers("Left", CombatPose.blend_fingers(ArcheryPose.OPEN, ArcheryPose.GRIP, k), 1.0)
		p.pose_fingers("Right", CombatPose.blend_fingers(ArcheryPose.OPEN, ArcheryPose.HOOK, k), 1.0)


var _frame_logged := 0


## Lanza: apunta, carga (brazo atrás), lanza y baja.
func _drive_throw(t: float) -> void:
	pose.aim_style = &"throw"
	pose.aim_dir = Vector3(0, 0.05, 1).normalized()
	pose.aim_weight = _ramp(t, 0.0, 0.3) * (1.0 - _ramp(t, 2.4, 2.8))
	pose.throw.draw = clampf((t - 0.5) / 0.9, 0.0, 1.0)
	pose.throw.throw_t = t - 1.7 if t >= 1.7 else -1.0
	stance_yaw = -25.0 * pose.aim_weight
	_placer = func(p: CombatPose) -> void:
		if right_item == null:
			return
		right_item.top_level = true
		var g := p.throw.grip_xform
		var dir := -g.basis.z
		var x := g.basis.x
		right_item.global_transform = Transform3D(Basis(x, dir, x.cross(dir)), g.origin + dir * 0.40)
		right_item.visible = pose.throw.throw_t < ThrowPose.RELEASE_AT and p.aim_weight > 0.05
