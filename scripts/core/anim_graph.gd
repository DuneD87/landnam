class_name AnimGraph
extends RefCounted

## Montaje por código de un AnimationNodeBlendTree: lo usan los canales de acción del jugador
## (PlayerCombat) y de las criaturas (CreatureActionChannel), la locomoción, la escalada, la cojera
## y los ritmos de marcha de los NPC, que se insertan en el árbol de la escena.


## El nodo que entra por la entrada [port] de [node]; vacío si no hay ninguno.
static func input_of(tree_root: AnimationNodeBlendTree, node: StringName, port: int) -> StringName:
	var connections: Array = tree_root.get("node_connections")
	for i in range(0, connections.size(), 3):
		if connections[i] == node and int(connections[i + 1]) == port:
			return connections[i + 2]
	return StringName()


## Añade [anim] como [prefix]_anim, seguido de un TimeSeek ([prefix]_seek, si [seek]) y un
## TimeScale ([prefix]_speed), para poder arrastrarlo a un instante y cambiarle el ritmo. Devuelve
## el último nodo de la cadena, [prefix]_speed, que es el que se conecta al resto.
static func add_clip(tree_root: AnimationNodeBlendTree, prefix: String, anim: AnimationNodeAnimation,
		seek: bool = true) -> StringName:
	var anim_name := StringName(prefix + "_anim")
	var speed_name := StringName(prefix + "_speed")
	tree_root.add_node(anim_name, anim)
	tree_root.add_node(speed_name, AnimationNodeTimeScale.new())
	if seek:
		var seek_name := StringName(prefix + "_seek")
		tree_root.add_node(seek_name, AnimationNodeTimeSeek.new())
		tree_root.connect_node(seek_name, 0, anim_name)
		tree_root.connect_node(speed_name, 0, seek_name)
	else:
		tree_root.connect_node(speed_name, 0, anim_name)
	return speed_name


## Filtra [node] (una mezcla) a [root_bone] y todo lo que cuelga de él en [skeleton]: lo demás sigue
## con lo de debajo (el tronco y los brazos tensan el arco mientras las piernas andan).
static func filter_branch(node: AnimationNode, skeleton: Skeleton3D, root_bone: String) -> void:
	node.filter_enabled = true
	var root := skeleton.find_bone(root_bone)
	for bone in skeleton.get_bone_count():
		var parent := bone
		while parent >= 0 and parent != root:
			parent = skeleton.get_bone_parent(parent)
		if parent == root:
			node.set_filter_path(NodePath("Armature/Skeleton3D:" + skeleton.get_bone_name(bone)), true)
