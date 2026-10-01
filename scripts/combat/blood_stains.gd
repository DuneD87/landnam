class_name BloodStains
extends RefCounted

## Sangre sobre el cuerpo: cada golpe deja en el sitio por donde entra una mancha con regueros que
## bajan según la gravedad (blood_smear.png), pegada al hueso más cercano para que siga al cuerpo al
## moverse. Son Decals que solo pintan las mallas del personaje: estas llevan además la capa de
## render LAYER, y las manchas solo esa capa en su cull_mask, así que el suelo de debajo no se
## mancha. Se secan oscureciéndose y se limpian con clear() (al reaparecer, al reciclar una criatura).

## Capa de render 20, libre en el proyecto: la de las mallas que se pueden manchar.
const LAYER := 1 << 19
const MAX_PER_BODY := 12
const DRY_TIME := 60.0
const SMEAR := preload("res://textures/combat/blood_smear.png")
const SMEAR_NORMAL := preload("res://textures/combat/blood_smear_normal.png")
const META_SKELETON := &"blood_stain_skeleton"
const META_STAINS := &"blood_stains"
const HOLDER_PREFIX := "BloodStains_"


## Mancha a [target] por donde entra un golpe ([point], mundo) que va hacia [direction]. [power]
## (0,4..1,6) da el tamaño.
static func stain(target: Node, point: Vector3, direction: Vector3, power: float) -> void:
	if SettingsManager.gore_level() == SettingsManager.GORE_OFF:
		return
	var body := target as Node3D
	if body == null or not body.is_inside_tree():
		return
	var skel := _skeleton(body)
	if skel == null:
		return
	var bone := _nearest_bone(skel, point)
	if bone < 0:
		return
	_tag_meshes(skel)
	var holder := _holder(skel, bone)
	var decal := Decal.new()
	decal.name = "Stain"
	decal.texture_albedo = SMEAR
	decal.texture_normal = SMEAR_NORMAL
	decal.texture_orm = BloodPool._orm()
	decal.cull_mask = LAYER
	# Solo las caras que miran hacia el golpe, no las del otro lado del brazo.
	decal.normal_fade = 0.45
	decal.upper_fade = 0.3
	decal.lower_fade = 0.3
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 30.0
	decal.distance_fade_length = 10.0
	var size := randf_range(0.22, 0.34) * clampf(power, 0.8, 1.8)
	decal.size = Vector3(size, 0.22, size * 1.5)
	holder.add_child(decal)
	# +Y hacia fuera del cuerpo (contra el golpe), +Z hacia abajo por la superficie: en la imagen,
	# abajo es por donde corren los regueros. La mancha del golpe queda arriba, en el punto.
	var out := -direction.normalized() if direction.length_squared() > 1e-6 else (point - holder.global_position).normalized()
	var down := CombatFx._down()
	var along := down - out * down.dot(out)
	if along.length_squared() < 1e-4:
		along = out.cross(Vector3.RIGHT if absf(out.x) < 0.9 else Vector3.FORWARD)
	along = along.normalized()
	decal.global_transform = Transform3D(Basis(out.cross(along), out, along), point + along * size * 0.45)
	decal.create_tween().tween_property(decal, "modulate", Color(0.6, 0.45, 0.45), DRY_TIME)
	var list: Array = skel.get_meta(META_STAINS, [])
	list.append(decal)
	while list.size() > MAX_PER_BODY:
		var old: Variant = list.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	skel.set_meta(META_STAINS, list)


## Quita todas las manchas de [target].
static func clear(target: Node) -> void:
	var body := target as Node3D
	if body == null:
		return
	var skel := _skeleton(body)
	if skel == null:
		return
	for decal in skel.get_meta(META_STAINS, []):
		if is_instance_valid(decal):
			(decal as Node).queue_free()
	skel.set_meta(META_STAINS, [])


static func _skeleton(body: Node3D) -> Skeleton3D:
	var cached: Variant = body.get_meta(META_SKELETON, null)
	if cached is Skeleton3D and is_instance_valid(cached):
		return cached
	var skel := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel != null:
		body.set_meta(META_SKELETON, skel)
	return skel


## El hueso cuyo tramo (de él a su hijo) pasa más cerca de [point].
static func _nearest_bone(skel: Skeleton3D, point: Vector3) -> int:
	var local := skel.global_transform.affine_inverse() * point
	var best := -1
	var best_d := INF
	for b in skel.get_bone_count():
		var parent := skel.get_bone_parent(b)
		if parent < 0:
			continue
		var d := Geometry3D.get_closest_point_to_segment(local, skel.get_bone_global_pose(parent).origin,
				skel.get_bone_global_pose(b).origin).distance_squared_to(local)
		if d < best_d:
			best_d = d
			best = parent
	return best


## Las mallas del personaje se pueden manchar (las que se le pongan después, una armadura nueva,
## llegan limpias hasta el siguiente golpe).
static func _tag_meshes(skel: Skeleton3D) -> void:
	for node in skel.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers |= LAYER


static func _holder(skel: Skeleton3D, bone: int) -> BoneAttachment3D:
	var holder_name := HOLDER_PREFIX + str(bone)
	var holder := skel.get_node_or_null(holder_name) as BoneAttachment3D
	if holder == null:
		holder = BoneAttachment3D.new()
		holder.name = holder_name
		holder.bone_idx = bone
		skel.add_child(holder)
		# Hasta la siguiente actualización del esqueleto no tendría su sitio, y la mancha se
		# colocaría respecto a uno viejo.
		holder.on_skeleton_update()
	return holder
