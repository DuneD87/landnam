class_name HumanBodyData
extends Resource

## The customisable human, as baked by tools/character/bake_character_human.gd
## from the MakeHuman export (tools/character/blender/export_mpfb_human.py).
## Everything is in the player skin space: metres, Y up, +Z forward.
##
## Body: a base mesh (the male body) and sparse morphs. A morph stores, per
## vertex, only the residual displacement left after the vertex has moved with
## the joints it is skinned to; the joints themselves move by `joint_deltas`,
## applied to the skeleton at runtime (see HumanShape and BodyProportions).
##
## Anchors: the raw MakeHuman points proxies (hair, beards, eyebrows...) are
## refitted to at runtime, with sparse raw displacements per morph. `pose`
## maps raw points to skin space per sex and bone; `ground` is where the soles
## of the raw body are, per sex, and `ground_deltas` how a morph moves them.

@export var mesh: ArrayMesh
## Body morphs. Morph m covers entries offsets[m] .. offsets[m + 1].
@export var names: PackedStringArray
@export var offsets: PackedInt32Array
@export var indices: PackedInt32Array
@export var position_deltas: PackedVector3Array
@export var normal_deltas: PackedVector3Array

## Skeleton, in the order of the player skeleton's bones.
@export var bone_names: PackedStringArray
## Joint positions of the male base.
@export var joints: PackedVector3Array
## Morph name -> joint displacement per bone.
@export var joint_deltas := {}
## Rest orientation of each bone (the player's), and the Skin binding the
## meshes to the male base joints with them.
@export var orientations: Array[Basis] = []
@export var skin: Skin
@export var skin_to_skeleton := Transform3D.IDENTITY

## Anchors, raw MakeHuman space. Anchor morph m covers anchor_offsets[m] .. [m + 1].
@export var anchors: PackedVector3Array
@export var anchor_names: PackedStringArray
@export var anchor_offsets: PackedInt32Array
@export var anchor_indices: PackedInt32Array
@export var anchor_deltas: PackedVector3Array
## Sex -> Array[Transform3D] per bone, raw -> skin space (before the ground).
@export var pose := {}
@export var ground := {}
@export var ground_deltas := {}

## Skin id -> {texture: path, tone: Color, sex: StringName}.
@export var skins := {}
## Sex -> relief normal map path; skin masks (see make_skin_masks.py).
@export var normal_maps := {}
@export var masks_texture := ""
@export var stubble_texture := ""

var _morph_index := {}


func morph(name: StringName) -> int:
	if _morph_index.is_empty():
		for i in names.size():
			_morph_index[StringName(names[i])] = i
	return _morph_index.get(name, -1)


func has_morph(name: StringName) -> bool:
	return morph(name) >= 0
