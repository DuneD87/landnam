class_name HumanProxyData
extends Resource

## A mesh that rides on the human (hair, beard, eyes, eyebrows, genitals...), as baked by
## tools/character/bake_character_human.gd. It keeps no morphs: HumanShape
## refits it to the morphed body exactly as MakeHuman does. Each source vertex
## is three weighted anchors plus an offset scaled by the body's measures, in
## raw MakeHuman space, then posed with the bones it is skinned to. Eyes follow
## their eyelid rings instead.

enum Kind { EYES, TEETH, TONGUE, EYEBROWS, EYELASHES, HAIR, BEARD, GENITALS }

@export var kind: Kind
## Texture role ("albedo", "normal") -> res:// path.
@export var textures := {}
## Mean colour of the albedo texture (weighted by alpha): materials tint
## relative to it, so one hair colour looks alike on every style.
@export var tone := Color.WHITE
## Whether the strands of the texture run along U (0) or V (1).
@export var strand_axis := 1
## Base surface (male base): UVs, indices, skinning; its vertices are output
## vertices, `source` maps each to its source vertex.
@export var mesh: ArrayMesh
@export var source: PackedInt32Array
## Per source vertex: four bones and weights.
@export var pose_bones: PackedInt32Array
@export var pose_weights: PackedFloat32Array
## Fit, per source vertex: three anchors, their weights and the raw offset.
@export var fit_refs: PackedInt32Array
@export var fit_weights: PackedFloat32Array
@export var fit_offsets: PackedVector3Array
## MakeHuman's offset scaling: for X, height and depth, two anchors and the
## distance they had when the asset was made. Empty when unscaled.
@export var fit_scales: PackedFloat32Array
## Eyes: per side the anchors of the eyelid ring, the side of each source
## vertex and the raw base positions.
@export var lid_rings: Array[PackedInt32Array] = []
@export var lid_side: PackedInt32Array
@export var lid_raw: PackedVector3Array

var _arrays: Array


## Base surface arrays, cached.
func arrays() -> Array:
	if _arrays.is_empty():
		_arrays = mesh.surface_get_arrays(0)
	return _arrays
