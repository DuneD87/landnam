class_name RockFragment
extends Node3D

## Trozo que se suelta de una roca que se pica (FracturedRock): sale despedido un poco hacia fuera,
## da media vuelta y cae hasta el suelo. Los que llevan piedras se pican otra vez: los grandes se
## parten en trozos más pequeños (RockFracture) y los pequeños se deshacen en piedras sueltas que
## se recogen (DroppedItem). Las esquirlas, sin piedras, se hacen polvo al caer. Si la cámara se
## aleja antes, se va.

const GROUP := &"rock_fragment"
const GRAVITY := 9.8
## Trabajo para deshacerlo: fijo más por metro de tamaño (un golpe de pico, más o menos).
const WORK := 6.0
const WORK_PER_METER := 4.0
## Por encima de este volumen (m³) se parte en trozos de más o menos SPLIT_PIECE, entre
## SPLIT_COUNT trozos.
const SPLIT_VOLUME := 0.35
const SPLIT_PIECE := 0.15
const SPLIT_COUNT := Vector2i(2, 6)
## Cuánto se hunde en el suelo (fracción del radio): asienta en vez de apoyarse en un punto.
const SINK := 0.3
## Lo que sale despedido hacia fuera antes de caer (m): al soltarse de la roca y al partirse.
const THROW := 0.7
const SPLIT_THROW := 0.25
const DESPAWN_DISTANCE := 170.0

var radius := 0.5
var _mesh: Mesh
## Volumen en el mundo (m³).
var _volume := 0.1
var _stone: ItemData
var _stones := 0
var _work := 10.0
var _done := 0.0
var _up := Vector3.UP
## La caída, en el marco del padre: de dónde a dónde, cuánto dura y lo que gira.
var _from: Transform3D
var _to: Vector3
var _up_local := Vector3.UP
var _spin_axis := Vector3.RIGHT
var _spin := 0.0
var _t := 0.0
var _duration := 0.0
var _despawn_check := 1.0


## El trozo [mesh] (centrado en su centroide, de [volume] en unidades de la malla) en [xf] (mundo,
## con la escala de la roca), con [stones] de [stone] dentro. Sale [throw] m hacia [out] y cae
## contra [up]. [exclude]: lo que no es suelo (el resto de la roca).
func setup(mesh: Mesh, xf: Transform3D, stone: ItemData, stones: int, volume: float, up: Vector3,
		out: Vector3, exclude: Array[RID], throw := THROW) -> void:
	name = "RockFragment"
	add_to_group(GameManager.RESET_ON_LOAD_GROUP)
	_mesh = mesh
	_stone = stone
	_stones = stones
	_up = up
	_volume = volume * absf(xf.basis.determinant())
	add_child(RockFracture.mesh_instance(mesh))
	var size := mesh.get_aabb().size * xf.basis.get_scale()
	radius = maxf(maxf(size.x, size.y), size.z) * 0.5
	_work = WORK + WORK_PER_METER * radius * 2.0
	global_transform = xf
	reset_physics_interpolation()
	var start := xf.origin
	var landing := start + out * (throw + radius * 0.5)
	var space := get_world_3d().direct_space_state
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(landing + up * 2.0,
		landing - up * 60.0, PhysicsLayers.WORLD, exclude))
	var rest := landing if ground.is_empty() else (ground.position as Vector3) + up * radius * (1.0 - SINK)
	var to_parent := (get_parent() as Node3D).global_transform.affine_inverse()
	_from = to_parent * xf
	_to = to_parent * rest
	_up_local = (to_parent.basis * up).normalized()
	_spin_axis = (to_parent.basis * out.cross(up)).normalized()
	if not _spin_axis.is_finite() or _spin_axis.length_squared() < 0.5:
		_spin_axis = Vector3.RIGHT
	_spin = randf_range(0.6, 1.6) * (throw / THROW)
	_duration = sqrt(2.0 * maxf((start - rest).dot(up), 0.05) / GRAVITY) + 0.25
	add_to_group(GROUP)


## Ya en el suelo y con piedras dentro: hasta entonces no se pica.
func is_ready() -> bool:
	return _t >= _duration and _stones > 0


func center() -> Vector3:
	return global_position


func _physics_process(delta: float) -> void:
	if _t < _duration:
		_t = minf(_t + delta, _duration)
		var s := _t / _duration
		# Sale con un pequeño arco (hasta 25 cm) y cae acelerando; gira mientras.
		var position_now := _from.origin.lerp(_to, s * s) + _up_local * s * (1.0 - s)
		transform = Transform3D(Basis(_spin_axis, _spin * s) * _from.basis, position_now)
		if _t >= _duration:
			_land()
		return
	_despawn_check -= delta
	if _despawn_check <= 0.0:
		_despawn_check = 1.0
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.global_position.distance_to(global_position) > DESPAWN_DISTANCE:
			queue_free()


func _land() -> void:
	var dust := clampf(radius * 0.4, 0.12, 0.4)
	if _stones > 0:
		BlockDebris.burst(self, global_position, _up, 2, dust)
		AudioManager.play_material(&"block_impact", &"rock", global_position, {"volume_offset_db": -6.0})
		return
	# Esquirla: se hace polvo contra el suelo.
	BlockDebris.burst(self, global_position, _up, 3, dust)
	AudioManager.play_material(&"block_impact", &"rock", global_position,
		{"volume_offset_db": -9.0, "pitch": randf_range(1.3, 1.6)})
	queue_free()


## Golpe de [power] dado desde [miner]: al completar el trabajo, se parte o se deshace en piedras.
func hit(power: float, miner: Node3D) -> bool:
	if not is_ready() or power <= 0.0:
		return false
	var toward := (miner.global_position - global_position) if miner != null else _up
	toward = toward - _up * toward.dot(_up)
	toward = toward.normalized() if toward.length_squared() > 1e-6 else _up
	var surface := global_position + (toward + _up).normalized() * radius * 0.8
	BlockDebris.burst(self, surface, (toward + _up).normalized(), 2, 0.15)
	AudioManager.play_material(&"block_impact", &"rock", surface,
		{"volume_offset_db": -5.0, "pitch": randf_range(1.15, 1.35)})
	_done += power
	if _done < _work:
		return true
	BlockDebris.burst(self, global_position, _up, 5, clampf(radius * 0.35, 0.15, 0.5))
	AudioManager.play_material(&"block_impact", &"rock", global_position, {"pitch": 0.9})
	if not (_volume > SPLIT_VOLUME and _stones > 1 and _split(toward)):
		if _stone != null:
			DroppedItem.spawn_at(self, _stone, _stones, global_position + toward * radius * 0.5 + _up * 0.4,
				-_up, _pile(mini(_stones, 3)))
	_stones = 0
	queue_free()
	return true


## Se parte en trozos más pequeños con sus piedras repartidas, que saltan un poco. false si la
## malla no da para partirse.
func _split(toward: Vector3) -> bool:
	var count := clampi(roundi(_volume / SPLIT_PIECE), SPLIT_COUNT.x, SPLIT_COUNT.y)
	var pieces := RockFracture.pieces_of(_mesh, count)
	if pieces.size() < 2:
		return false
	var shares := RockMining.share(_stones, pieces.map(func(piece: Dictionary) -> float: return piece.volume))
	var nothing: Array[RID] = []
	for i in pieces.size():
		var piece: Dictionary = pieces[i]
		var xf := global_transform.translated_local(piece.offset)
		var out := xf.origin - global_position
		out = out - _up * out.dot(_up)
		out = (out.normalized() if out.length_squared() > 1e-6 else toward) * 0.7 + toward * 0.3
		var fragment := RockFragment.new()
		get_parent().add_child(fragment)
		fragment.setup(piece.mesh, xf, _stone, shares[i], piece.volume, _up, out.normalized(), nothing,
			SPLIT_THROW)
	return true


## Montón de piedras: el mismo trozo, en chico.
func _pile(count: int) -> Node3D:
	var pile := Node3D.new()
	var box := _mesh.get_aabb()
	var scale := 0.18 / maxf(maxf(box.size.x, box.size.y), box.size.z)
	var spots := [Vector3(-0.08, 0.0, 0.0), Vector3(0.08, 0.0, 0.04), Vector3(0.0, 0.07, -0.02)]
	for i in count:
		var stone := RockFracture.mesh_instance(_mesh)
		var basis := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)) * Basis.from_scale(Vector3.ONE * scale)
		stone.transform = Transform3D(basis, spots[i] + Vector3.UP * 0.07 - basis * box.get_center())
		pile.add_child(stone)
	return pile
