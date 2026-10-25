class_name FishingPose
extends RefCounted

## Brazos por IK: preparar, latigazo al lanzar, espera y tirón al recoger.
var weight := 0.0
var cast_phase := -1.0
var pull := 0.0
var direction := Vector3.FORWARD


func apply(p: CombatPose) -> void:
	if weight <= 0.001:
		return
	var up := p.model_dir(Vector3.UP)
	var forward := p.to_skel_dir(direction).slide(up).normalized()
	if forward.length_squared() < 0.01:
		forward = p.model_dir(Vector3.BACK)
	var right := forward.cross(up).normalized()
	var m := p.unit()
	var lift := pull * 0.18
	var back := pull * 0.15
	var angle := lerpf(55.0, 12.0, pull)
	if cast_phase >= 0.0:
		var snap := smoothstep(0.15, 0.65, cast_phase)
		angle = lerpf(-35.0, 65.0, snap)
		lift += sin(cast_phase * PI) * 0.20
		back += (1.0 - snap) * 0.15
	var hand := p.bone_pos(CombatPose.R_ARM[0]) + (forward * (0.34 - back) - up * (0.27 - lift)) * m
	p.two_bone(CombatPose.R_ARM, hand, right - up, weight)
	p.two_bone(CombatPose.L_ARM, hand - right * 0.12 * m - up * 0.08 * m, -right - up, weight)
	var rod_axis := (up * cos(deg_to_rad(angle)) + forward * sin(deg_to_rad(angle))).normalized()
	# _apply_grip coloca +Y por el pulgar; orientar la palma alinea la caña con rod_axis.
	var palm := forward * cos(deg_to_rad(angle)) - up * sin(deg_to_rad(angle))
	p.orient_hand("Right", palm.cross(rod_axis).normalized(), palm, weight)
	p.pose_fingers("Left", CombatPose.FIST, weight)
