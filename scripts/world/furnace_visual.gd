class_name FurnaceVisual
extends Node3D

## Lo que se ve del horno de fundición (Furnace), a la manera de los de la Edad del bronce:
## - una cuba de barro de 1,2 m, ancha abajo y estrecha en la chimenea, más tiznada arriba, con un
##   hueco por donde se ve el fuego;
## - la boca, un arco de barro abajo delante (+Z) por el que se saca la escoria y se ven las brasas;
## - una tobera de barro en el costado (+X) que llega de dos fuelles de piel tirados en el suelo;
## - un zócalo de piedras alrededor y unos tizones de carbón delante.
## Las piedras son las del banco de trabajo (Poly Haven, CC0); lo demás sale de ProcMesh. El origen es
## el suelo, en el centro. Lo usan Furnace y la vista previa al plantarlo (SurvivalActions). Ver
## docs/items.md.

## Para la colisión (Furnace) y la llama de la chimenea.
const RADIUS := 0.5
const HEIGHT := 1.2
## El centro de la boca, por fuera.
const MOUTH := Vector3(0.0, 0.16, 0.6)
## Brillo de las brasas encendido.
const EMBER_ENERGY := 3.0

const STONE := preload("res://models/props/workbench/stone_01/stone_01_1k.gltf")
const PEBBLES := preload("res://models/props/workbench/namaqualand_stones_01/namaqualand_stones_01_1k.gltf")

const CLAY := &"clay"
const SOOT := &"soot"
const EMBER := &"ember"

## La cuba, la boca, la tobera y los fuelles: se hace una vez y la comparten todos.
static var _shell: ArrayMesh
static var _embers: ArrayMesh

## Piedras del zócalo: [modelo, malla (lo que acaba su nombre; "" = la única), ángulo alrededor
## (grados desde +X hacia +Z), distancia al centro, giro, escala].
var STONES := [
	[STONE, "", 20.0, 0.56, 10.0, 1.5], [PEBBLES, "_a", 55.0, 0.58, 40.0, 1.3],
	[PEBBLES, "_c", 125.0, 0.57, -20.0, 1.4], [STONE, "", 160.0, 0.56, 80.0, 1.6],
	[PEBBLES, "_e", 200.0, 0.58, 15.0, 1.4], [STONE, "", 240.0, 0.55, -60.0, 1.4],
	[PEBBLES, "_b", 280.0, 0.57, 120.0, 1.5], [PEBBLES, "_d", 320.0, 0.58, 70.0, 1.6],
]

var _glow: StandardMaterial3D


func _ready() -> void:
	var shell := MeshInstance3D.new()
	shell.mesh = shell_mesh()
	add_child(shell)
	# Las brasas, con su material propio: se encienden y se apagan con cada horno.
	_glow = make_material(EMBER)
	var embers := MeshInstance3D.new()
	embers.mesh = _embers
	embers.material_override = _glow
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(embers)
	for piece in STONES:
		var mesh := _mesh(piece[0], piece[1])
		if mesh == null:
			continue
		var a := deg_to_rad(piece[2])
		var at := Vector3(cos(a), 0.0, sin(a)) * float(piece[3]) - Vector3.UP * 0.03
		_add(mesh, Basis(Vector3.UP, deg_to_rad(piece[4])).scaled(Vector3.ONE * float(piece[5])), at)
	set_lit(false)


## Brasas encendidas o apagadas.
func set_lit(lit: bool) -> void:
	if _glow != null:
		_glow.emission_energy_multiplier = EMBER_ENERGY if lit else 0.0
		_glow.albedo_color = Color(0.35, 0.12, 0.04) if lit else Color(0.05, 0.045, 0.04)


## Los materiales del horno, y los de los objetos para lo demás (la piel de los fuelles, las cañas, el
## carbón). Las piezas no cuidan el sentido de sus caras: todos se ven y se iluminan por las dos.
## Los usa también la forja (ForgeVisual).
static func make_material(kind: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = String(kind)
	match kind:
		CLAY:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.36, 0.24, 0.15), Color(0.58, 0.43, 0.29), 3.0, 61)
			mat.roughness = 0.95
		SOOT:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.08, 0.07, 0.06), Color(0.34, 0.25, 0.18), 2.5, 67)
			mat.roughness = 0.97
		EMBER:
			mat.albedo_color = Color(0.05, 0.045, 0.04)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.42, 0.1)
			mat.emission_texture = ProcMesh.noise_texture(Color(0.25, 0.05, 0.0), Color(1.0, 0.8, 0.45), 9.0, 71)
			mat.roughness = 1.0
		_:
			mat = SurvivalMeshes.make_material(kind)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## La cuba, la boca, la tobera y los fuelles, sin las piedras ni las brasas (el icono:
## SurvivalMeshes.smelting_furnace).
static func shell_mesh() -> ArrayMesh:
	if _shell == null:
		_build()
	return _shell


static func _build() -> void:
	var b := ProcMesh.Builder.new()
	# La cuba: por fuera de abajo arriba, el borde y por dentro hasta el fondo de la chimenea. La
	# mitad de abajo, de barro; la de arriba, tiznada.
	ProcMesh.lathe(b.st(CLAY), [Vector2(0.5, -0.05), Vector2(0.52, 0.1), Vector2(0.51, 0.3),
		Vector2(0.47, 0.5), Vector2(0.42, 0.66)], 20, Vector3.ZERO, 2.0, 1.5)
	ProcMesh.lathe(b.st(SOOT), [Vector2(0.42, 0.66), Vector2(0.36, 0.84), Vector2(0.3, 1.02),
		Vector2(0.28, 1.14), Vector2(0.27, 1.2), Vector2(0.21, 1.21), Vector2(0.19, 1.14),
		Vector2(0.17, 0.95)], 20, Vector3.ZERO, 2.0, 1.5)
	_arch(b.st(CLAY))
	_tuyere(b)
	_shell = b.commit(make_material)
	# Las brasas: el fondo de la chimenea y lo que se ve por la boca.
	var embers := ProcMesh.Builder.new()
	var st := embers.st(EMBER)
	ProcMesh.lathe(st, [Vector2(0.17, 0.95), Vector2(0.0, 0.93)], 16)
	# Por la boca se ven justo delante de la pared de la cuba, que la tapa por dentro.
	var mouth := _arch_ring(0.13, 0.11, 0.535)
	ProcMesh.fan(st, mouth, false)
	for k in 5:
		var a := k * 1.3
		WeaponMeshes.lump(st, Vector3(sin(a) * 0.07, 0.03, 0.565 + cos(a) * 0.015), 0.04, 101 + k, 0.6, 0.3)
	_embers = embers.commit(make_material)


## La boca: un arco de barro grueso que sale de la cuba por delante, de [inner] por dentro a [outer]
## por fuera, desde dentro de la pared hasta un poco por delante.
static func _arch(st: SurfaceTool) -> void:
	var z_in := 0.36
	var z_out := MOUTH.z
	var outer_in := _arch_ring(0.22, 0.17, z_in)
	var outer_out := _arch_ring(0.22, 0.17, z_out)
	var inner_out := _arch_ring(0.13, 0.11, z_out)
	var inner_in := _arch_ring(0.13, 0.11, z_in)
	_band(st, outer_in, outer_out)
	_band(st, outer_out, inner_out)
	_band(st, inner_out, inner_in)


## Un arco de medio punto sobre el suelo, de [half] de ancho a cada lado y con los lados rectos
## hasta [side_height], en [z]: de un pie al otro.
static func _arch_ring(half: float, side_height: float, z: float) -> PackedVector3Array:
	var ring := PackedVector3Array()
	ring.append(Vector3(half, -0.04, z))
	for k in 11:
		var a := PI * float(k) / 10.0
		ring.append(Vector3(cos(a) * half, side_height + sin(a) * half, z))
	ring.append(Vector3(-half, -0.04, z))
	return ring


## Tira de cuadriláteros entre dos líneas con los mismos puntos.
static func _band(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array) -> void:
	for i in a.size() - 1:
		ProcMesh.quad(st, a[i], a[i + 1], b[i + 1], b[i])


## La tobera, que entra en la cuba por el costado, y los dos fuelles de piel que soplan por ella, con
## sus cañas y los palos con que se pisan.
static func _tuyere(b: ProcMesh.Builder) -> void:
	var clay := b.st(CLAY)
	var nozzle := PackedVector3Array([Vector3(0.3, 0.2, 0.05), Vector3(0.62, 0.17, 0.08), Vector3(0.74, 0.12, 0.1)])
	ProcMesh.tube(clay, nozzle, PackedVector2Array([Vector2(0.045, 0.045), Vector2(0.05, 0.05),
		Vector2(0.06, 0.06)]), 9)
	var hide := b.st(SurvivalMeshes.HIDE)
	var reed := b.st(WeaponMeshes.WOOD)
	for side in [-1.0, 1.0]:
		var at := Vector3(1.02, 0.0, 0.1 + side * 0.2)
		# El fuelle: un odre de piel tumbado y aplastado, más ancho por detrás.
		var bag := []
		for k in 9:
			var t := float(k) / 8.0
			var r := 0.16 * sin(t * PI) * (0.75 + 0.25 * t) + 0.02
			bag.append(Vector2(r * (1.0 + 0.04 * sin(t * 23.0)), t * 0.4))
		# Tumbado hacia la tobera (-X) y aplastado de alto.
		var lay := Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(1.0, 0.55, 1.0))
		_lathe(hide, bag, 12, Transform3D(lay, at + Vector3(0.28, 0.09, 0.0)))
		# La caña, del fuelle a la boca de la tobera.
		ProcMesh.tube(reed, PackedVector3Array([at + Vector3(-0.12, 0.09, 0.0), Vector3(0.78, 0.12, 0.1)]),
			PackedVector2Array([Vector2(0.018, 0.018), Vector2(0.015, 0.015)]), 6)
		# El palo con que se sube y se baja.
		ProcMesh.tube(reed, PackedVector3Array([at + Vector3(0.12, 0.16, 0.0), at + Vector3(0.18, 0.62, -side * 0.04)]),
			PackedVector2Array([Vector2(0.016, 0.016), Vector2(0.013, 0.013)]), 6)
	# Unos tizones de carbón delante, a un lado de la boca.
	var coal := b.st(SurvivalMeshes.COAL)
	for k in 6:
		var a := k * 2.1
		WeaponMeshes.lump(coal, Vector3(-0.42 + cos(a) * 0.09, 0.03, 0.62 + sin(a) * 0.08), 0.05, 131 + k, 0.65, 0.3)


## Como ProcMesh.lathe, sin tapas, con los puntos llevados por [xform].
static func _lathe(st: SurfaceTool, profile: Array, segments: int, xform: Transform3D) -> void:
	var base := ProcMesh.vertex_count(st)
	for i in profile.size():
		var p: Vector2 = profile[i]
		for j in segments + 1:
			var a := TAU * float(j) / float(segments)
			ProcMesh.emit(st, Vector2(float(j) / segments, p.y * 2.0), xform * Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
	for i in profile.size() - 1:
		for j in segments:
			var a0 := base + i * (segments + 1) + j
			var b0 := a0 + segments + 1
			for index in [a0, b0, a0 + 1, a0 + 1, b0, b0 + 1]:
				st.add_index(index)


## La malla de [scene] cuyo nombre acaba en [suffix] (o la primera).
func _mesh(scene: PackedScene, suffix: String) -> Mesh:
	var source: Node = scene.instantiate()
	var found: Mesh = null
	for child in source.find_children("*", "MeshInstance3D", true, false):
		if suffix == "" or String(child.name).ends_with(suffix):
			found = (child as MeshInstance3D).mesh
			break
	source.free()
	return found


## [mesh] con el centro de su base en [at].
func _add(mesh: Mesh, basis: Basis, at: Vector3) -> void:
	var box := mesh.get_aabb()
	var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis, at - basis * base)
	add_child(mi)
