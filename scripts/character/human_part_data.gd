class_name HumanPartData
extends Resource

## One mesh of the human (body, eyes, a hair style...) as baked by
## tools/character/bake_character_human.gd: its base surface (the male body,
## in the player skin space, skinned to the player skeleton) plus sparse
## morphs. Morph `m` covers entries `offsets[m] .. offsets[m + 1]` of the flat
## arrays: vertex index and the change in position and normal at weight 1.
##
## morphable() expands the morphs into blend shapes for live editing (built
## once per part and shared); baked() applies weights to a static mesh.

enum Kind { BODY, EYES, TEETH, TONGUE, EYEBROWS, EYELASHES, HAIR }

@export var kind: Kind
## Texture role ("albedo", "normal"...) -> res:// path, for the part's material.
@export var textures := {}
## Mean colour of the albedo texture where it is opaque: materials tint
## relative to it, so one hair colour looks alike on every style.
@export var tone := Color.WHITE
@export var mesh: ArrayMesh
@export var names: PackedStringArray
@export var offsets: PackedInt32Array
@export var indices: PackedInt32Array
@export var position_deltas: PackedVector3Array
@export var normal_deltas: PackedVector3Array

var _morphable: ArrayMesh
var _base_arrays: Array


func has_morph(morph: StringName) -> bool:
	return names.has(String(morph))


## Mesh with one blend shape per morph of this part.
func morphable() -> ArrayMesh:
	if _morphable != null:
		return _morphable
	var result := ArrayMesh.new()
	# NORMALIZED with absolute targets blends as base + sum(w * (target - base));
	# RELATIVE would read the targets as deltas.
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var shapes: Array[Array] = []
	for morph in names:
		result.add_blend_shape(morph)
		var arrays := _morphed({StringName(morph): 1.0})
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]:
			shape[attribute] = arrays[attribute]
		shapes.append(shape)
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(), shapes)
	_morphable = result
	return result


## Static mesh with `weights` (morph name -> weight) applied; unknown names
## are ignored.
func baked(weights: Dictionary) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _morphed(weights))
	return result


func _arrays() -> Array:
	if _base_arrays.is_empty():
		_base_arrays = mesh.surface_get_arrays(0)
	return _base_arrays


func _morphed(weights: Dictionary) -> Array:
	var arrays := _arrays().duplicate()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
	var touched := PackedByteArray()
	touched.resize(vertices.size())
	for morph in weights:
		var w: float = weights[morph]
		var m := names.find(String(morph))
		if m < 0 or is_zero_approx(w):
			continue
		for k in range(offsets[m], offsets[m + 1]):
			var i := indices[k]
			vertices[i] += position_deltas[k] * w
			normals[i] += normal_deltas[k] * w
			touched[i] = 1
	for i in vertices.size():
		if touched[i]:
			normals[i] = normals[i].normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	return arrays
