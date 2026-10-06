class_name CreatureActionChannel
extends RefCounted

## Canal de animación de acción de una criatura (ataques, tambaleos; más adelante reacciones y
## amenazas), encima de todo su árbol de locomoción. Reproduce cualquier clip de su
## AnimationPlayer al ritmo que se le pida y lo cambia en marcha (el aviso lento de un zarpazo).
## Son dos ranuras (Animation → TimeSeek → TimeScale → OneShot) que se turnan: un clip que
## empieza mientras suena otro (un combo) se funde sobre él en vez de saltar desde la
## locomoción. El árbol de la escena lo comparten todas las criaturas de la especie, así que cada
## una monta el canal sobre su propia copia. Se pide con NPCController.get_action_channel().

const SLOTS := [&"act_a", &"act_b"]

var _tree: AnimationTree
var _shots: Array[AnimationNodeOneShot] = []
var _anims: Array[AnimationNodeAnimation] = []
var _slot := 0
var _playing := false


## Monta el canal en el árbol de [tree]. null si el árbol no es un BlendTree con salida.
static func build(tree: AnimationTree) -> CreatureActionChannel:
	if tree == null or not (tree.tree_root is AnimationNodeBlendTree):
		return null
	var tree_root := (tree.tree_root as AnimationNodeBlendTree).duplicate(true) as AnimationNodeBlendTree
	var connections: Array = tree_root.get("node_connections")
	var below := StringName()
	for i in range(0, connections.size(), 3):
		if connections[i] == &"output" and int(connections[i + 1]) == 0:
			below = connections[i + 2]
	if below == StringName():
		return null
	var channel := CreatureActionChannel.new()
	channel._tree = tree
	tree_root.disconnect_node(&"output", 0)
	for slot in SLOTS:
		var anim := AnimationNodeAnimation.new()
		var shot := AnimationNodeOneShot.new()
		tree_root.add_node(StringName("%s_anim" % slot), anim)
		tree_root.add_node(StringName("%s_seek" % slot), AnimationNodeTimeSeek.new())
		tree_root.add_node(StringName("%s_speed" % slot), AnimationNodeTimeScale.new())
		tree_root.add_node(slot, shot)
		tree_root.connect_node(StringName("%s_seek" % slot), 0, StringName("%s_anim" % slot))
		tree_root.connect_node(StringName("%s_speed" % slot), 0, StringName("%s_seek" % slot))
		tree_root.connect_node(slot, 0, below)
		tree_root.connect_node(slot, 1, StringName("%s_speed" % slot))
		below = slot
		channel._anims.append(anim)
		channel._shots.append(shot)
	tree_root.connect_node(&"output", 0, below)
	tree.tree_root = tree_root
	return channel


## Reproduce [anim] desde [from] a ritmo [speed], fundiéndose con lo que sonara (la locomoción o
## el clip anterior del canal).
func play(anim: StringName, speed: float = 1.0, fade_in: float = 0.3, fade_out: float = 0.4,
		from: float = 0.0) -> void:
	if is_playing():
		_tree.set("parameters/%s/request" % SLOTS[_slot], AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_slot = 1 - _slot
	var slot: StringName = SLOTS[_slot]
	_anims[_slot].animation = anim
	_shots[_slot].fadein_time = fade_in
	_shots[_slot].fadeout_time = fade_out
	_tree.set("parameters/%s_seek/seek_request" % slot, from)
	_tree.set("parameters/%s_speed/scale" % slot, speed)
	_tree.set("parameters/%s/request" % slot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_playing = true


func set_speed(speed: float) -> void:
	_tree.set("parameters/%s_speed/scale" % SLOTS[_slot], speed)


## Se funde de vuelta a la locomoción.
func stop() -> void:
	if not _playing:
		return
	_playing = false
	for slot in SLOTS:
		_tree.set("parameters/%s/request" % slot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Si el clip sigue sonando (un OneShot se apaga solo al acabar el clip).
func is_playing() -> bool:
	return _playing and bool(_tree.get("parameters/%s/active" % SLOTS[_slot]))
