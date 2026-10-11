class_name CampfireVisual
extends Node3D

## Lo que se ve de una hoguera:
## - el corro de piedras (Stone Fire Pit, de Poly Haven, CC0);
## - leña en tienda (Dry Branches Medium 01, de Poly Haven, CC0);
## - una calcomanía de ceniza que tizna el suelo, por irregular que sea, y que encendida enseña las
##   brasas.
## El origen es el suelo, en el centro. Lo usan Campfire y la vista previa al plantarla
## (SurvivalActions). Ver docs/items.md.

const PIT := preload("res://models/props/campfire/stone_fire_pit/stone_fire_pit_2k.gltf")
const BRANCHES := preload("res://models/props/campfire/dry_branches_medium_01/dry_branches_medium_01_1k.gltf")
const ASH := preload("res://textures/props/campfire_ash_albedo.png")
const EMBERS := preload("res://textures/props/campfire_ash_emission.png")
## El corro mide 1,45 m: se deja en 1,1. La base de sus piedras está a PIT_GROUND en su malla (el
## fondo, más abajo, es un hoyo cavado que tapa el terreno: la ceniza lo sustituye) y se hunde un
## poco para que no se vea la junta con el suelo.
const PIT_SCALE := 0.76
const PIT_GROUND := -0.045
const PIT_SINK := 0.025
## Radio por fuera de las piedras (m, ya escalado): el que se apoya en el suelo.
const RADIUS := 0.55
## Brillo de las brasas encendida.
const EMBER_ENERGY := 2.5

var decal: Decal


func _ready() -> void:
	var pit: Node3D = PIT.instantiate()
	pit.scale = Vector3.ONE * PIT_SCALE
	pit.position.y = -PIT_GROUND * PIT_SCALE - PIT_SINK
	add_child(pit)
	_add_wood()
	decal = Decal.new()
	decal.texture_albedo = ASH
	decal.texture_emission = EMBERS
	decal.emission_energy = 0.0
	# Por debajo del suelo para alcanzarlo en terreno irregular, y sin llegar a lo alto de las
	# piedras (solo se tiznan por abajo).
	decal.size = Vector3(1.3, 0.5, 1.3)
	decal.position.y = -0.13
	decal.upper_fade = 0.15
	decal.lower_fade = 0.3
	decal.normal_fade = 0.5
	add_child(decal)


## Brasas encendidas o apagadas.
func set_lit(lit: bool) -> void:
	if decal != null:
		decal.emission_energy = EMBER_ENERGY if lit else 0.0


## La leña: cuatro palos en tienda y un tronco atravesado, de las ramas del modelo, algo
## tiznados.
func _add_wood() -> void:
	var source: Node3D = BRANCHES.instantiate()
	var meshes := {}
	for child in source.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		meshes[String(mi.name).right(1)] = mi.mesh
	source.free()
	if meshes.size() < 3:
		return
	var charred := (meshes["a"] as Mesh).surface_get_material(0)
	if charred is StandardMaterial3D:
		charred = charred.duplicate()
		(charred as StandardMaterial3D).albedo_color = Color(0.55, 0.5, 0.46)
	# Palos en tienda: del pie, en el corro de dentro, a lo alto del centro. [malla, largo de la
	# malla (m), ángulo]
	for stick in [["b", 1.04, 0.3], ["c", 0.78, 1.9], ["b", 1.04, 3.4], ["c", 0.78, 4.9]]:
		var a: float = stick[2]
		var foot := Vector3(cos(a) * 0.27, 0.03, sin(a) * 0.27)
		var top := Vector3(cos(a + 0.6) * 0.035, 0.34, sin(a + 0.6) * 0.035)
		var dir := (top - foot).normalized()
		var length := foot.distance_to(top) * 1.2
		_place_log(meshes[stick[0]], charred, (foot + top) * 0.5 + dir * 0.03, dir, length / float(stick[1]))
	# Un tronco atravesado abajo.
	_place_log(meshes["a"], charred, Vector3(0.0, 0.05, 0.0), Vector3(1.0, 0.0, 0.35).normalized(), 0.33)


func _place_log(mesh: Mesh, material: Material, at: Vector3, along: Vector3, mesh_scale: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	var side := Vector3.UP.cross(along)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var basis := Basis(side, along.cross(side).normalized(), along)
	mi.transform = Transform3D(basis.scaled_local(Vector3.ONE * mesh_scale), at)
	add_child(mi)
