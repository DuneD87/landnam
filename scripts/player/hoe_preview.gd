class_name HoePreview
extends Node3D

## Lo que va a allanar la azada mientras se lleva en la mano, apuntado igual que el golpe
## (TerrainLeveling.aim): un círculo en el plano al que quedará el suelo, del radio que se allana del
## todo, un aro tenue donde se acaba el borde y un velo dentro. Lo que asoma por encima del velo se
## cortará y lo que queda por debajo se rellenará; a través del terreno se ve más tenue. Ocre
## allanando a lo de alrededor, azul con el golpe pesado (a los pies) y rojo sobre la roca, donde la
## azada rebota.

const LEVEL_COLOR := Color(0.95, 0.80, 0.45)
const FEET_COLOR := Color(0.50, 0.80, 0.98)
const ROCK_COLOR := Color(0.95, 0.35, 0.30)
## Opacidad del círculo, del aro del borde y del velo. Lo que se ve a través del terreno lleva
## THROUGH de la suya.
const RING_ALPHA := 0.85
const EDGE_ALPHA := 0.4
const VEIL_ALPHA := 0.12
const THROUGH := 0.35
## Grosor de las líneas (m) y lo que se levanta sobre el plano para no parpadear con un suelo que ya
## está a nivel.
const LINE := 0.05
const LIFT := 0.03
const SEGMENTS := 64

var _player: PlayerController
## {"material", "through" (su pasada sin profundidad), "alpha"} por pieza.
var _parts: Array[Dictionary] = []


func setup(player: PlayerController) -> void:
	_player = player
	name = "HoePreview"
	top_level = true
	visible = false
	_add_part(_annulus(TerrainLeveling.RADIUS - LINE, TerrainLeveling.RADIUS), RING_ALPHA)
	_add_part(_annulus(TerrainLeveling.EDGE - LINE * 0.6, TerrainLeveling.EDGE), EDGE_ALPHA)
	_add_part(_annulus(0.0, TerrainLeveling.RADIUS - LINE), VEIL_ALPHA)


func _process(_delta: float) -> void:
	var aim := TerrainLeveling.aim(_player, _player.camera, _player.combat.is_heavy_swing()) if _active() else {}
	visible = not aim.is_empty()
	if not visible:
		return
	var color := ROCK_COLOR if aim.rock else (FEET_COLOR if _player.combat.is_heavy_swing() else LEVEL_COLOR)
	global_transform = Transform3D(TerrainLeveling.frame(aim.up), aim.center + aim.up * LIFT)
	for part in _parts:
		(part.material as StandardMaterial3D).albedo_color = Color(color, part.alpha)
		(part.through as StandardMaterial3D).albedo_color = Color(color, part.alpha * THROUGH)


## Con la azada en la mano y en situación de golpear: no nadando, cayendo ni trepando, ni con el
## inventario abierto o construyendo.
func _active() -> bool:
	var p := _player
	return TerrainLeveling.levels(p.combat.weapon()) and p.visible and p.input_enabled \
		and not p.free_flight_enabled and p.camera != null and not p.inventory_ui.visible \
		and not p.building_system.build_mode and not p.combat.is_dead() and not p.climb.is_active() \
		and not p.movement.is_swimming and not p.movement.is_falling


func _add_part(mesh: Mesh, alpha: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	var through := material.duplicate() as StandardMaterial3D
	through.no_depth_test = true
	material.next_pass = through
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_parts.append({"material": material, "through": through, "alpha": alpha})


## Corona plana en XZ entre [inner] y [outer]; con [inner] 0, un disco.
static func _annulus(inner: float, outer: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for i in SEGMENTS:
		var a := Vector3(cos(TAU * i / SEGMENTS), 0.0, sin(TAU * i / SEGMENTS))
		var b := Vector3(cos(TAU * (i + 1) / SEGMENTS), 0.0, sin(TAU * (i + 1) / SEGMENTS))
		if inner > 0.0:
			vertices.append_array(PackedVector3Array([a * inner, a * outer, b * outer, a * inner, b * outer, b * inner]))
		else:
			vertices.append_array(PackedVector3Array([Vector3.ZERO, a * outer, b * outer]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
