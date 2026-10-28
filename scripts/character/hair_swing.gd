class_name HairSwing
extends SpringBoneSimulator3D

## Swings the hair's bones (HairBones) of the skeleton it is a child of: each
## chain hangs under gravity, lags behind the head when it turns or the body
## speeds up or slows down, and the head, neck, back, shoulders and upper
## arms keep it out of them.
##
## Like SkirtSwing it simulates in the skeleton's own space, so lengths and
## speeds are in skeleton units (the constants are in metres and scaled) and
## the body's movement through the world comes in as an external force.

## How strongly a chain turns back to the shape the style was groomed in, at
## its root and at its tip: the roots hold, the ends fly.
const STIFFNESS_ROOT := 1.2
const STIFFNESS_TIP := 0.15
## How much of its swing a joint loses each frame.
const DRAG := 0.3
## Metres per second it falls with.
const GRAVITY := 2.5
## Thickness of the hair round each joint, metres.
const JOINT_RADIUS := 0.012
## The body, as capsules: [bone, next bone, radius in metres until the body is
## measured, share of the measured flesh it keeps]. Under a share of 1 the
## hair lying on the body at rest starts clear of it.
const CAPSULES := [
	[&"mixamorig_Neck", &"mixamorig_Head", 0.055, 0.9],
	[&"mixamorig_Spine2", &"mixamorig_Neck", 0.1, 0.7],
	[&"mixamorig_LeftShoulder", &"mixamorig_LeftArm", 0.05, 0.75],
	[&"mixamorig_RightShoulder", &"mixamorig_RightArm", 0.05, 0.75],
	[&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", 0.045, 0.9],
	[&"mixamorig_RightArm", &"mixamorig_RightForeArm", 0.045, 0.9],
]
## The head, a sphere at the ring's centre, as a share of the head's length.
const HEAD_RADIUS := 0.3
## How much of the body's acceleration swings it the other way, and how
## quickly that acceleration is followed (per second), so steps do not jolt it.
const INERTIA := 0.08
const INERTIA_SMOOTHING := 8.0

var _units := 100.0
var _last_position := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _acceleration := Vector3.ZERO
var _tracking := false


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_units = 1.0 / skeleton.global_transform.basis.get_scale().x
	var ring := HairBones.frame(skeleton)
	var globals := BodyMeasurements.rest_globals(skeleton)
	var stiffness := Curve.new()
	stiffness.max_value = 1.0
	stiffness.add_point(Vector2(0.0, 1.0))
	stiffness.add_point(Vector2(1.0, STIFFNESS_TIP / STIFFNESS_ROOT))
	var down: Vector3 = globals[skeleton.find_bone(HairBones.HEAD)].basis * -ring.up
	setting_count = HairBones.CHAINS
	for chain in HairBones.CHAINS:
		set_root_bone_name(chain, HairBones.bone_name(chain, 0))
		set_end_bone_name(chain, HairBones.bone_name(chain, HairBones.JOINTS - 1))
		set_extend_end_bone(chain, true)
		set_end_bone_direction(chain, BONE_DIRECTION_FROM_PARENT)
		set_end_bone_length(chain, HairBones.DROP * ring.size)
		set_center_from(chain, CENTER_FROM_NODE)
		set_center_node(chain, get_path_to(skeleton))
		set_radius(chain, JOINT_RADIUS * _units)
		set_stiffness(chain, STIFFNESS_ROOT * _units)
		set_stiffness_damping_curve(chain, stiffness)
		set_drag(chain, DRAG)
		set_gravity(chain, GRAVITY * _units)
		set_gravity_direction(chain, down.normalized())
	var head := SpringBoneCollisionSphere3D.new()
	head.name = "Head"
	head.bone_name = HairBones.HEAD
	head.radius = HEAD_RADIUS * ring.size
	head.position_offset = ring.centre / _units
	add_child(head)
	for entry in CAPSULES:
		var bone := skeleton.find_bone(entry[0])
		var next := skeleton.find_bone(entry[1])
		if bone < 0 or next < 0:
			continue
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = String(entry[0]).trim_prefix(HumanRig.PREFIX)
		capsule.bone_name = entry[0]
		capsule.set_meta(&"length", globals[bone].origin.distance_to(globals[next].origin))
		capsule.set_meta(&"share", entry[3])
		add_child(capsule)
		_size(capsule, entry[2], Vector2.ZERO)


## Fits the capsules to a body's measurements, as SkirtSwing.fit_legs()
## does, keeping each one's share of the flesh.
func fit_body(body: BodyMeasurements) -> void:
	var skeleton := get_skeleton()
	for capsule in get_children():
		if not capsule is SpringBoneCollisionCapsule3D:
			continue
		var bone := skeleton.find_bone(capsule.bone_name)
		if not body.has_bone(bone):
			continue
		var xs := PackedFloat32Array()
		var zs := PackedFloat32Array()
		var radii := PackedFloat32Array()
		for slice in BodyMeasurements.SLICES:
			var at := (bone * BodyMeasurements.SLICES + slice) * 4
			var section := body.sections.slice(at, at + 4)
			xs.append((section[0] + section[1]) * 0.5)
			zs.append((section[2] + section[3]) * 0.5)
			radii.append(minf(section[1] - section[0], section[3] - section[2]) * 0.5)
		var share: float = capsule.get_meta(&"share")
		_size(capsule, _median(radii) * share / _units, Vector2(_median(xs), _median(zs)) / _units)


## Starts over from the bones' rests (a new style moved them).
func restart() -> void:
	_tracking = false
	reset()


## `radius` and `centre` (across the bone: X, Z) in metres.
func _size(capsule: SpringBoneCollisionCapsule3D, radius: float, centre: Vector2) -> void:
	var length: float = capsule.get_meta(&"length")
	capsule.radius = radius * _units
	capsule.height = length + radius * _units * 2.0
	# In the bone's axes (Y towards the next joint); metres.
	capsule.position_offset = Vector3(centre.x, length * 0.5 / _units, centre.y)


static func _median(values: PackedFloat32Array) -> float:
	values.sort()
	return values[values.size() / 2]


func _process(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not active or delta <= 0.0:
		_tracking = false
		return
	var position := skeleton.global_position
	if _tracking:
		var velocity := (position - _last_position) / delta
		var acceleration := (velocity - _last_velocity) / delta
		_acceleration = _acceleration.lerp(acceleration, minf(1.0, INERTIA_SMOOTHING * delta))
		_last_velocity = velocity
	else:
		_last_velocity = Vector3.ZERO
		_acceleration = Vector3.ZERO
	_last_position = position
	_tracking = true
	# The skeleton's basis takes world metres into its own units and axes.
	external_force = skeleton.global_basis.inverse() * (-_acceleration * INERTIA)
