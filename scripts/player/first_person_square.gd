class_name FirstPersonSquare
extends SkeletonModifier3D

## Primera persona: gira el cuerpo entero sobre la cadera para que el pecho mire al frente del
## modelo, que es hacia donde mira la cámara (el jugador se encara a ella). Los golpes tuercen el
## tronco hasta 70° a cada lado y el pesado de la espada da la vuelta entera; con la cámara en la
## cabeza y el giro del ratón, eso mete el hombro delante de la vista. Lo que brazo y arma
## recorren respecto al pecho se queda, y la hoja que hiere es la que se ve.
##
## Va antes de FootIK, que apoya los pies donde queden, y de LookAtIK, que luego tuerce el tronco
## hacia la mirada. Solo gira en el plano del suelo del modelo: no endereza al que se agacha ni al
## que salta.

## Nodo cuyo marco manda (PlayerModel): +Z adelante, +Y arriba, +X a la izquierda.
var frame_node: Node3D

var _hips := -1
var _left := -1
var _right := -1


func _ready() -> void:
	var skel := get_skeleton()
	if skel != null:
		_hips = skel.find_bone(&"mixamorig_Hips")
		_left = skel.find_bone(&"mixamorig_LeftArm")
		_right = skel.find_bone(&"mixamorig_RightArm")


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skel := get_skeleton()
	if skel == null or frame_node == null or _hips < 0 or _left < 0 or _right < 0:
		return
	var to_frame := frame_node.global_transform.affine_inverse() * skel.global_transform
	# El frente del pecho, por la línea de los hombros: no depende de los ejes de los huesos.
	var across := to_frame * skel.get_bone_global_pose(_left).origin - to_frame * skel.get_bone_global_pose(_right).origin
	var forward := across.cross(Vector3.UP)
	if forward.length_squared() < 1e-6:
		return
	var yaw := atan2(forward.x, forward.z)
	var up := (to_frame.basis.inverse() * Vector3.UP).normalized()
	var pose := skel.get_bone_global_pose(_hips)
	# La cadera es la raíz: su pose ya está en el espacio del esqueleto.
	skel.set_bone_pose_rotation(_hips, (Quaternion(up, -yaw) * pose.basis.get_rotation_quaternion()).normalized())
