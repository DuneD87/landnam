class_name SettlementDecor extends RefCounted

## Lo que se ve de los sitios de trabajo de los poblados (SettlementWorkplace) y su decorado
## (SettlementProp), que SettlementManager pone con su casa: ni se guarda ni se recoge. La leñera (troncos
## apilados y el tajo), el huerto (montones de tierra con sus matas, cada una a su altura), el banco de
## trabajo; y barriles, cajas, sacos, arcones, el yunque y la fragua, la cruz, el letrero, el bastidor de
## pieles, el secadero de pescado y la mercancía (los objetos del juego con su escena).

const BENCH_VISUAL := "res://scenes/world/stone_workbench_visual.tscn"
## El banco (StoneWorkbenchVisual): 1,22 m de largo, 0,76 de alto y 0,47 de fondo.
const BENCH_SIZE := Vector3(1.22, 0.76, 0.47)
## La leñera, en su pose: la pila a lo largo de X detrás (-Z) y el tajo delante.
const PILE_CENTER := Vector3(0.0, 0.0, -0.95)
const PILE_SIZE := Vector3(2.2, 0.9, 0.9)
const STUMP_AT := Vector3(0.0, 0.0, 0.45)
const STUMP_RADIUS := 0.24
const STUMP_HEIGHT := 0.45
const LOG_RADIUS := 0.085
const SOIL_COLOR := Color(0.2, 0.14, 0.09)
const FORGE_VISUAL := "res://scenes/world/bronze_forge_visual.tscn"
const CHEST_VISUAL := "res://scenes/world/wooden_chest_visual.tscn"
## Medidas del decorado (m): barril (radio, alto), caja, saco (radio, alto), yunque.
const BARREL := Vector2(0.3, 0.85)
const CRATE := Vector3(0.6, 0.55, 0.6)
const SACK := Vector2(0.24, 0.55)
const ANVIL := Vector3(0.5, 0.75, 0.4)

static var _woodpile: ArrayMesh
static var _props := {}
static var _goods := {}
static var _plant: ArrayMesh
static var _mound: Mesh


## El nodo de [work] (SettlementLayout._workplace) en [frame] (de su marco, el del terreno, al del
## padre que lo vaya a llevar).
static func make(work: Dictionary, frame: Transform3D) -> Node3D:
	var pose: Transform3D = work.pose
	var node := Node3D.new()
	node.transform = frame * pose
	match StringName(work.kind):
		&"woodpile":
			var mesh := MeshInstance3D.new()
			mesh.mesh = woodpile_mesh()
			node.add_child(mesh)
			node.add_child(_body([[Vector3(PILE_SIZE.x, PILE_SIZE.y, PILE_SIZE.z), PILE_CENTER + Vector3.UP * PILE_SIZE.y * 0.5],
				[Vector3(STUMP_RADIUS * 2.0, STUMP_HEIGHT, STUMP_RADIUS * 2.0), STUMP_AT + Vector3.UP * STUMP_HEIGHT * 0.5]]))
		&"garden":
			_garden(node, pose, work.plants)
		&"bench":
			node.add_child((load(BENCH_VISUAL) as PackedScene).instantiate())
			node.add_child(_body([[BENCH_SIZE, Vector3.UP * BENCH_SIZE.y * 0.5]]))
	return node


## Quita la sombra a todo lo que se ve de [node] (un adorno, un sitio de trabajo, un lecho): son cientos
## de piezas pequeñas por poblado, cada una un dibujo más por cascada, y su sombra casi no se nota.
static func no_shadows(node: Node) -> void:
	for mesh: GeometryInstance3D in node.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Un cuerpo estático con una caja por [size, centro].
static func _body(boxes: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	for box: Array in boxes:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box[0]
		shape.shape = b
		shape.position = box[1]
		body.add_child(shape)
	return body


## Las matas del huerto en [plants] (marco del terreno), cada una sobre su montón de tierra, giradas al
## azar (con la semilla de su sitio: siempre igual).
static func _garden(node: Node3D, pose: Transform3D, plants: PackedVector3Array) -> void:
	var to_local := pose.affine_inverse()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pose.origin)
	var mounds := MultiMesh.new()
	mounds.transform_format = MultiMesh.TRANSFORM_3D
	mounds.mesh = mound_mesh()
	mounds.instance_count = plants.size()
	var tufts := MultiMesh.new()
	tufts.transform_format = MultiMesh.TRANSFORM_3D
	tufts.mesh = plant_mesh()
	tufts.instance_count = plants.size()
	for i in plants.size():
		var at := to_local * plants[i]
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		mounds.set_instance_transform(i, Transform3D(yaw, at))
		tufts.set_instance_transform(i, Transform3D(yaw.scaled(Vector3.ONE * rng.randf_range(0.75, 1.2)), at + Vector3.UP * 0.05))
	for multimesh in [mounds, tufts]:
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		node.add_child(instance)


## Troncos apilados en capas que se estrechan hacia arriba, cada uno algo movido, y el tajo: un tocón
## con un leño de pie encima.
static func woodpile_mesh() -> ArrayMesh:
	if _woodpile != null:
		return _woodpile
	var builder := ProcMesh.Builder.new()
	var bark := builder.st(WeaponMeshes.BARK)
	var wood := builder.st(WeaponMeshes.WOOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var layers := 4
	for layer in layers:
		var count := 11 - layer * 2
		var y := LOG_RADIUS + layer * LOG_RADIUS * 1.75
		for k in count:
			var x := (k - (count - 1) * 0.5) * LOG_RADIUS * 2.05
			var r := LOG_RADIUS * rng.randf_range(0.85, 1.1)
			var depth := PILE_SIZE.z * 0.5 * rng.randf_range(0.9, 1.05)
			var shift := rng.randf_range(-0.04, 0.04)
			ProcMesh.tube(bark, PackedVector3Array([PILE_CENTER + Vector3(x, y, -depth + shift),
				PILE_CENTER + Vector3(x, y, depth + shift)]), PackedVector2Array([Vector2.ONE * r, Vector2.ONE * r]), 7)
	ProcMesh.tube(bark, PackedVector3Array([STUMP_AT, STUMP_AT + Vector3.UP * STUMP_HEIGHT]),
		PackedVector2Array([Vector2.ONE * STUMP_RADIUS * 1.08, Vector2.ONE * STUMP_RADIUS]), 10, Vector3.RIGHT)
	ProcMesh.tube(wood, PackedVector3Array([STUMP_AT + Vector3(0.03, STUMP_HEIGHT, 0.0),
		STUMP_AT + Vector3(0.03, STUMP_HEIGHT + 0.3, 0.0)]),
		PackedVector2Array([Vector2.ONE * 0.08, Vector2.ONE * 0.075]), 7)
	_woodpile = builder.commit(SurvivalMeshes.make_material)
	return _woodpile


## Una mata de hojas: unas cuantas que salen del centro y se abren al subir.
static func plant_mesh() -> ArrayMesh:
	if _plant != null:
		return _plant
	var builder := ProcMesh.Builder.new()
	var leaf := builder.st(SurvivalMeshes.HERB)
	for i in 7:
		var a := TAU * i / 7.0
		var out := Vector3(cos(a), 0.0, sin(a))
		var tall := 0.28 + 0.06 * (i % 3)
		ProcMesh.tube(leaf, PackedVector3Array([Vector3.ZERO, out * 0.06 + Vector3.UP * tall * 0.6,
			out * 0.16 + Vector3.UP * tall]),
			PackedVector2Array([Vector2(0.03, 0.006), Vector2(0.035, 0.006), Vector2(0.005, 0.003)]), 4, out.cross(Vector3.UP))
	_plant = builder.commit(SurvivalMeshes.make_material)
	return _plant


## Un montón de tierra removida, achatado.
static func mound_mesh() -> Mesh:
	if _mound != null:
		return _mound
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.16
	sphere.radial_segments = 10
	sphere.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = SOIL_COLOR
	material.roughness = 1.0
	sphere.material = material
	_mound = sphere
	return _mound



## El nodo del adorno [prop] (SettlementLayout: {"kind", "pose", "item", "scale"}, en el marco del
## terreno) en [frame], o null si no se sabe dibujar.
static func prop(prop: Dictionary, frame: Transform3D) -> Node3D:
	var node := Node3D.new()
	node.transform = frame * (prop.pose as Transform3D)
	var scale := float(prop.get("scale", 1.0))
	if not is_equal_approx(scale, 1.0):
		node.transform.basis = node.transform.basis.scaled_local(Vector3.ONE * scale)
	var item := StringName(prop.get("item", &""))
	match StringName(prop.kind):
		&"barrel":
			_add_mesh(node, prop_mesh(&"barrel"))
			node.add_child(_body([[Vector3(BARREL.x * 1.8, BARREL.y, BARREL.x * 1.8), Vector3.UP * BARREL.y * 0.5]]))
		&"crate":
			_add_mesh(node, prop_mesh(&"crate"))
			node.add_child(_body([[CRATE, Vector3.UP * CRATE.y * 0.5]]))
		&"sack":
			_add_mesh(node, prop_mesh(&"sack"))
		&"anvil":
			_add_mesh(node, prop_mesh(&"anvil"))
			node.add_child(_body([[ANVIL, Vector3.UP * ANVIL.y * 0.5]]))
		&"cross":
			_add_mesh(node, prop_mesh(&"cross"))
		&"hide_rack":
			_add_mesh(node, prop_mesh(&"hide_rack"))
			node.add_child(_body([[Vector3(1.4, 1.7, 0.2), Vector3.UP * 0.85]]))
		&"fish_rack":
			_add_mesh(node, prop_mesh(&"fish_rack"))
			for k in 7:
				var fish := goods(&"raw_fish")
				if fish != null:
					fish.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, k * 0.7),
						Vector3(-0.75 + k * 0.25, 1.32, 0.0))
					node.add_child(fish)
			node.add_child(_body([[Vector3(1.9, 1.6, 0.3), Vector3.UP * 0.8]]))
		&"sign":
			_add_mesh(node, prop_mesh(&"sign"))
			var mark := goods(item)
			if mark != null:
				# La seña delante de la tabla, de cara a la calle (+Z del adorno).
				mark.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.8), SIGN_BOARD + Vector3(0, -0.05, 0.06))
				node.add_child(mark)
		&"forge":
			node.add_child((load(FORGE_VISUAL) as PackedScene).instantiate())
			node.add_child(_body([[Vector3(1.46, 0.76, 0.5), Vector3.UP * 0.38]]))
		&"chest":
			node.add_child((load(CHEST_VISUAL) as PackedScene).instantiate())
			node.add_child(_body([[Vector3(0.9, 0.6, 0.55), Vector3.UP * 0.3]]))
		&"goods":
			var shown := goods(item)
			if shown == null:
				node.free()
				return null
			node.add_child(shown)
		_:
			node.free()
			return null
	return node


static func _add_mesh(node: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	node.add_child(instance)


## Lo que se ve del objeto [id] (su escena, sin nada que no sea malla): para la mercancía y las señas.
static func goods(id: StringName) -> Node3D:
	if id == &"":
		return null
	if not _goods.has(id):
		var data: ItemData = ItemCatalog.get_item(id)
		_goods[id] = load(data.scene_path) if data != null and data.scene_path != "" and ResourceLoader.exists(data.scene_path) else null
	var scene: PackedScene = _goods[id]
	if scene == null:
		return null
	var root := Node3D.new()
	var source := scene.instantiate()
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var copy := MeshInstance3D.new()
		copy.mesh = mesh.mesh
		for i in mesh.get_surface_override_material_count():
			copy.set_surface_override_material(i, mesh.get_surface_override_material(i))
		copy.material_override = mesh.material_override
		var xform := Transform3D.IDENTITY
		var at: Node = mesh
		while at != null and at != source:
			if at is Node3D:
				xform = (at as Node3D).transform * xform
			at = at.get_parent()
		copy.transform = xform
		root.add_child(copy)
	source.free()
	return root


## Donde cuelga la tabla del letrero, en el adorno: el brazo sale del muro (z = 0) hacia +Z.
const SIGN_BOARD := Vector3(0.0, -0.45, 0.75)


## La malla del adorno [kind], hecha una vez.
static func prop_mesh(kind: StringName) -> ArrayMesh:
	if _props.has(kind):
		return _props[kind]
	var b := ProcMesh.Builder.new()
	match kind:
		&"barrel":
			var wood := b.st(WeaponMeshes.WOOD)
			var profile := []
			for i in 9:
				var t := i / 8.0
				profile.append(Vector2(BARREL.x * (0.84 + 0.16 * sin(t * PI)), BARREL.y * t))
			_turned(wood, profile, 16)
			var hoop := b.st(WeaponMeshes.IRON)
			for t: float in [0.12, 0.3, 0.7, 0.88]:
				var r := BARREL.x * (0.84 + 0.16 * sin(t * PI)) + 0.008
				_turned(hoop, [Vector2(r, BARREL.y * t - 0.02), Vector2(r, BARREL.y * t + 0.02)], 16)
		&"crate":
			var wood := b.st(WeaponMeshes.WOOD)
			ProcMesh.box(wood, Vector3.UP * CRATE.y * 0.5, CRATE - Vector3.ONE * 0.02)
			var frame := b.st(WeaponMeshes.DARK_WOOD)
			var h := CRATE * 0.5
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					ProcMesh.box(frame, Vector3(sx * (h.x - 0.03), h.y, sz * (h.z - 0.03)), Vector3(0.07, CRATE.y, 0.07))
			for y: float in [0.04, CRATE.y - 0.04]:
				for sz: float in [-1.0, 1.0]:
					ProcMesh.box(frame, Vector3(0, y, sz * (h.z - 0.02)), Vector3(CRATE.x, 0.07, 0.05))
				for sx: float in [-1.0, 1.0]:
					ProcMesh.box(frame, Vector3(sx * (h.x - 0.02), y, 0), Vector3(0.05, 0.07, CRATE.z))
			# Las tablas en cruz de las caras.
			for sz: float in [-1.0, 1.0]:
				ProcMesh.box(frame, Vector3(0, h.y, sz * (h.z + 0.005)), Vector3(CRATE.x * 1.25, 0.06, 0.02),
					Basis(Vector3.BACK, atan2(CRATE.y, CRATE.x)))
		&"sack":
			var cloth := b.st(SurvivalMeshes.PLANT_FIBER)
			_turned(cloth, [Vector2(SACK.x * 0.8, 0.0), Vector2(SACK.x, 0.08), Vector2(SACK.x * 1.02, 0.25),
				Vector2(SACK.x * 0.85, 0.4), Vector2(SACK.x * 0.35, 0.48), Vector2(SACK.x * 0.25, 0.5),
				Vector2(SACK.x * 0.45, SACK.y)], 12)
		&"anvil":
			var stump := b.st(WeaponMeshes.BARK)
			_turned(stump, [Vector2(0.26, 0.0), Vector2(0.23, 0.45)], 12)
			var stone := b.st(WeaponMeshes.STONE)
			ProcMesh.box(stone, Vector3(0, 0.6, 0), Vector3(0.42, 0.3, 0.3))
			ProcMesh.box(stone, Vector3(0.28, 0.66, 0), Vector3(0.16, 0.14, 0.14))
		&"cross":
			var wood := b.st(WeaponMeshes.DARK_WOOD)
			ProcMesh.box(wood, Vector3(0, 0.9, 0), Vector3(0.14, 1.8, 0.14))
			ProcMesh.box(wood, Vector3(0, 1.3, 0), Vector3(0.95, 0.14, 0.14))
		&"hide_rack":
			var pole := b.st(WeaponMeshes.BARK)
			for x: float in [-0.65, 0.65]:
				ProcMesh.tube(pole, PackedVector3Array([Vector3(x, 0, 0), Vector3(x, 1.75, 0)]),
					PackedVector2Array([Vector2.ONE * 0.045, Vector2.ONE * 0.04]), 6)
			for y: float in [0.25, 1.6]:
				ProcMesh.tube(pole, PackedVector3Array([Vector3(-0.75, y, 0), Vector3(0.75, y, 0)]),
					PackedVector2Array([Vector2.ONE * 0.035, Vector2.ONE * 0.035]), 6, Vector3.UP)
			var hide := b.st(SurvivalMeshes.HIDE)
			var pts := [Vector3(-0.55, 0.32, 0.01), Vector3(0.55, 0.36, 0.01), Vector3(0.5, 1.52, 0.01),
				Vector3(-0.52, 1.5, 0.01)]
			ProcMesh.quad(hide, pts[0], pts[1], pts[2], pts[3], 1.0)
			ProcMesh.quad(hide, pts[3], pts[2], pts[1], pts[0], 1.0)
			var cord := b.st(WeaponMeshes.CORD)
			for k in 4:
				var a: Vector3 = pts[k]
				var c: Vector3 = Vector3(signf(a.x) * 0.65, a.y + (0.1 if a.y > 1.0 else -0.05), 0.0)
				ProcMesh.tube(cord, PackedVector3Array([a, c]), PackedVector2Array([Vector2.ONE * 0.008, Vector2.ONE * 0.008]), 4)
		&"fish_rack":
			var pole := b.st(WeaponMeshes.BARK)
			for x: float in [-0.9, 0.9]:
				for sz: float in [-1.0, 1.0]:
					ProcMesh.tube(pole, PackedVector3Array([Vector3(x, 0, sz * 0.35), Vector3(x, 1.55, 0)]),
						PackedVector2Array([Vector2.ONE * 0.04, Vector2.ONE * 0.035]), 6)
			ProcMesh.tube(pole, PackedVector3Array([Vector3(-1.0, 1.5, 0), Vector3(1.0, 1.5, 0)]),
				PackedVector2Array([Vector2.ONE * 0.04, Vector2.ONE * 0.04]), 6, Vector3.UP)
		&"sign":
			var arm := b.st(WeaponMeshes.DARK_WOOD)
			ProcMesh.box(arm, Vector3(0, 0, 0.5), Vector3(0.08, 0.08, 1.0))
			ProcMesh.box(arm, Vector3(0, -0.25, 0.04), Vector3(0.07, 0.5, 0.07))
			ProcMesh.box(arm, Vector3(0, -0.15, 0.25), Vector3(0.05, 0.05, 0.5), Basis(Vector3.RIGHT, atan2(0.25, 0.45)))
			var board := b.st(WeaponMeshes.WOOD)
			# La tabla, de cara a la calle (+Z), colgada del brazo por dos cuerdas.
			ProcMesh.box(board, SIGN_BOARD, Vector3(0.62, 0.42, 0.05))
			ProcMesh.box(arm, Vector3(0, 0, SIGN_BOARD.z), Vector3(0.7, 0.06, 0.06))
			var cord := b.st(WeaponMeshes.CORD)
			for dx: float in [-0.25, 0.25]:
				ProcMesh.tube(cord, PackedVector3Array([Vector3(dx, -0.02, SIGN_BOARD.z), Vector3(dx, SIGN_BOARD.y + 0.21, SIGN_BOARD.z)]),
					PackedVector2Array([Vector2.ONE * 0.008, Vector2.ONE * 0.008]), 4)
	var mesh := b.commit(SurvivalMeshes.make_material)
	_props[kind] = mesh
	return mesh


## Superficie de revolución alrededor de +Y por el [profile] [(radio, y)], con las caras hacia fuera:
## un tubo vertical. ProcMesh.lathe las da al revés (sus mallas se cierran con commit(..., true)), y en
## estos builders van junto a cajas y tubos, que van del derecho.
static func _turned(st: SurfaceTool, profile: Array, segments: int) -> void:
	var points := PackedVector3Array()
	var radii := PackedVector2Array()
	for q: Vector2 in profile:
		points.append(Vector3(0.0, q.y, 0.0))
		radii.append(Vector2(q.x, q.x))
	ProcMesh.tube(st, points, radii, segments)
