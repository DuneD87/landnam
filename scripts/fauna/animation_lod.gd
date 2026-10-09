class_name AnimationLod

## De cada cuántos fotogramas se anima un esqueleto según dónde está respecto de la cámara, con el
## tiempo acumulado: lo que cuesta es el esqueleto (mezclar los clips y posar cientos de huesos, en
## CPU). La fauna ambiental (SkinnedModel) aligera también los lejanos (stride_for); las criaturas
## (AnimationController), solo las que están fuera de cámara (in_view), que de cerca se notaba.

## Cada cuánto se vuelve a mirar dónde está la cámara (s).
const CHECK_INTERVAL := 0.5
## [distancia a la cámara (m), de cada cuántos fotogramas], en cámara.
const STRIDES := [[12.0, 1], [30.0, 2], [60.0, 3]]
const FAR_STRIDE := 4
const HIDDEN_STRIDE := 8


## El paso de [node] con la cámara de su viewport. [radius] (m) es el del cuerpo: uno grande con el
## origen fuera de cámara puede asomar en ella. Sin cámara, cada fotograma.
static func stride_for(node: Node3D, radius: float = 0.0) -> int:
	var camera := node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	if camera == null:
		return 1
	if not _in_frustum(camera, node.global_position, radius):
		return HIDDEN_STRIDE
	var distance := camera.global_position.distance_to(node.global_position)
	for step in STRIDES:
		if distance < step[0]:
			return step[1]
	return FAR_STRIDE


## Si [node] asoma en la cámara de su viewport ([radius] como en stride_for). Sin cámara, sí.
static func in_view(node: Node3D, radius: float = 0.0) -> bool:
	var camera := node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	return camera == null or _in_frustum(camera, node.global_position, radius)


static func _in_frustum(camera: Camera3D, point: Vector3, radius: float) -> bool:
	if radius <= 0.0:
		return camera.is_position_in_frustum(point)
	# Los planos del frustum miran hacia fuera.
	for plane in camera.get_frustum():
		if plane.distance_to(point) > radius:
			return false
	return true
