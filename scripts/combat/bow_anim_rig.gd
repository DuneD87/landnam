class_name BowAnimRig
extends RefCounted

## Arco sobre las animaciones del Pro Longbow Pack de Mixamo (bow_draw y bow_recoil de la
## librería "combat"): el cuerpo lo pone la animación y aquí solo se colocan
## el arco en el puño izquierdo, la cuerda en los dedos de la derecha y la flecha, en el mismo
## fotograma. Da los mismos resultados que ArcheryPose, así que quien lleva el arco los coloca
## igual con una u otra.
##
## Los clips se encadenan sin saltos: bow_draw acaba a tope donde empieza bow_recoil (soltar), y
## bow_recoil acaba donde empieza bow_draw (la mano atrás, que sube por encima del hombro a la
## aljaba, saca la flecha, la encaja y tensa). Sostener a tope es quedarse en el último
## fotograma de bow_draw: bow_overdraw no sirve (sigue tensando 13 cm más en sus 3,8 s hasta
## llevar la mano tras la cabeza, su cabeza tiembla 3° de cabeceo y no empieza donde acaba
## bow_draw: la cabeza cae 3 cm al pasar de uno a otro).

## Instantes de bow_draw (s): la mano pasa por la boca de la aljaba y se lleva la flecha, y la
## encaja en la cuerda; desde ahí tensa hasta el anclaje (final del clip).
const GRAB_T := 0.30
const NOCK_T := 0.57
## Distancia de la empuñadura a los dedos de la cuerda al final de bow_draw (m): tensión 1.
const FULL_DRAW := 0.671
## Dirección de la flecha de la animación a tope, respecto al frente del cuerpo (grados; yaw
## positivo hacia la izquierda, pitch hacia arriba). CombatPose inclina el tronco para llevarla
## al blanco.
const ANIM_ARROW_YAW := 0.6
const ANIM_ARROW_PITCH := -4.7
## Arco respecto al marco de la mano izquierda (CombatPose.hand_frame), medido a tope: su +Z por
## la flecha y su +Y arriba. CANT lo ladea como ArcheryPose (la pala de arriba fuera de la cara).
const BOW_IN_HAND := Basis(Vector3(-0.2956, -0.9419, 0.1595), Vector3(0.2133, -0.2278, -0.95),
	Vector3(0.9312, -0.2468, 0.2683))
const CANT := 10.0

# --- Entradas (las pone PlayerCombat o el escenario de pruebas) ---

## Clip que suena en el canal de tronco y brazos (&"bow_draw", &"bow_recoil"),
## o vacío, y su instante.
var clip: StringName = &""
var time: float = 0.0

# --- Resultados, en mundo (ver ArcheryPose) ---

var bow_xform: Transform3D
var bow_flex: float = 0.0
var string_point: Vector3
var string_pulled: bool = false
var arrow_mode: StringName = &""
var arrow_xform: Transform3D


## 0..1 cuánto se aparta la línea de tiro de la cara (CombatPose._clear_face): entra mientras
## tensa, a tope se queda y al soltar se va con el retroceso.
func face_clearance_weight() -> float:
	match clip:
		&"bow_draw":
			return smoothstep(NOCK_T, NOCK_T + 0.25, time)
		&"bow_recoil":
			return 1.0 - smoothstep(0.0, 0.35, time)
	return 0.0


func apply(p: CombatPose) -> void:
	var m := p.unit()
	var to_world := p.skeleton().global_transform
	var up := p.model_dir(Vector3.UP)
	# Arco: la empuñadura en el puño cerrado, como un mango (CombatPose.FIST_HANDLE).
	var hand := p.hand_frame("Left")
	var grip := p.bone_pos("mixamorig_LeftHand") \
		+ (hand.x * CombatPose.FIST_HANDLE.x + hand.y * CombatPose.FIST_HANDLE.y) * m
	var bow_skel := Transform3D((hand * BOW_IN_HAND * Basis(Vector3.BACK, deg_to_rad(-CANT))).orthonormalized(), grip)
	# Cuerda entre el índice y el corazón de la derecha.
	var fingers := (p.bone_pos("mixamorig_RightHandIndex2") + p.bone_pos("mixamorig_RightHandMiddle2")) * 0.5
	var brace := -WeaponMeshes.bow_tip(true).z
	var rest := bow_skel * (Vector3(0, ArcheryPose.ARROW_REST, -brace) * m)
	var arrow_rest := bow_skel * (Vector3(0, ArcheryPose.ARROW_REST, 0) * m)

	bow_xform = Transform3D((to_world.basis * bow_skel.basis).orthonormalized(), to_world * bow_skel.origin)
	var drawing := clip == &"bow_draw" and time >= NOCK_T
	string_pulled = drawing
	string_point = to_world * (fingers if string_pulled else rest)
	var pull := (grip.distance_to(fingers) / m - brace) / (FULL_DRAW - brace)
	bow_flex = clampf(pull, 0.0, 1.0) if string_pulled else 0.0
	if clip == &"bow_recoil" and time < 0.6:
		# La cuerda vuelve de golpe y vibra; las palas rebotan (como ArcheryPose).
		var vib := exp(-time * 11.0)
		string_point = to_world * rest + (to_world.basis * bow_skel.basis.x).normalized() * 0.006 * sin(time * TAU * 22.0) * vib
		bow_flex = exp(-time * 28.0) * cos(time * 50.0)

	arrow_mode = &""
	var world_up := (to_world.basis * up).normalized()
	if string_pulled:
		arrow_mode = &"nocked"
		arrow_xform = ArcheryPose._arrow_at(to_world * fingers, (to_world * arrow_rest - to_world * fingers).normalized(), world_up)
	elif clip == &"bow_draw" and time >= GRAB_T:
		# En la mano: sale de la aljaba hacia arriba y gira hasta apuntar al arco al encajarla.
		arrow_mode = &"hand"
		var into_quiver := -ArcheryPose.quiver_skel(p).basis.y
		var to_bow := (arrow_rest - fingers).normalized()
		var dir := into_quiver.slerp(to_bow, smoothstep(GRAB_T + 0.08, NOCK_T, time)).normalized()
		arrow_xform = ArcheryPose._arrow_at(to_world * fingers - (to_world.basis * dir).normalized() * 0.02,
			(to_world.basis * dir).normalized(), world_up)
