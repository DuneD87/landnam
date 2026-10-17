class_name PlayerRemains
extends Node3D

## Lo que queda del jugador al que devora una fiera (Devouring), que se queda en el mundo: una copia
## de su cuerpo tal como ha caído. El esqueleto va en la pose final del muñeco de trapo (con todo lo
## demás que lo mueve: las proporciones del cuerpo, las manos), y las mallas con piel van tal como
## estaban (ya cortadas si había perdido algún miembro, con las tapas de los muñones), con la sangre
## que llevaba encima (BloodStains). Mientras se lo comen:
##   - sever(): se le arranca un miembro con su propio Dismemberment; lo arrancado cae y se queda
##     (SeveredLimb.keep), y el muñón echa sangre a borbotones un rato;
##   - open_torso(): se le abre el vientre y el pecho (la canal: HumanCarcass);
##   - spill_guts(): las vísceras salen al suelo (GutPile);
##   - tug(): el cuerpo da un tirón hacia la fiera a cada bocado y vuelve.
## seal() lo deja quieto para siempre (sin Dismemberment, que cada fotograma mira las mallas).
## Antes de build() es solo un ancla: feed_point() sigue al muñeco del jugador, para que la fiera
## vaya hacia él mientras cae. Va con el origen flotante, y caben MAX_ALIVE: al pasar, se va el más
## viejo con lo que se le arrancó.
##
## Se guarda en la partida (save_category "remains"): no las mallas, sino cómo rehacerlas. Su aspecto
## y lo que llevaba puesto, la pose, los cortes (los de antes y los de la fiera), si está abierto en
## canal, las vísceras y dónde quedó cada miembro arrancado. Al cargar se rehace (_rebuild) con un
## cuerpo de personaje que se viste igual, se copia y se tira. Los que se hicieron después de guardar
## se van al cargar (discard_on_load).

const GROUP := &"player_remains"
const MAX_ALIVE := 8
const SCENE_PATH := "res://scenes/combat/player_remains.tscn"
## El cuerpo con el que se rehacen al cargar, y lo que se espera a que se vista (s).
const MODEL_PATH := "res://scenes/character/character_model.tscn"
const DRESS_TIMEOUT := 10.0
const TORSO_BONE := &"mixamorig_Spine1"
const CHEST_BONE := &"mixamorig_Spine2"
const HEAD_BONE := &"mixamorig_Head"
const ROOT_BONE := &"mixamorig_Hips"
const LIMBS: Array[StringName] = [&"left_arm", &"right_arm", &"left_leg", &"right_leg"]
## Lo que sobresale de los huesos la carne que se muerde (m): el tronco tumbado y un miembro; y su
## grueso, para morderlos por donde caiga la boca (bite_surface).
const TORSO_LIFT := 0.11
const LIMB_LIFT := 0.04
const TORSO_RADIUS := 0.14
const LIMB_RADIUS := 0.055
## Lo que lleva en la boca la fiera un miembro que acaba de arrancar (s, entre los dos).
const HOLD_TIME := Vector2(1.2, 1.9)
## Un tirón: lo que tarda en dar el tirón y en volver (s).
const TUG_IN := 0.05
const TUG_TIME := 0.45
## Borbotones de un muñón: cada cuánto (s), su vida media (s) y por debajo de qué fuerza se acaban.
const STUMP_PULSE := 0.32
const STUMP_HALF_LIFE := 3.0
const STUMP_STOP := 0.08
## El charco bajo cada muñón (m) y lo que tarda en extenderse (s).
const STUMP_POOL := Vector2(0.5, 3.0)
## Las vísceras, a la medida de un cuerpo de este radio (m; GutPile).
const GUTS_RADIUS := 0.28

static var _alive: Array[PlayerRemains] = []

var skeleton: Skeleton3D
var dismemberment: Dismemberment
var built := false
## Ya despiezado (o dejado a medias): la fiera come un rato más y se va (FeedState).
var devoured := false
## Lo arrancado (SeveredLimb), que se queda con los restos.
var limbs: Array = []
## Abierto en canal (open_torso): el hueco (HumanCarcass.wound). Vacío si no.
var wound := {}
## Para la partida guardada (GameManager).
var entity_id := ""
var save_category := "remains"
var discard_on_load := true

var _ragdoll: Ragdoll
var _gravity := Vector3.ZERO
## Giro y sitio de cada hueso en la pose en que quedó: los tirones vuelven a ella.
var _rotations: Array[Quaternion] = []
var _positions: Array[Vector3] = []
## Hueso → tirón en curso {axis (en el marco del hueso), angle, time}.
var _tugs := {}
## Tirón del cuerpo entero (la pelvis): {offset (en el marco de su padre), time}.
var _shove := {}
## Muñones que sangran: {cut, strength, pulse}.
var _stumps: Array[Dictionary] = []
## El miembro que trabaja la fiera ({bone, tip, name}); vacío, el tronco.
var _focus := {}
## Las FeedState de las fieras que vienen a comérselo; la primera trabaja el _focus.
var _feeders: Array = []
## Los brazos y las piernas que ya no tiene (zona → true).
var _lost := {}
## Hueso que se está arrancando → la FeedState que se lo llevará en la boca al caer.
var _grippers := {}
## Para rehacerlo al cargar: su aspecto y lo puesto ({appearance, armor: [{scene, head}]}), los
## cortes de antes de morir y los de la fiera ({name, t, origin, normal, drop}).
var _look := {}
var _cuts: Array[Dictionary] = []
## Rehaciéndolo de la partida: lo guardado (con los miembros por colocar, por hueso del corte).
var _restoring := {}
## Los materiales con la luz del planeta de lo que lleva puesto: copias propias, registradas en él.
var _planet_materials: Array[ShaderMaterial] = []
var _planet_core: Node


## Un ancla en [host], en el marco [at] del cuerpo del jugador (+Z adelante), que sigue a [ragdoll]
## hasta build().
static func spawn(host: Node, at: Transform3D, ragdoll: Ragdoll) -> PlayerRemains:
	var remains := (load(SCENE_PATH) as PackedScene).instantiate() as PlayerRemains
	remains.name = "PlayerRemains"
	remains.entity_id = "player_remains_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	remains._ragdoll = ragdoll
	host.add_child(remains, true)
	remains.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	return remains


func _ready() -> void:
	add_to_group(&"floating_origin")
	add_to_group(GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	set_process(false)
	for i in range(_alive.size() - 1, -1, -1):
		if not is_instance_valid(_alive[i]):
			_alive.remove_at(i)
	_alive.append(self)
	while _alive.size() > MAX_ALIVE:
		_alive.pop_front().queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for limb in limbs:
			if is_instance_valid(limb):
				(limb as Node).queue_free()
		if _planet_core != null and is_instance_valid(_planet_core):
			for material in _planet_materials:
				_planet_core.unregister_planet_material(material)


## Copia el cuerpo de [source] (el esqueleto del jugador) donde está, en la pose [pose] (la local de
## cada hueso con todos los modificadores; ver Devouring). [frame] es el marco del cuerpo (+Z
## adelante, hacia dónde doblan codos y rodillas al caer lo arrancado); [cutter], el Dismemberment
## del jugador, del que aprovecha lo ya leído de las mallas; [gravity], la de allí; [lost], los
## brazos y las piernas que ya había perdido.
func build(source: Skeleton3D, pose: Array[Transform3D], frame: Node3D, cutter: Dismemberment,
		gravity: Vector3, lost: Array[StringName] = []) -> void:
	if built:
		return
	built = true
	_gravity = gravity
	for zone in lost:
		_lost[zone] = true
	global_transform = Transform3D(frame.global_basis.orthonormalized(), frame.global_position)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for b in source.get_bone_count():
		skeleton.add_bone(source.get_bone_name(b))
	for b in source.get_bone_count():
		skeleton.set_bone_parent(b, source.get_bone_parent(b))
		skeleton.set_bone_rest(b, source.get_bone_rest(b))
	add_child(skeleton)
	skeleton.global_transform = source.global_transform
	for b in pose.size():
		var rotation := pose[b].basis.get_rotation_quaternion()
		skeleton.set_bone_pose_position(b, pose[b].origin)
		skeleton.set_bone_pose_rotation(b, rotation)
		skeleton.set_bone_pose_scale(b, pose[b].basis.get_scale())
		_positions.append(pose[b].origin)
		_rotations.append(rotation)
	if _restoring.is_empty():
		_record(source, cutter)
	var body: MeshInstance3D = null
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var inst := node as MeshInstance3D
		# FirstPersonBody es Mesh_0 con la cabeza plegada: solo lo ve la cámara en primera persona.
		if inst.skin == null or inst.mesh == null or not _shown(inst, source) or inst.name == &"FirstPersonBody":
			continue
		var copy := _copy_mesh(inst)
		skeleton.add_child(copy)
		copy.transform = skeleton.global_transform.affine_inverse() * inst.global_transform
		if inst.name == &"Mesh_0":
			body = copy
	_copy_stains(source)
	dismemberment = Dismemberment.new()
	dismemberment.name = "Dismemberment"
	dismemberment.skeleton = skeleton
	if body != null:
		dismemberment.capped.append(body)
	dismemberment.frame_node = self
	dismemberment.gravity = gravity
	if cutter != null:
		dismemberment.world_mask = cutter.world_mask
		dismemberment.share_sources(cutter)
	dismemberment.limb_dropped.connect(_on_limb_dropped)
	add_child(dismemberment)
	_bind_planet_materials()


## Se ve (ella y lo que hay entre ella y el esqueleto [source]; el cuerpo entero puede estar escondido).
static func _shown(inst: Node3D, source: Node) -> bool:
	var node: Node = inst
	while node != null and node != source:
		if node is Node3D and not (node as Node3D).visible:
			return false
		node = node.get_parent()
	return true


## Lo que hace falta para rehacerlo al cargar: el aspecto del personaje, lo que lleva puesto (las
## piezas de armadura que cuelgan del esqueleto [source]) y los cortes de antes de morir ([cutter]).
func _record(source: Skeleton3D, cutter: Dismemberment) -> void:
	var character: CharacterData = GameManager.character
	_look.appearance = character.appearance.to_dict() if character != null and character.appearance != null else {}
	var armor := []
	for child in source.get_children():
		var data: Variant = child.get(&"item_data")
		if data is ItemData and (data as ItemData).scene_path != "":
			armor.append({scene = data.scene_path, head = data.armor_slot == ItemData.ArmorSlot.HEAD})
	_look.armor = armor
	if cutter != null:
		for c in cutter.cuts():
			_cuts.append({name = String(c.name), t = c.t, origin = _vec(c.origin), normal = _vec(c.normal), drop = false})


## Los materiales con la luz del planeta (los de la armadura, por el uniform planet_position o
## light_direction): cada copia lleva los suyos, registrados en el planeta del jugador. Si aún no hay
## planeta (cargando), se reintenta.
func _bind_planet_materials() -> void:
	if not _planet_materials.is_empty() or skeleton == null:
		return
	var player := GameManager.player
	var loader: Variant = player.get(&"planet") if player != null else null
	var core: Variant = loader.get(&"planet") if loader is Object and is_instance_valid(loader) else null
	if not (core is Node) or not (core as Node).has_method(&"register_planet_material"):
		get_tree().create_timer(1.0).timeout.connect(_bind_planet_materials)
		return
	_planet_core = core
	var copies := {}
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var inst := node as MeshInstance3D
		if inst.mesh == null:
			continue
		if _planet_lit(inst.material_override):
			inst.material_override = _planet_copy(inst.material_override, copies)
		for i in inst.mesh.get_surface_count():
			var material := inst.get_surface_override_material(i)
			if material == null:
				material = inst.mesh.surface_get_material(i)
			if _planet_lit(material):
				inst.set_surface_override_material(i, _planet_copy(material, copies))


func _planet_copy(material: Material, copies: Dictionary) -> ShaderMaterial:
	if not copies.has(material):
		var copy := material.duplicate() as ShaderMaterial
		copies[material] = copy
		_planet_materials.append(copy)
		_planet_core.register_planet_material(copy)
	return copies[material]


static func _planet_lit(material: Material) -> bool:
	var shader_material := material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return false
	for uniform in shader_material.shader.get_shader_uniform_list():
		if uniform.name == "planet_position" or uniform.name == "light_direction":
			return true
	return false


## Una copia de [inst] tal como la ve la cámara en tercera persona (en primera, el cuerpo y la
## cabeza solo dan sombra).
static func _copy_mesh(inst: MeshInstance3D) -> MeshInstance3D:
	var copy := MeshInstance3D.new()
	copy.name = inst.name
	copy.mesh = inst.mesh
	copy.skin = inst.skin
	copy.material_override = inst.material_override
	copy.material_overlay = inst.material_overlay
	for i in inst.get_surface_override_material_count():
		copy.set_surface_override_material(i, inst.get_surface_override_material(i))
	for i in inst.get_blend_shape_count():
		copy.set_blend_shape_value(i, inst.get_blend_shape_value(i))
	for property in inst.get_property_list():
		var key: String = property.name
		if key.begins_with("instance_shader_parameters/"):
			copy.set(key, inst.get(key))
	var shadow := inst.cast_shadow
	if inst.has_meta(&"camera_cast_shadow"):
		shadow = inst.get_meta(&"camera_cast_shadow")
	if shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	copy.cast_shadow = shadow
	# Con la capa de BloodStains si ya se había manchado.
	copy.layers = inst.layers
	copy.lod_bias = inst.lod_bias
	copy.extra_cull_margin = inst.extra_cull_margin
	copy.custom_aabb = inst.custom_aabb
	for meta in [Dismemberment.NO_CUT_META, Dismemberment.CAP_META]:
		if inst.has_meta(meta):
			copy.set_meta(meta, inst.get_meta(meta))
	return copy


## La sangre que llevaba encima (BloodStains): sus manchas, en los mismos huesos.
func _copy_stains(source: Skeleton3D) -> void:
	var stains: Array = []
	for child in source.get_children():
		var holder := child as BoneAttachment3D
		if holder == null or not String(holder.name).begins_with(BloodStains.HOLDER_PREFIX):
			continue
		var copy := holder.duplicate() as BoneAttachment3D
		skeleton.add_child(copy)
		for decal in copy.get_children():
			if decal is Decal:
				stains.append(decal)
	skeleton.set_meta(BloodStains.META_STAINS, stains)


# ---------------------------------------------------------------------------------------------
# Las fieras


func add_feeder(state: FeedState) -> void:
	if not _feeders.has(state):
		_feeders.append(state)


func remove_feeder(state: FeedState) -> void:
	_feeders.erase(state)


## Las fieras que se lo están comiendo ahora mismo (con la boca en él).
func eating() -> Array[FeedState]:
	var out: Array[FeedState] = []
	for state in _feeders:
		if is_instance_valid(state) and (state as FeedState).is_eating():
			out.append(state)
	return out


## La primera fiera que está comiendo (la que trabaja el miembro que toca), o null.
func main_feeder() -> FeedState:
	for state in _feeders:
		if is_instance_valid(state) and (state as FeedState).is_eating():
			return state
	return null


## Dónde se trabaja (mundo): el miembro que toca o el tronco. Antes de build(), el muñeco.
func feed_point() -> Vector3:
	if not built:
		return _ragdoll.center() if is_instance_valid(_ragdoll) and _ragdoll.is_running() else global_position
	return _spot_point(_spots()[0])


## Lo que muerde [state] (mundo, sobre la carne): la primera fiera, donde se trabaja (feed_point);
## cada una de las demás, otra de las partes que quedan (el tronco, los otros miembros).
func bite_point(state: FeedState) -> Vector3:
	if not built:
		return feed_point()
	return _spot_point(_spot(state))


## El hueso de lo que muerde [state] (para el tirón).
func bite_bone(state: FeedState) -> StringName:
	return _spot(state).bone if built else TORSO_BONE


## Donde toca la carne de lo que muerde [state] la boca que llega desde [mouth] (mundo): el punto de
## su superficie (la del tronco o el miembro, como un cilindro alrededor de sus huesos) más cercano.
func bite_surface(state: FeedState, mouth: Vector3) -> Vector3:
	if not built or mouth == Vector3.INF:
		return bite_point(state)
	var spot := _spot(state)
	# Abierto en canal, el tronco se come por dentro.
	if not wound.is_empty() and spot.bone == TORSO_BONE:
		return wound_point()
	var axis := _axis_point(spot, mouth)
	if axis == Vector3.INF:
		return bite_point(state)
	var out := mouth - axis
	if out.length_squared() < 1e-8:
		out = _up()
	return axis + out.normalized() * float(spot.radius)


## Dentro del hueco de la canal (mundo): en medio, algo por debajo de la abertura. INF si no está abierto.
func wound_point() -> Vector3:
	if wound.is_empty() or not built:
		return Vector3.INF
	var center: Vector3 = wound.center
	var inside := Vector3(center.x, center.y, lerpf(center.z, float(wound.front), 0.3))
	return skeleton.global_transform * (skeleton.get_bone_global_pose(wound.bone) * (wound.body_bind as Transform3D) * inside)


## Lo lejos que queda [mouth] (mundo) de la carne de lo que muerde [state] (m): positivo fuera,
## negativo hundida en ella.
func bite_gap(state: FeedState, mouth: Vector3) -> float:
	if not built:
		return mouth.distance_to(feed_point())
	var spot := _spot(state)
	var axis := _axis_point(spot, mouth)
	if axis == Vector3.INF:
		return mouth.distance_to(bite_point(state))
	return mouth.distance_to(axis) - float(spot.radius)


## El punto del eje de [spot] (entre sus huesos a y b) más cercano a [point], o INF.
func _axis_point(spot: Dictionary, point: Vector3) -> Vector3:
	var a := skeleton.find_bone(spot.a)
	var b := skeleton.find_bone(spot.b)
	if a < 0 or b < 0:
		return Vector3.INF
	var xf := skeleton.global_transform
	return Geometry3D.get_closest_point_to_segment(point, xf * skeleton.get_bone_global_pose(a).origin,
		xf * skeleton.get_bone_global_pose(b).origin)


func _spot(state: FeedState) -> Dictionary:
	var spots := _spots()
	return spots[maxi(_feeders.find(state), 0) % spots.size()]


## Las partes que se pueden morder, la que se trabaja primero: {bone (el del tirón), tip (hasta
## dónde), t (dónde, a lo largo), lift (encima), a y b (los huesos de su eje), radius (su grueso)}.
func _spots() -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	var focus: StringName = _focus.get("name", &"")
	if focus != &"":
		spots.append(_limb_spot(focus))
	spots.append({bone = TORSO_BONE, tip = CHEST_BONE, t = 0.3, lift = TORSO_LIFT, a = ROOT_BONE, b = CHEST_BONE,
		radius = TORSO_RADIUS})
	for zone in LIMBS:
		var bone := limb_bone(zone, true)
		if not _lost.has(zone) and bone != focus:
			spots.append(_limb_spot(bone))
	return spots


static func _limb_spot(bone: StringName) -> Dictionary:
	var tip := StringName(Dismemberment.CUTTABLE[bone][0])
	return {bone = bone, tip = tip, t = 0.5, lift = LIMB_LIFT, a = bone, b = tip, radius = LIMB_RADIUS}


func _spot_point(spot: Dictionary) -> Vector3:
	var bone := skeleton.find_bone(spot.bone)
	var tip := skeleton.find_bone(spot.tip)
	if bone < 0 or tip < 0:
		return torso_point()
	return _segment_point(bone, tip, spot.t) + _up() * float(spot.lift)


func _up() -> Vector3:
	return -_gravity.normalized() if _gravity.length_squared() > 1e-6 else global_basis.y


## La fiera trabaja [zone] (un brazo o una pierna; ver limb_bone); vacío, el tronco.
func set_focus(zone: StringName, upper: bool) -> void:
	_focus = {}
	if zone == &"" or not built:
		return
	var bone_name := limb_bone(zone, upper)
	var bone := skeleton.find_bone(bone_name)
	var tip := skeleton.find_bone(String(Dismemberment.CUTTABLE[bone_name][0]))
	if bone >= 0 and tip >= 0:
		_focus = {bone = bone, tip = tip, name = bone_name}


# ---------------------------------------------------------------------------------------------
# Puntos del cuerpo


## El hueso por el que se arranca [zone] (un brazo o una pierna): el de arriba si [upper] (el brazo,
## el muslo), si no el de abajo (el antebrazo, la pierna). Como BodyDamage.sever_zone.
static func limb_bone(zone: StringName, upper: bool) -> StringName:
	var side := "Left" if String(zone).begins_with("left") else "Right"
	var part := ("Arm" if upper else "ForeArm") if String(zone).ends_with("arm") \
		else ("UpLeg" if upper else "Leg")
	return StringName("mixamorig_" + side + part)


func torso_point() -> Vector3:
	return bone_point(TORSO_BONE)


func head_point() -> Vector3:
	return bone_point(HEAD_BONE)


## Dónde está [bone_name] (mundo). Antes de build(), donde come la fiera.
func bone_point(bone_name: StringName) -> Vector3:
	if not built:
		return feed_point()
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## La mitad del tramo de [zone] que se arrancaría (ver limb_bone).
func limb_point(zone: StringName, upper: bool) -> Vector3:
	if not built:
		return feed_point()
	var bone_name := limb_bone(zone, upper)
	var bone := skeleton.find_bone(bone_name)
	var tip := skeleton.find_bone(String(Dismemberment.CUTTABLE[bone_name][0]))
	if bone < 0 or tip < 0:
		return torso_point()
	return _segment_point(bone, tip, 0.5)


func _segment_point(bone: int, tip: int, t: float) -> Vector3:
	var xf := skeleton.global_transform
	return (xf * skeleton.get_bone_global_pose(bone).origin).lerp(xf * skeleton.get_bone_global_pose(tip).origin, t)


# ---------------------------------------------------------------------------------------------
# Despiece


## Le arranca [zone] (un brazo o una pierna; ver limb_bone) tirando hacia [pull] (mundo); lo
## arrancado sale con [fling] (m/s) y se queda junto a los restos; si lo arranca [gripper] (una
## fiera), al caer se lo lleva en la boca un rato (FeedState.hold). [quiet]: sin sangre ni charco
## (lo que pasa a oscuras al saltarlo). Devuelve false si ya no le queda ese miembro.
func sever(zone: StringName, upper: bool, pull: Vector3, fling: Vector3, quiet := false,
		gripper: FeedState = null) -> bool:
	if not built or dismemberment == null:
		return false
	var bone_name := limb_bone(zone, upper)
	var bone := skeleton.find_bone(bone_name)
	var tip := skeleton.find_bone(String(Dismemberment.CUTTABLE[bone_name][0]))
	if bone < 0 or tip < 0:
		return false
	# El muñón se queda en ese hueso: sin el tirón que llevara.
	if _tugs.has(bone):
		_tugs.erase(bone)
		skeleton.set_bone_pose_rotation(bone, _rotations[bone])
	dismemberment.gravity = _gravity
	var c := dismemberment.cut(bone_name, _segment_point(bone, tip, 0.55), pull, fling)
	if c.is_empty():
		return false
	_lost[zone] = true
	_cuts.append({name = String(bone_name), t = c.t, origin = _vec(c.origin), normal = _vec(c.normal),
		drop = dismemberment.drop_parts})
	if _focus.get("bone", -1) == bone:
		_focus = {}
	if gripper != null:
		_grippers[bone] = gripper
	if quiet:
		return true
	var ends := dismemberment.stump(c)
	CombatFx.sever_burst(self, ends[0], ends[1])
	BloodPool.spawn(self, ends[0], _gravity, STUMP_POOL.x * randf_range(0.8, 1.2), STUMP_POOL.y,
		dismemberment.world_mask)
	_stumps.append({cut = c, strength = 1.0, pulse = 0.0})
	set_process(true)
	return true


## Lo abre en canal: el vientre y el pecho, sin piel ni ropa (Dismemberment.carve), y dentro la
## cavidad, la columna y las costillas rotas (HumanCarcass). Las vísceras salen aparte (spill_guts).
## Devuelve false si ya estaba abierto o no se puede.
func open_torso() -> bool:
	if not built or dismemberment == null or not wound.is_empty():
		return false
	var found := HumanCarcass.wound(skeleton, skeleton.get_node_or_null(^"Mesh_0") as MeshInstance3D)
	if found.is_empty():
		return false
	wound = found
	dismemberment.carve(wound)
	HumanCarcass.cavity(skeleton, wound)
	return true


## Le saca las vísceras al suelo, por el lado de [side] (horizontal, mundo).
func spill_guts(side: Vector3) -> void:
	if not built:
		return
	GutPile.spawn(self, torso_point(), side, _up(), GUTS_RADIUS)


## Un tirón de [bone_name] hacia [toward] (mundo) de [degrees] grados, que vuelve a la pose en
## TUG_TIME. Con [shift] (m), el cuerpo entero se mueve eso hacia allí y vuelve.
func tug(bone_name: StringName, toward: Vector3, degrees: float, shift := 0.0) -> void:
	if not built or toward.length_squared() < 1e-6:
		return
	var bone := skeleton.find_bone(bone_name)
	if bone < 0 or (dismemberment != null and dismemberment.is_lost(bone)):
		return
	var basis := (skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis).orthonormalized()
	# Los huesos de Mixamo van a lo largo de su +Y: se gira para llevar la punta hacia allí.
	var axis := basis.y.cross(toward.normalized())
	if axis.length_squared() > 1e-6:
		_tugs[bone] = {axis = (basis.inverse() * axis).normalized(), angle = deg_to_rad(degrees), time = 0.0}
	var root := skeleton.find_bone(ROOT_BONE)
	if shift > 0.0 and root >= 0:
		var parent := skeleton.get_bone_parent(root)
		var frame := skeleton.global_basis
		if parent >= 0:
			frame = frame * skeleton.get_bone_global_pose(parent).basis
		_shove = {offset = frame.inverse() * (toward.normalized() * shift), time = 0.0, bone = root}
	set_process(true)


func _on_limb_dropped(cut: Dictionary, limb: Node3D) -> void:
	if not _restoring.is_empty():
		_place_restored(cut, limb)
		return
	if limb.has_method(&"keep"):
		limb.keep()
	limbs.append(limb)
	var gripper: Variant = _grippers.get(cut.bone)
	_grippers.erase(cut.bone)
	if gripper != null and is_instance_valid(gripper) and (gripper as FeedState).is_eating():
		(gripper as FeedState).hold(limb, randf_range(HOLD_TIME.x, HOLD_TIME.y))


func _process(delta: float) -> void:
	for bone: int in _tugs.keys():
		var tug_state: Dictionary = _tugs[bone]
		tug_state.time += delta
		skeleton.set_bone_pose_rotation(bone, _rotations[bone] * Quaternion(tug_state.axis,
			tug_state.angle * _tug_weight(tug_state.time)))
		if tug_state.time >= TUG_TIME:
			_tugs.erase(bone)
	if not _shove.is_empty():
		_shove.time += delta
		var root: int = _shove.bone
		skeleton.set_bone_pose_position(root, _positions[root] + (_shove.offset as Vector3) * _tug_weight(_shove.time))
		if _shove.time >= TUG_TIME:
			_shove = {}
	for stump in _stumps:
		stump.strength *= pow(0.5, delta / STUMP_HALF_LIFE)
		stump.pulse -= delta
		if stump.pulse <= 0.0 and dismemberment != null:
			stump.pulse = STUMP_PULSE * randf_range(0.85, 1.15)
			var ends := dismemberment.stump(stump.cut)
			CombatFx.spurt(self, ends[0], ends[1], stump.strength)
	_stumps = _stumps.filter(func(stump: Dictionary) -> bool: return stump.strength > STUMP_STOP)
	if _tugs.is_empty() and _shove.is_empty() and _stumps.is_empty():
		set_process(false)


## Cuánto del tirón se ve [time] segundos después: de golpe y luego vuelve despacio.
static func _tug_weight(time: float) -> float:
	return smoothstep(0.0, TUG_IN, time) * (1.0 - smoothstep(TUG_IN, TUG_TIME, time))


## Se queda como está para siempre: sin tirones ni borbotones, lo arrancado quieto y sin
## Dismemberment (que, con cortes, cada fotograma mira si alguna malla ha cambiado). Las mallas
## cortadas y las tapas de los muñones se quedan. Antes, que no le quede ningún corte por aplicar
## (Dismemberment.is_busy).
func seal() -> void:
	devoured = true
	if built:
		for bone: int in _tugs:
			skeleton.set_bone_pose_rotation(bone, _rotations[bone])
		if not _shove.is_empty():
			skeleton.set_bone_pose_position(_shove.bone, _positions[_shove.bone])
	_tugs.clear()
	_shove = {}
	_stumps.clear()
	_focus = {}
	set_process(false)
	for limb in limbs:
		if is_instance_valid(limb) and limb.has_method(&"settle"):
			limb.settle()
	if dismemberment != null:
		dismemberment.queue_free()
		dismemberment = null


# ---------------------------------------------------------------------------------------------
# Partida guardada


func get_save_data() -> Dictionary:
	if not built:
		return {}
	var origin := global_position
	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	if fo != null:
		origin = fo.to_canonical(origin)
	var pose := []
	for b in skeleton.get_bone_count():
		var scale := skeleton.get_bone_pose_scale(b)
		pose.append(_vec(_positions[b]) + [_rotations[b].x, _rotations[b].y, _rotations[b].z, _rotations[b].w] + _vec(scale))
	var kept := []
	for limb in limbs:
		if is_instance_valid(limb) and limb.has_method(&"saved_pose"):
			kept.append({cut = String(limb.cut_bone), pose = limb.saved_pose(global_transform)})
	var guts := get_node_or_null(^"GutPile") as Node3D
	return {
		"origin": _vec(origin), "basis": _basis(global_basis), "skeleton": _xform(skeleton.transform),
		"gravity": _vec(_gravity), "pose": pose, "look": _look, "cuts": _cuts, "limbs": kept,
		"lost": _lost.keys().map(func(zone: StringName) -> String: return String(zone)),
		"open": not wound.is_empty(), "guts": _xform(guts.transform) if guts != null else [],
		"devoured": devoured,
	}


## Lo de la partida guardada: si ya está (la misma partida), nada; si no, se rehace (_rebuild).
func restore_save_data(data: Dictionary) -> void:
	if built:
		return
	if data.is_empty():
		queue_free()
		return
	_restoring = data
	_rebuild.call_deferred()


## Rehace los restos de lo guardado. Un cuerpo de personaje con su aspecto y lo que llevaba puesto,
## en la pose guardada, de donde se copian las mallas (build); luego los cortes, los de la fiera
## soltando lo arrancado, que se coloca donde quedó (_place_restored); la canal, las vísceras, la
## sangre del tronco, y quieto (seal).
func _rebuild() -> void:
	var data := _restoring
	var origin := _to_vec(data.get("origin", []))
	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	if fo != null:
		origin = fo.from_canonical(origin)
	global_transform = Transform3D(_to_basis(data.get("basis", [])), origin)
	reset_physics_interpolation()
	var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	model.visible = false
	add_child(model)
	var rig := model.get_node_or_null(^"AppearanceRig") as CharacterAppearanceRig
	var source := model.get_node(^"Armature/Skeleton3D") as Skeleton3D
	var look: Dictionary = data.get("look", {})
	if rig != null:
		rig.apply(CharacterAppearance.from_dict(look.get("appearance", {})))
		for piece: Dictionary in look.get("armor", []):
			var scene := load(String(piece.get("scene", ""))) as PackedScene
			if scene == null:
				continue
			var item := scene.instantiate()
			source.add_child(item)
			rig.dress(item, bool(piece.get("head", false)))
		var waited := 0.0
		while rig.is_dressing() and waited < DRESS_TIMEOUT:
			await get_tree().process_frame
			waited += get_process_delta_time()
	var pose: Array[Transform3D] = []
	for entry: Array in data.get("pose", []):
		var rotation := Quaternion(entry[3], entry[4], entry[5], entry[6]).normalized()
		pose.append(Transform3D(Basis(rotation).scaled(Vector3(entry[7], entry[8], entry[9])),
			Vector3(entry[0], entry[1], entry[2])))
	if pose.size() != source.get_bone_count():
		push_warning("PlayerRemains: la pose guardada no casa con el esqueleto (%d/%d huesos)" % [pose.size(), source.get_bone_count()])
		model.queue_free()
		queue_free()
		return
	var lost: Array[StringName] = []
	for zone in data.get("lost", []):
		lost.append(StringName(zone))
	build(source, pose, self, null, _to_vec(data.get("gravity", [])), lost)
	skeleton.transform = _to_xform(data.get("skeleton", []))
	model.queue_free()
	_look = look
	devoured = true
	# Los miembros por colocar, por el hueso de su corte.
	var places := {}
	for limb: Dictionary in data.get("limbs", []):
		places[String(limb.get("cut", ""))] = limb.get("pose", {})
	_restoring = data.duplicate()
	_restoring.places = places
	for c: Dictionary in data.get("cuts", []):
		var drop := bool(c.get("drop", false)) and places.has(String(c.get("name", "")))
		dismemberment.add_saved(StringName(c.get("name", "")), float(c.get("t", 0.5)), _to_vec(c.get("origin", [])),
			_to_vec(c.get("normal", [0, 1, 0])), drop)
		_cuts.append(c)
	if data.get("open", false):
		open_torso()
	var guts: Array = data.get("guts", [])
	if guts.size() == 12:
		var pile := MeshInstance3D.new()
		pile.name = "GutPile"
		pile.mesh = GutPile.mesh()
		add_child(pile)
		pile.transform = _to_xform(guts)
	var frames := 0
	while dismemberment.is_busy() and frames < 600:
		await get_tree().process_frame
		frames += 1
	if SettingsManager.gore_level() != SettingsManager.GORE_OFF and not wound.is_empty():
		for i in 4:
			BloodStains.stain(self, torso_point() + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15)), -_up(), 1.4)
	_restoring = {}
	seal()


## Lo arrancado al rehacerlo: donde quedó, quieto. Sin sitio guardado, se lo comieron.
func _place_restored(cut: Dictionary, limb: Node3D) -> void:
	var places: Dictionary = _restoring.get("places", {})
	var place: Variant = places.get(String(cut.name))
	if place == null or not limb.has_method(&"place"):
		limb.queue_free()
		return
	limb.place(global_transform, place)
	limbs.append(limb)


static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a.size() >= 3 else Vector3.ZERO


static func _basis(b: Basis) -> Array:
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]


static func _to_basis(a: Array) -> Basis:
	if a.size() < 9:
		return Basis.IDENTITY
	return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))


static func _xform(t: Transform3D) -> Array:
	return _basis(t.basis) + _vec(t.origin)


static func _to_xform(a: Array) -> Transform3D:
	if a.size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(_to_basis(a), Vector3(a[9], a[10], a[11]))

