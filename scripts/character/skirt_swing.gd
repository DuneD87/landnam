class_name SkirtSwing
extends SpringBoneSimulator3D

## Swings the skirt's bones (SkirtBones) of the skeleton it is a child of:
## each chain hangs under gravity, the thighs and shins push it aside, and it
## lags behind when the body speeds up or slows down.
##
## It simulates in the skeleton's own space (centred on the skeleton): with
## the character's Armature scaled down, the joints and the collision shapes
## only meet there. So lengths and speeds are given in skeleton units (the
## constants are in metres and scaled), the shapes' offsets are in metres
## (SpringBoneCollision3D places them so), and the body's movement through
## the world, which that space does not see, comes in as an external force.

## How strongly a chain turns back to hanging as at rest from the hips.
const STIFFNESS := 0.8
## How much of its swing a joint loses each frame.
const DRAG := 0.35
## Metres per second it falls with.
const GRAVITY := 1.2
## Thickness of the skirt round each joint, metres.
const JOINT_RADIUS := 0.025
## Legs, as capsules: [bone, next bone, girth it takes (BodyMeasurements),
## radius in metres until the body is measured (fit_legs())].
const LEGS := [
	[&"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"thigh", 0.085],
	[&"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"thigh", 0.085],
	[&"mixamorig_LeftLeg", &"mixamorig_LeftFoot", &"calf", 0.06],
	[&"mixamorig_RightLeg", &"mixamorig_RightFoot", &"calf", 0.06],
]
## The thigh's girth is taken at its top, which narrows down to the knee: its
## capsule is this much of it.
const THIGH_SHARE := 0.9
## How much of the body's acceleration swings it the other way, and how
## quickly that acceleration is followed (per second), so steps do not jolt it.
const INERTIA := 0.06
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
	var globals := BodyMeasurements.rest_globals(skeleton)
	var hips := skeleton.find_bone(SkirtBones.HIPS)
	var spine := skeleton.find_bone(SkirtBones.SPINE)
	var down := (globals[hips].origin - globals[spine].origin).normalized()
	setting_count = SkirtBones.CHAINS
	for chain in SkirtBones.CHAINS:
		set_root_bone_name(chain, SkirtBones.bone_name(chain, 0))
		set_end_bone_name(chain, SkirtBones.bone_name(chain, SkirtBones.JOINTS - 1))
		set_extend_end_bone(chain, true)
		set_end_bone_direction(chain, BONE_DIRECTION_FROM_PARENT)
		var last := skeleton.find_bone(SkirtBones.bone_name(chain, SkirtBones.JOINTS - 1))
		set_end_bone_length(chain, skeleton.get_bone_rest(last).origin.length())
		set_center_from(chain, CENTER_FROM_NODE)
		set_center_node(chain, get_path_to(skeleton))
		set_radius(chain, JOINT_RADIUS * _units)
		set_stiffness(chain, STIFFNESS * _units)
		set_drag(chain, DRAG)
		set_gravity(chain, GRAVITY * _units)
		set_gravity_direction(chain, down)
	for leg in LEGS:
		var bone := skeleton.find_bone(leg[0])
		var next := skeleton.find_bone(leg[1])
		if bone < 0 or next < 0:
			continue
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = String(leg[0]).trim_prefix("mixamorig_")
		capsule.bone_name = leg[0]
		capsule.set_meta(&"length", globals[bone].origin.distance_to(globals[next].origin))
		capsule.set_meta(&"girth", leg[2])
		add_child(capsule)
		_size_leg(capsule, leg[3])


## Sizes the legs' capsules to a body's measurements (BodyMeasurements.summary).
func fit_legs(summary: Dictionary) -> void:
	for capsule in get_children():
		if capsule is SpringBoneCollisionCapsule3D and summary.has(capsule.get_meta(&"girth")):
			var girth: float = summary[capsule.get_meta(&"girth")]
			_size_leg(capsule, girth / TAU * (THIGH_SHARE if capsule.get_meta(&"girth") == &"thigh" else 1.0))


func _size_leg(capsule: SpringBoneCollisionCapsule3D, radius: float) -> void:
	var length: float = capsule.get_meta(&"length")
	capsule.radius = radius * _units
	capsule.height = length + radius * _units * 2.0
	# Along the bone, which points at the next joint; metres.
	capsule.position_offset = Vector3(0.0, length * 0.5 / _units, 0.0)


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
