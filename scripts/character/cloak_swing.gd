class_name CloakSwing
extends SkirtSwing

## Swings a cloak's bones (CloakBones) as SkirtSwing does the skirt's: each
## chain hangs under gravity, lags behind when the body speeds up or slows
## down (SkirtSwing's _process()) and streams behind as it moves (AIR). The torso, the legs and the arms
## push it aside, as capsules round their flesh (fit_legs()): the torso's by
## its depth, so the cloak lies on the back instead of standing off it as
## far as the shoulders are wide. Lengths and speeds in skeleton units,
## offsets in metres, as there.

## A cloak is heavier and swings slower than a skirt's strips.
const CLOAK_STIFFNESS := 0.5
const CLOAK_DRAG := 0.45
const CLOAK_RADIUS := 0.03
const CLOAK_GRAVITY := 1.2
## How much of the body's speed (m/s) the air pushes it back with: running,
## it streams behind (at 4 m/s, about a quarter of the way to level).
const AIR := 0.13
## How much further (m) than the body the torso's capsules reach: the cloak
## hangs over a chest piece, and only off the bare body it would sink into it.
const TORSO_MARGIN := 0.06
## [bone, next bone, radius in metres until the body is measured].
const TORSO := [
	[&"mixamorig_Hips", &"mixamorig_Spine", 0.12],
	[&"mixamorig_Spine", &"mixamorig_Spine1", 0.12],
	[&"mixamorig_Spine1", &"mixamorig_Spine2", 0.12],
	[&"mixamorig_Spine2", &"mixamorig_Neck", 0.12],
]
## Capsules across the body rather than along a bone (their axis along the
## bone's X), round the deepest of some of its slices: [name, bone, first
## and last slice + 1, margin (m)]. The buttocks (the lower half of the
## hips', with the belly in front of them), so what hangs from the back
## falls over them rather than into the hollow the torso's and the thighs'
## capsules leave there; the shoulder blades, which stand out at the sides
## of the back past the torso's round capsule. The margin as the cloak
## stands off them: only the chains' joints collide, and the cloak between
## two of them must clear them too.
const ACROSS := [
	[&"Buttocks", &"mixamorig_Hips", 0, 3, 0.03],
	[&"ShoulderBlades", &"mixamorig_Spine2", 0, 6, 0.015],
]
const ARMS := [
	[&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", 0.05],
	[&"mixamorig_RightArm", &"mixamorig_RightForeArm", 0.05],
	[&"mixamorig_LeftForeArm", &"mixamorig_LeftHand", 0.04],
	[&"mixamorig_RightForeArm", &"mixamorig_RightHand", 0.04],
]


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_units = 1.0 / skeleton.global_transform.basis.get_scale().x
	var globals := BodyMeasurements.rest_globals(skeleton)
	var spine := skeleton.find_bone(CloakBones.SPINE)
	var hips := skeleton.find_bone(SkirtBones.HIPS)
	var down := (globals[hips].origin - globals[spine].origin).normalized()
	setting_count = CloakBones.CHAINS
	for chain in CloakBones.CHAINS:
		var last := skeleton.find_bone(CloakBones.bone_name(chain, CloakBones.JOINTS - 1))
		set_root_bone_name(chain, CloakBones.bone_name(chain, 0))
		set_end_bone_name(chain, CloakBones.bone_name(chain, CloakBones.JOINTS - 1))
		set_extend_end_bone(chain, true)
		set_end_bone_direction(chain, BONE_DIRECTION_FROM_PARENT)
		set_end_bone_length(chain, skeleton.get_bone_rest(last).origin.length())
		set_center_from(chain, CENTER_FROM_NODE)
		set_center_node(chain, get_path_to(skeleton))
		set_radius(chain, CLOAK_RADIUS * _units)
		set_stiffness(chain, CLOAK_STIFFNESS * _units)
		set_drag(chain, CLOAK_DRAG)
		set_gravity(chain, CLOAK_GRAVITY * _units)
		set_gravity_direction(chain, down)
	for limb in TORSO + LEGS + ARMS:
		var bone := skeleton.find_bone(limb[0])
		var next := skeleton.find_bone(limb[1])
		if bone < 0 or next < 0:
			continue
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = String(limb[0]).trim_prefix(HumanRig.PREFIX)
		capsule.bone_name = limb[0]
		capsule.set_meta(&"length", globals[bone].origin.distance_to(globals[next].origin))
		capsule.set_meta(&"torso", limb in TORSO)
		add_child(capsule)
		_size_leg(capsule, limb[2], Vector2.ZERO)
	# The arms come out through the cloak's slits in front of its end chains:
	# pushed off them, those would bell it out round the hands.
	for chain in [0, CloakBones.CHAINS - 1]:
		set_exclude_collision_count(chain, ARMS.size())
		for k in ARMS.size():
			set_exclude_collision_path(chain, k, NodePath(String(ARMS[k][0]).trim_prefix(HumanRig.PREFIX)))
	for across in ACROSS:
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = across[0]
		capsule.bone_name = across[1]
		capsule.rotation_offset = Quaternion(Vector3.BACK, PI * 0.5)
		add_child(capsule)
		_size_across(capsule, 0.1, 0.34, Vector3.ZERO)


## Fits the capsules to a body's measurements as SkirtSwing.fit_legs() does
## the legs' (a limb's round its widest side); the torso's round its depth,
## centred front to back.
func fit_legs(body: BodyMeasurements) -> void:
	var skeleton := get_skeleton()
	for capsule in get_children():
		if not capsule is SpringBoneCollisionCapsule3D:
			continue
		var bone := skeleton.find_bone(capsule.bone_name)
		if not body.has_bone(bone):
			continue
		var across := ACROSS.filter(func(a: Array) -> bool: return a[0] == capsule.name)
		if not across.is_empty():
			_fit_across(capsule, body, bone, across[0])
			continue
		var xs := PackedFloat32Array()
		var zs := PackedFloat32Array()
		var radii := PackedFloat32Array()
		for slice in BodyMeasurements.SLICES:
			var at := (bone * BodyMeasurements.SLICES + slice) * 4
			var section := body.sections.slice(at, at + 4)
			xs.append((section[0] + section[1]) * 0.5)
			zs.append((section[2] + section[3]) * 0.5)
			if capsule.get_meta(&"torso", false):
				radii.append((section[3] - section[2]) * 0.5)
			else:
				radii.append(maxf(section[1] - section[0], section[3] - section[2]) * 0.5)
		var torso: bool = capsule.get_meta(&"torso", false)
		var centre := Vector2(0.0 if torso else _median(xs), _median(zs))
		_size_leg(capsule, _median(radii) / _units + (TORSO_MARGIN if torso else 0.0), centre / _units)


## Round the deepest of the slices `across` names: as deep as it (and its
## margin), as wide.
func _fit_across(capsule: SpringBoneCollisionCapsule3D, body: BodyMeasurements, bone: int, across: Array) -> void:
	var deepest := 0
	var depth := -1.0
	for slice in range(across[2], across[3]):
		var at := (bone * BodyMeasurements.SLICES + slice) * 4
		if body.sections[at + 3] - body.sections[at + 2] > depth:
			depth = body.sections[at + 3] - body.sections[at + 2]
			deepest = slice
	var at := (bone * BodyMeasurements.SLICES + deepest) * 4
	var section := body.sections.slice(at, at + 4)
	var span := body.spans[bone]
	var y := span.x + (deepest + 0.5) / BodyMeasurements.SLICES * (span.y - span.x)
	var centre := Vector3((section[0] + section[1]) * 0.5, y, (section[2] + section[3]) * 0.5)
	_size_across(capsule, depth * 0.5 / _units + across[4], (section[1] - section[0]) / _units, centre / _units)


## Radius and width in metres; the centre in the bone's axes, metres. The
## cylinder runs between the middles of the two halves, half the width apart.
func _size_across(capsule: SpringBoneCollisionCapsule3D, radius: float, width: float, centre: Vector3) -> void:
	capsule.radius = radius * _units
	capsule.height = (radius * 2.0 + width * 0.5) * _units
	capsule.position_offset = centre


func _process(delta: float) -> void:
	super(delta)
	var skeleton := get_skeleton()
	if skeleton != null and active and _tracking:
		external_force += skeleton.global_basis.inverse() * (-_last_velocity * AIR)
