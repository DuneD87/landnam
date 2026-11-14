extends CombatPose

## Agarre de dos manos sobre el remo real, también sin un clip de remar. Se aplica después de
## las proporciones del cuerpo; los objetivos y la malla usan la misma palada, en el marco del barco.
## Inclinación de la espalda (grados): se recoge al acercar el mango y se alarga al alejarlo.
const LEAN_BACK := -30.0
const LEAN_FORWARD := 18.0
const REST_LEAN := -5.0
const LEAN_PER_METRE := 120.0
const SPINE_SHARE := Vector3(0.25, 0.15, 0.10)

var bench: RowingBench


func _apply() -> void:
	if _skel == null or frame_node == null or not is_instance_valid(bench) or not bench.is_rowing():
		return
	var body := bench.ship()
	var oars := body.oars() if body != null else null
	if oars == null:
		return
	var station := bench.oar_station()
	if station.is_empty():
		return
	# El clip sentado se mide antes de BodyProportions. Se vuelve a apoyar la cadera con
	# las proporciones ya aplicadas, para que cuerpo y agarre compartan la misma altura real.
	var hips := bone_idx(HumanRig.HIPS)
	if hips < 0:
		return
	var seat := bench.get_global_transform_interpolated().orthonormalized() * RowingBench.SEAT
	var correction := to_skel_point(seat) - bone_pos(HumanRig.HIPS)
	var parent := _skel.get_bone_parent(hips)
	if parent >= 0:
		correction = _skel.get_bone_global_pose(parent).basis.inverse() * correction
	_skel.set_bone_pose_position(hips, _skel.get_bone_pose_position(hips) + correction)
	var phase := oars.phase()
	var ship_frame := body.get_global_transform_interpolated().orthonormalized()
	var axis := to_skel_dir(ship_frame.basis * BoatOars.station_pose(station, phase).basis.y)
	var grip := to_skel_point(ship_frame * BoatOars.grip_at(station, phase))
	var forward := model_dir(Vector3.BACK)
	var up := model_dir(Vector3.UP)
	var left := model_dir(Vector3.RIGHT)
	var m := unit()
	# La espalda sigue la distancia REAL del mango respecto a las caderas. La misma fase mueve
	# los brazos en sentidos opuestos según el costado y la rotación de la bancada: un coseno
	# fijo podía inclinar el pecho hacia las manos justo al recogerlas y meter los codos dentro.
	var to_grip := (grip - bone_pos(HumanRig.HIPS)) / m
	var reach := to_grip.dot(forward)
	var lean := REST_LEAN
	if oars.direction != 0:
		lean = clampf((reach - BoatOars.HOLD_FORWARD) * LEAN_PER_METRE + REST_LEAN, LEAN_BACK, LEAN_FORWARD)
	var twist := clampf(rad_to_deg(atan2(to_grip.dot(left), maxf(reach, 0.15))) * 0.3, -8.0, 8.0)
	# La mitad del balanceo nace en la pelvis: inclinar solo la parte alta de la espalda
	# deja el abdomen en el camino de los antebrazos. Las piernas conservan su orientación.
	rotate_about(HumanRig.HIPS, Vector3.RIGHT, lean * 0.5)
	rotate_about(HumanRig.LEFT_UP_LEG, Vector3.RIGHT, -lean * 0.5)
	rotate_about(HumanRig.RIGHT_UP_LEG, Vector3.RIGHT, -lean * 0.5)
	for i in SPINE.size():
		var share: float = SPINE_SHARE[i]
		rotate_about(SPINE[i], Vector3.RIGHT, lean * share)
		rotate_about(SPINE[i], Vector3.UP, twist * share)
	# La mirada queda más estable mientras la espalda flexiona; las caderas no se despegan.
	rotate_about(HumanRig.NECK, Vector3.RIGHT, -lean * 0.35)
	for side: String in ["Left", "Right"]:
		var sign_side := 1.0 if side == "Left" else -1.0
		var along := signf(axis.dot(left)) * sign_side
		var target := grip + axis * along * BoatOars.HAND_SPACING * 0.5 * m
		# Nudillos al frente, palma sobre el mango; la mano se cierra alrededor del eje.
		var knuckles := forward.slide(axis).normalized()
		var palm := knuckles.cross(axis * along).normalized()
		if palm.dot(-up) < 0.0:
			palm = -palm
		var wrist := target - (knuckles * FIST_HANDLE.x + palm * FIST_HANDLE.y) * m
		# Los codos se abren por delante de las costillas, también al terminar el tirón.
		arm_ik(side, wrist, left * sign_side + forward * 0.6 - up * 0.25, 1.0)
		orient_hand(side, knuckles, palm, 1.0)
		pose_fingers(side, FIST, 1.0)
