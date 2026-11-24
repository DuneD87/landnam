class_name CrowdBody
extends RefCounted

## A human for the far crowd (HumanMerge.crowd): one mesh in the model's space (metres, feet at
## the origin) whose materials pose it from `bones`, the texture of its bone matrices. It has no
## skeleton, no animation player and no node of its own: any number of them stand in a MultiMesh,
## each instance with its place and the clip it plays (CrowdClips.params).

## Room for any pose around the feet.
const BOUNDS := AABB(Vector3(-1.3, -0.4, -1.3), Vector3(2.6, 2.8, 2.6))

## Beyond this from the camera (metres) a figure wears `distant`, the lighter mesh.
const DISTANT_REACH := 60.0

var mesh: ArrayMesh
var distant: ArrayMesh
var bones: ImageTexture
## What it wears and its sex: bodies stand in for each other by it (the crowd of a village).
var kind := ""


## The bodies built so far, by whose they are and by kind: a village's far crowd borrows them.
const KEPT := 128
static var _by_owner := {}
static var _order: Array = []
## Kind -> the owners whose body is of it, in the order they came.
static var _by_kind := {}


## Keeps `body` as `owner`'s (a resident's id), dropping the oldest beyond KEPT.
static func remember(owner: String, body: CrowdBody) -> void:
	if _by_owner.has(owner):
		_forget_kind(owner)
	else:
		_order.append(owner)
	_by_owner[owner] = body
	(_by_kind.get_or_add(body.kind, []) as Array).append(owner)
	while _order.size() > KEPT:
		var oldest: String = _order.pop_front()
		_forget_kind(oldest)
		_by_owner.erase(oldest)


static func _forget_kind(owner: String) -> void:
	var kind: String = (_by_owner[owner] as CrowdBody).kind
	var owners: Array = _by_kind.get(kind, [])
	owners.erase(owner)
	if owners.is_empty():
		_by_kind.erase(kind)


## `owner`'s own body if it was built, else one of its `kind` (the same one for the same owner),
## else null.
static func borrow(owner: String, kind: String) -> CrowdBody:
	if _by_owner.has(owner):
		return _by_owner[owner]
	var owners: Array = _by_kind.get(kind, [])
	return _by_owner[owners[hash(owner) % owners.size()]] if not owners.is_empty() else null


## Whether some body of `kind` was built.
static func has_kind(kind: String) -> bool:
	return _by_kind.has(kind)


## What a resident (SettlementPopulation) looks like from afar: its sex and what it wears on top.
static func kind_of(who: Dictionary) -> String:
	var outfit: Array = who.get("outfit", [])
	return "%s:%s" % [String(who.get("sex", &"")), String(outfit[0]) if not outfit.is_empty() else ""]


## `count` of it, each at the origin and idle until told otherwise; `far`, with the lighter mesh.
func instance(count := 1, far := false) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = distant if far and distant != null else mesh
	multimesh.instance_count = count
	var idle := CrowdClips.params(&"idle")
	for i in count:
		multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		multimesh.set_instance_custom_data(i, idle)
	multimesh.custom_aabb = BOUNDS
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## One of it that changes mesh with the distance by itself: a node with the two instances, each
## shown on its side of DISTANT_REACH. clip() tells both what to play.
func figure() -> Node3D:
	var node := Node3D.new()
	var near := instance(1)
	near.visibility_range_end = DISTANT_REACH
	node.add_child(near)
	if distant != null:
		var far := instance(1, true)
		far.visibility_range_begin = DISTANT_REACH
		node.add_child(far)
	return node


## What a figure() plays (CrowdClips.params).
static func clip(figure: Node3D, params: Color) -> void:
	for child in figure.get_children():
		var instance := child as MultiMeshInstance3D
		if instance != null:
			instance.multimesh.set_instance_custom_data(0, params)
