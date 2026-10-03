extends SceneTree

## Reorienta las animaciones de Mixamo de models/player/mixamo/combat/ (descargadas con un
## personaje de Character Creator: huesos CC_Base_*) al esqueleto del jugador (mixamorig_*), y
## las guarda como la librería "combat" en models/player/mixamo/combat_anims.tres.
##   godot --headless --path . --script res://tools/combat/retarget_mixamo.gd
##
## Los dos esqueletos no coinciden ni en nombres ni en reposo (el del jugador está en A, con los
## brazos ~52° abajo). Por eso no se copian las rotaciones locales: por cada hueso se toma cuánto
## ha girado en mundo respecto a su reposo en la animación original, y ese mismo giro se aplica
## al hueso del jugador partiendo de un reposo "igualado" (su reposo con el hueso apuntando
## donde apuntaba el de origen). La altura de la cadera se escala a la del jugador.

const SOURCE_DIR := "res://models/player/mixamo/combat/"
const OUT := "res://models/player/mixamo/combat_anims.tres"
const TARGET_SCENE := "res://scenes/character/character_model.tscn"
const FPS := 30.0
## Suavizado de la cabeza (ver la opción "smooth"): a 30 fps, sigma 2 borra el temblor y deja casi
## entero el cabeceo de cada paso.
const SMOOTH_HEAD := {"Head": 2.0}

## Animación de salida: [archivo, desde (s), hasta (s) o -1 = final, quitar desplazamiento
## horizontal de la cadera, en bucle (opcional), opciones (opcional)]. El archivo va respecto a
## SOURCE_DIR, o con su ruta res:// entera (ActorCore, también con esqueleto de Character Creator).
## Opciones: "mirror" la saca reflejada (izquierda por derecha); "height_from" toma la altura de
## la cadera de pie de otra descarga del mismo personaje (para las que no empiezan de pie);
## "offset" desplaza la cadera (m del origen, se escala con ella) para que dos clips que se
## mezclan compartan marco; "end_at_origin" la desplaza para que el clip acabe de pie en el origen
## (lo que recorre lo pone el código moviendo el cuerpo); "smooth" suaviza el giro de esos huesos
## ({hueso sin mixamorig_: sigma en fotogramas}), para capturas que tiemblan de un fotograma a otro.
const CLIPS := {
	"roll": ["Sprinting Forward Roll", 0.0, -1.0, true],
	# Lo que sigue a 1,5 s es volver andando al sitio.
	"dodge_back": ["Dodging Back", 0.35, 1.5, true],
	"death": ["Dying", 0.0, -1.0, false],
	# Sin la carrerilla ni los pasos de después; el desplazamiento lo pone el código.
	"throw": ["Goalie Throw", 0.3, 1.9, true],
	"bow_draw": ["Standing Draw Arrow", 0.0, -1.0, false],
	"bow_recoil": ["Standing Aim Recoil", 0.0, -1.0, false],
	"hit_react": ["Standing React Small From Front 02", 0.0, -1.0, false],
	# Pro Longbow Pack (Mixamo): el ciclo del arquero y andar apuntando.
	"bow_overdraw": ["Pro_Longbow_Pack/standing aim overdraw", 0.0, -1.0, false],
	"bow_idle": ["Pro_Longbow_Pack/standing idle 01", 0.0, -1.0, false],
	"bow_equip": ["Pro_Longbow_Pack/standing equip bow", 0.0, -1.0, false],
	"bow_disarm": ["Pro_Longbow_Pack/standing disarm bow", 0.0, -1.0, false],
	"bow_aim_walk_forward": ["Pro_Longbow_Pack/standing aim walk forward", 0.0, -1.0, true],
	"bow_aim_walk_back": ["Pro_Longbow_Pack/standing aim walk back", 0.0, -1.0, true],
	"bow_aim_walk_left": ["Pro_Longbow_Pack/standing aim walk left", 0.0, -1.0, true],
	"bow_aim_walk_right": ["Pro_Longbow_Pack/standing aim walk right", 0.0, -1.0, true],
	# Espada a una mano: combo de tres tajos (MeleeMoveset lo parte en golpes) y pesado.
	"sword_combo": ["melee/one_handed_sword_combo_light", 0.0, -1.0, true],
	"sword_heavy": ["melee/one_handed_sword_slash_heavy", 0.0, -1.0, true],
	# ActorCore: paseo relajado (el ciclo; son 3 pasos dobles que cierran el bucle).
	"walk_relaxed": ["res://models/player/actorcore/walk_relaxed/walk_relaxed_loop", 0.0, -1.0, true, true],
	# Lisiado (PlayerCombat, canal "cripple"): cojera con la pierna derecha mala y su espejo, y
	# arrastrarse por el suelo con las piernas muertas. En las descargas la cabeza tiembla respecto
	# al cuello (saltos de 3-7° de un fotograma a otro): se suaviza, conservando el cabeceo del paso.
	"injured_idle": ["injury/Injured Idle", 0.0, -1.0, true, true, {"smooth": SMOOTH_HEAD}],
	"injured_walk": ["injury/Injured Walk", 0.0, -1.0, true, true, {"smooth": SMOOTH_HEAD}],
	"injured_walk_back": ["injury/Injured Walk Backwards", 0.0, -1.0, true, true, {"smooth": SMOOTH_HEAD}],
	"injured_idle_mirror": ["injury/Injured Idle", 0.0, -1.0, true, true, {"mirror": true, "smooth": SMOOTH_HEAD}],
	"injured_walk_mirror": ["injury/Injured Walk", 0.0, -1.0, true, true, {"mirror": true, "smooth": SMOOTH_HEAD}],
	"injured_walk_back_mirror": ["injury/Injured Walk Backwards", 0.0, -1.0, true, true,
		{"mirror": true, "smooth": SMOOTH_HEAD}],
	"crawl": ["injury/Zombie Crawl", 0.0, -1.0, true, true,
		{"height_from": "injury/Injured Idle", "smooth": SMOOTH_HEAD}],
	# Escalada (ClimbController). Subir y bajar son ciclos en el sitio y conservan el vaivén de la
	# cadera (si no, las manos patinarían por la pared). Bajar viene 1,36 m más alto y 0,10 m más
	# lejos de la pared que subir: se lleva al marco de subir para mezclarlas sin saltos. Coronar
	# acaba de pie en el origen. Ninguna empieza de pie: la escala sale de una que sí.
	"climb_up": ["res://models/player/mixamo/climbing/Climbing Up Wall", 0.0, -1.0, false, true,
		{"height_from": "Dying"}],
	"climb_down": ["res://models/player/mixamo/climbing/Climbing Down Wall", 0.0, -1.0, false, true,
		{"height_from": "Dying", "offset": Vector3(0.0, -1.36, -0.098)}],
	"climb_top": ["res://models/player/mixamo/climbing/Climbing To Top", 0.0, -1.0, false, false,
		{"height_from": "Dying", "end_at_origin": true}],
	# De lado: Braced Hang Shimmy va hacia la izquierda del personaje y viene 0,58 m más alto y
	# 0,19 m más lejos de la pared que subir; la derecha es su espejo.
	"climb_left": ["res://models/player/mixamo/climbing/Braced Hang Shimmy", 0.0, -1.0, false, true,
		{"height_from": "Dying", "offset": Vector3(0.0, -0.58, -0.19)}],
	"climb_right": ["res://models/player/mixamo/climbing/Braced Hang Shimmy", 0.0, -1.0, false, true,
		{"height_from": "Dying", "offset": Vector3(0.0, -0.58, -0.19), "mirror": true}],
}

## Hueso del jugador ← hueso de origen.
var MAP := {
	"Hips": "CC_Base_Hip", "Spine": "CC_Base_Waist", "Spine1": "CC_Base_Spine01",
	"Spine2": "CC_Base_Spine02", "Neck": "CC_Base_NeckTwist01", "Head": "CC_Base_Head",
}

## Para igualar reposos: [hueso del jugador, su hijo, hijo de origen correspondiente].
var ALIGN := [
	["Hips", "Spine", "CC_Base_Waist"], ["Spine", "Spine1", "CC_Base_Spine01"],
	["Spine1", "Spine2", "CC_Base_Spine02"], ["Spine2", "Neck", "CC_Base_NeckTwist01"],
	["Neck", "Head", "CC_Base_Head"],
]


func _initialize() -> void:
	for side in [["Left", "L"], ["Right", "R"]]:
		var m: String = side[0]
		var c: String = side[1]
		MAP["%sShoulder" % m] = "CC_Base_%s_Clavicle" % c
		MAP["%sArm" % m] = "CC_Base_%s_Upperarm" % c
		MAP["%sForeArm" % m] = "CC_Base_%s_Forearm" % c
		MAP["%sHand" % m] = "CC_Base_%s_Hand" % c
		MAP["%sUpLeg" % m] = "CC_Base_%s_Thigh" % c
		MAP["%sLeg" % m] = "CC_Base_%s_Calf" % c
		MAP["%sFoot" % m] = "CC_Base_%s_Foot" % c
		MAP["%sToeBase" % m] = "CC_Base_%s_ToeBase" % c
		ALIGN.append(["%sShoulder" % m, "%sArm" % m, "CC_Base_%s_Upperarm" % c])
		ALIGN.append(["%sArm" % m, "%sForeArm" % m, "CC_Base_%s_Forearm" % c])
		ALIGN.append(["%sForeArm" % m, "%sHand" % m, "CC_Base_%s_Hand" % c])
		ALIGN.append(["%sHand" % m, "%sHandMiddle1" % m, "CC_Base_%s_Mid1" % c])
		ALIGN.append(["%sUpLeg" % m, "%sLeg" % m, "CC_Base_%s_Calf" % c])
		ALIGN.append(["%sLeg" % m, "%sFoot" % m, "CC_Base_%s_Foot" % c])
		ALIGN.append(["%sFoot" % m, "%sToeBase" % m, "CC_Base_%s_ToeBase" % c])
		for finger in [["Thumb", "Thumb"], ["Index", "Index"], ["Middle", "Mid"], ["Ring", "Ring"], ["Pinky", "Pinky"]]:
			for k in [1, 2, 3]:
				MAP["%sHand%s%d" % [m, finger[0], k]] = "CC_Base_%s_%s%d" % [c, finger[1], k]
			ALIGN.append(["%sHand%s1" % [m, finger[0]], "%sHand%s2" % [m, finger[0]], "CC_Base_%s_%s2" % [c, finger[1]]])
			ALIGN.append(["%sHand%s2" % [m, finger[0]], "%sHand%s3" % [m, finger[0]], "CC_Base_%s_%s3" % [c, finger[1]]])
	_run.call_deferred()


func _run() -> void:
	var target: Node3D = load(TARGET_SCENE).instantiate()
	root.add_child(target)
	var tskel: Skeleton3D = target.get_node("Armature/Skeleton3D")
	await process_frame
	var library := AnimationLibrary.new()
	for clip_name in CLIPS:
		var clip: Array = CLIPS[clip_name]
		var anim := await _retarget(clip, target, tskel)
		if anim != null:
			library.add_animation(clip_name, anim)
			print("retargeted %s ← %s (%.2f s, %d pistas)" % [clip_name, clip[0], anim.length, anim.get_track_count()])
	var err := ResourceSaver.save(library, OUT)
	print("saved %s (%d)" % [OUT, err])
	quit()


## Rotación (sin escala) de un transform.
static func _rot(t: Transform3D) -> Basis:
	return t.basis.orthonormalized()


static func _arc(from: Vector3, to: Vector3) -> Basis:
	var a := from.normalized()
	var b := to.normalized()
	var axis := a.cross(b)
	var s := axis.length()
	if s < 1e-6:
		return Basis.IDENTITY if a.dot(b) > 0.0 else Basis(Vector3.UP, PI)
	return Basis(axis / s, atan2(s, a.dot(b)))


func _retarget(clip: Array, target: Node3D, tskel: Skeleton3D) -> Animation:
	var file: String = clip[0] if String(clip[0]).begins_with("res://") else SOURCE_DIR + clip[0]
	var source: Node3D = load(file + ".fbx").instantiate()
	root.add_child(source)
	var sskel: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
	var src_anim := player.get_animation(player.get_animation_list()[0])
	player.play(player.get_animation_list()[0])
	player.pause()

	var to_tmodel := target.global_transform.affine_inverse() * tskel.global_transform
	var tsk_rot := _rot(to_tmodel)
	var smodel := source.global_transform.affine_inverse()

	# Reposo de origen, con el esqueleto en su pose de enlace.
	var src_rest := {}
	for i in sskel.get_bone_count():
		src_rest[sskel.get_bone_name(i)] = smodel * sskel.global_transform * sskel.get_bone_global_rest(i)
	# Orientación: el personaje de origen puede mirar hacia otro lado que el jugador.
	var tl := _tpos(tskel, to_tmodel, "LeftUpLeg") - _tpos(tskel, to_tmodel, "RightUpLeg")
	var sl: Vector3 = (src_rest["CC_Base_L_Thigh"] as Transform3D).origin - (src_rest["CC_Base_R_Thigh"] as Transform3D).origin
	var yaw_fix := _arc(Vector3(sl.x, 0, sl.z), Vector3(tl.x, 0, tl.z))

	# Reposo del jugador y reposo "igualado" (cada hueso apuntando como el de origen).
	var t_rest_world := {}
	for i in tskel.get_bone_count():
		t_rest_world[tskel.get_bone_name(i)] = to_tmodel * tskel.get_bone_global_rest(i)
	var t_ref := {}
	for key in MAP:
		t_ref[key] = _rot(t_rest_world["mixamorig_" + key])
	for entry in ALIGN:
		var tb: String = "mixamorig_" + entry[0]
		var tc: String = "mixamorig_" + entry[1]
		var sb: String = MAP[entry[0]]
		var sc: String = entry[2]
		if not t_rest_world.has(tc) or not src_rest.has(sc):
			continue
		var tdir: Vector3 = (t_rest_world[tc] as Transform3D).origin - (t_rest_world[tb] as Transform3D).origin
		var sdir: Vector3 = yaw_fix * ((src_rest[sc] as Transform3D).origin - (src_rest[sb] as Transform3D).origin)
		t_ref[entry[0]] = _arc(tdir, sdir) * _rot(t_rest_world[tb])

	# Altura de la cadera de pie del jugador: la de su "idle", no la del reposo (el reposo del
	# rig tiene la cadera a 12 cm del suelo).
	var hips_rest_h := _standing_hips_height(target, tskel, to_tmodel)
	var src_hips_h: float = (src_rest["CC_Base_Hip"] as Transform3D).origin.y
	# El reposo de origen puede estar en otra escala que la animación: se mide la cadera en el
	# primer fotograma, que en todas estas empieza de pie.
	var opts: Dictionary = clip[5] if clip.size() > 5 else {}
	if opts.has("height_from"):
		src_hips_h = await _first_hips_height(opts.height_from)
	else:
		player.seek(clip[1], true)
		sskel.force_update_all_bone_transforms()
		var first_hips := smodel * sskel.global_transform * sskel.get_bone_global_pose(sskel.find_bone("CC_Base_Hip"))
		if first_hips.origin.y > 0.3:
			src_hips_h = first_hips.origin.y
	var scale := hips_rest_h / maxf(src_hips_h, 0.01)
	# Espejo: reflejo por el plano medio del jugador (normal = de la cadera derecha a la izquierda).
	# Cada hueso toma el giro reflejado de su pareja del otro lado, corregido para que en reposo
	# coincida con su propio reposo.
	var mirror: bool = opts.get("mirror", false)
	var reflect := Basis.IDENTITY
	var partner := {}
	var mirror_fix := {}
	if mirror:
		var n := tl.normalized()
		reflect = Basis(Vector3.RIGHT - 2.0 * n * n.x, Vector3.UP - 2.0 * n * n.y, Vector3.BACK - 2.0 * n * n.z)
		for i in tskel.get_bone_count():
			var bone_name := tskel.get_bone_name(i)
			var other := bone_name.replace("Left", "#").replace("Right", "Left").replace("#", "Right")
			var j := tskel.find_bone(other)
			partner[i] = j if j >= 0 else i
		for i in tskel.get_bone_count():
			var j: int = partner[i]
			var rest_i := _rot(t_rest_world[tskel.get_bone_name(i)])
			var rest_j := _rot(t_rest_world[tskel.get_bone_name(j)])
			mirror_fix[j] = (reflect * rest_i * reflect).inverse() * rest_j

	var from: float = clip[1]
	var to: float = src_anim.length if clip[2] < 0.0 else clip[2]
	var anim := Animation.new()
	anim.length = to - from
	if clip.size() > 4 and clip[4]:
		anim.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	var order: Array = []
	for i in tskel.get_bone_count():
		var name := tskel.get_bone_name(i).trim_prefix("mixamorig_")
		if MAP.has(name):
			order.append(i)
			var track := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track, "Armature/Skeleton3D:mixamorig_" + name)
			tracks[i] = track
	var hips_pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_pos_track, "Armature/Skeleton3D:mixamorig_Hips")
	var start_xz := Vector3.ZERO
	var offset: Vector3 = opts.get("offset", Vector3.ZERO) * scale
	var hips_keys: Array = []

	var frames := int(ceil(anim.length * FPS))
	for f in frames + 1:
		var t := minf(from + f / FPS, to)
		player.seek(t, true)
		sskel.force_update_all_bone_transforms()
		# Giro en mundo (marco del modelo) de cada hueso del jugador en este fotograma.
		var world := {}
		for i in tskel.get_bone_count():
			var bone_name := tskel.get_bone_name(i)
			var key := bone_name.trim_prefix("mixamorig_")
			var parent := tskel.get_bone_parent(i)
			if MAP.has(key):
				var sidx := sskel.find_bone(MAP[key])
				var s_now := _rot(smodel * sskel.global_transform * sskel.get_bone_global_pose(sidx))
				var s_rest := _rot(src_rest[MAP[key]])
				var delta := yaw_fix * s_now * s_rest.inverse() * yaw_fix.inverse()
				world[i] = (delta * t_ref[key]).orthonormalized()
			else:
				var parent_world: Basis = world[parent] if parent >= 0 else tsk_rot
				world[i] = (parent_world * tskel.get_bone_rest(i).basis.orthonormalized()).orthonormalized()
		if mirror:
			var mirrored := {}
			for i in tskel.get_bone_count():
				var j: int = partner[i]
				mirrored[j] = (reflect * (world[i] as Basis) * reflect * (mirror_fix[j] as Basis)).orthonormalized()
			world = mirrored
		for i in order:
			var parent := tskel.get_bone_parent(i)
			var parent_world: Basis = world[parent] if parent >= 0 else tsk_rot
			var local: Quaternion = (parent_world.inverse() * (world[i] as Basis)).get_rotation_quaternion()
			anim.rotation_track_insert_key(tracks[i], t - from, local)
		# Cadera: posición de origen escalada, pasada al espacio del esqueleto del jugador.
		var s_hips := smodel * sskel.global_transform * sskel.get_bone_global_pose(sskel.find_bone("CC_Base_Hip"))
		var p: Vector3 = yaw_fix * s_hips.origin * scale + offset
		if f == 0:
			start_xz = Vector3(p.x, 0, p.z)
		if clip[3]:
			p -= Vector3(p.x, 0, p.z) - start_xz
		if mirror:
			p = reflect * p
		hips_keys.append([t - from, p])
	# Acabar de pie en el origen: la cadera del último fotograma va sobre él, a la altura de pie.
	if opts.get("end_at_origin", false):
		var last: Vector3 = hips_keys[-1][1]
		var shift := Vector3(last.x, last.y - hips_rest_h, last.z)
		for key in hips_keys:
			key[1] -= shift
	for key in hips_keys:
		anim.position_track_insert_key(hips_pos_track, key[0], to_tmodel.affine_inverse() * (key[1] as Vector3))
	var smooth: Dictionary = opts.get("smooth", {})
	for bone_name in smooth:
		var bone := tskel.find_bone("mixamorig_" + bone_name)
		if tracks.has(bone):
			_smooth_track(anim, tracks[bone], float(smooth[bone_name]), anim.loop_mode != Animation.LOOP_NONE)
	source.queue_free()
	await process_frame
	return anim


## Media gaussiana del giro de una pista de rotación (una clave por fotograma), [sigma] en
## fotogramas. En bucle los extremos miran al otro lado del ciclo (la última clave repite la
## primera); si no, se quedan con la clave del borde.
static func _smooth_track(anim: Animation, track: int, sigma: float, loop: bool) -> void:
	var count := anim.track_get_key_count(track)
	var keys: Array[Quaternion] = []
	for k in count:
		keys.append(anim.track_get_key_value(track, k))
	var period := count - 1 if loop else count
	var radius := ceili(sigma * 3.0)
	for k in count:
		var center := keys[k]
		var sum := Quaternion(0.0, 0.0, 0.0, 0.0)
		for o in range(-radius, radius + 1):
			var q := keys[posmod(k + o, period) if loop else clampi(k + o, 0, count - 1)]
			if q.dot(center) < 0.0:
				q = -q
			sum += q * exp(-0.5 * (o / sigma) * (o / sigma))
		anim.track_set_key_value(track, k, sum.normalized())


## Altura de la cadera (en el marco del modelo de origen) en el primer fotograma de [file].
func _first_hips_height(file: String) -> float:
	var source: Node3D = load(SOURCE_DIR + file + ".fbx").instantiate()
	root.add_child(source)
	var sskel: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
	player.play(player.get_animation_list()[0])
	player.pause()
	player.seek(0.0, true)
	sskel.force_update_all_bone_transforms()
	var hips := source.global_transform.affine_inverse() * sskel.global_transform \
		* sskel.get_bone_global_pose(sskel.find_bone("CC_Base_Hip"))
	source.queue_free()
	await process_frame
	return hips.origin.y


func _standing_hips_height(target: Node3D, tskel: Skeleton3D, to_tmodel: Transform3D) -> float:
	var ap: AnimationPlayer = target.get_node("AnimationPlayer")
	ap.play("idle")
	ap.seek(0.0, true)
	ap.pause()
	tskel.force_update_all_bone_transforms()
	var h := (to_tmodel * tskel.get_bone_global_pose(tskel.find_bone("mixamorig_Hips"))).origin.y
	ap.stop()
	tskel.reset_bone_poses()
	return h


func _tpos(tskel: Skeleton3D, to_tmodel: Transform3D, bone: String) -> Vector3:
	return (to_tmodel * tskel.get_bone_global_rest(tskel.find_bone("mixamorig_" + bone))).origin
