class_name PeltSwing
extends SkirtSwing

## Swings a pelt's forelegs (PeltBones) as SkirtSwing does the skirt: each
## chain hangs under gravity and lags behind when the body speeds up or
## slows down (SkirtSwing's _process()), and a capsule behind each, against
## the chest, keeps it from swinging into it. Lengths and speeds in skeleton
## units, offsets in metres, as there.

## How strongly a foreleg turns back to hanging as at rest, how much of its
## swing a joint loses each frame, metres per second it falls with.
const LEG_STIFFNESS := 0.6
const LEG_DRAG := 0.4
const LEG_GRAVITY := 1.2
## How thick a foreleg is round its chain, and the chest's capsule behind
## it, metres.
const LEG_RADIUS := 0.035
const CHEST_RADIUS := 0.06


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_units = 1.0 / skeleton.global_transform.basis.get_scale().x
	var globals := BodyMeasurements.rest_globals(skeleton)
	var spine := skeleton.find_bone(PeltBones.SPINE)
	var neck := skeleton.find_bone(PeltBones.NECK)
	var down := (globals[spine].origin - globals[neck].origin).normalized()
	var to_spine := globals[spine].basis.orthonormalized().inverse()
	setting_count = PeltBones.CHAINS
	for chain in PeltBones.CHAINS:
		var last := skeleton.find_bone(PeltBones.bone_name(chain, PeltBones.JOINTS - 1))
		set_root_bone_name(chain, PeltBones.bone_name(chain, 0))
		set_end_bone_name(chain, PeltBones.bone_name(chain, PeltBones.JOINTS - 1))
		set_extend_end_bone(chain, true)
		set_end_bone_direction(chain, BONE_DIRECTION_FROM_PARENT)
		set_end_bone_length(chain, skeleton.get_bone_rest(last).origin.length())
		set_center_from(chain, CENTER_FROM_NODE)
		set_center_node(chain, get_path_to(skeleton))
		set_radius(chain, LEG_RADIUS * _units)
		set_stiffness(chain, LEG_STIFFNESS * _units)
		set_drag(chain, LEG_DRAG)
		set_gravity(chain, LEG_GRAVITY * _units)
		set_gravity_direction(chain, down)
		# The chest behind the foreleg where it hangs plumb, from over the
		# pectorals to its end, on the spine.
		var top := globals[skeleton.find_bone(PeltBones.bone_name(chain, 1))].origin
		var bottom := globals[last].origin + down * skeleton.get_bone_rest(last).origin.length()
		var length := top.distance_to(bottom)
		var back := globals[spine].origin - top
		back = (back - down * down.dot(back)).normalized()
		var centre := (top + bottom) * 0.5 + back * (LEG_RADIUS + CHEST_RADIUS) * _units
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = "Chest%d" % chain
		capsule.bone_name = PeltBones.SPINE
		capsule.radius = CHEST_RADIUS * _units
		capsule.height = length + CHEST_RADIUS * _units * 2.0
		# In the bone's axes, metres.
		capsule.position_offset = to_spine * (centre - globals[spine].origin) / _units
		add_child(capsule)
