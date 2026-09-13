extends RefCounted

## Reparte 'callbk' (física) o 'proc' (idle) por script o clase. Mientras 'perf' está activo agrupa
## los nodos en prioridades contiguas (respetando la original) con un marcador delante de cada grupo.
## Dentro de la misma prioridad cambia el orden entre grupos; al apagarse la restaura y resume la pasada.

const SKIP_CLASSES := ["CollisionShape3D", "VoxelInstancerRigidBody"]
## Clases nativas que activan su procesado interno a demanda: se clasifican aunque ahora estén paradas.
const LAZY_CLASSES := ["VoxelLodTerrain", "VoxelTerrain", "VoxelInstancer", "VoxelViewer",
	"GPUParticles3D", "CPUParticles3D", "AnimationMixer", "Timer", "AudioStreamPlayer",
	"AudioStreamPlayer3D", "NavigationAgent3D"]
## Lo que corre antes del primer marcador: nodos que aún no se han clasificado.
const UNSORTED := "sin clasificar"
## Umbral de "frame malo" por grupo en el resumen.
const SLOW_US := 4000

var enabled := false
var physics := true
var _host: Node
var _keys: PackedStringArray = PackedStringArray()
var _key_index: Dictionary = {}
var _key_nodes: PackedInt32Array = PackedInt32Array()
var _key_priority: PackedInt32Array = PackedInt32Array()
var _order: Array[int] = []
var _marks: PackedInt64Array = PackedInt64Array()
var _frame_us: PackedInt64Array = PackedInt64Array([0])
var _total_us: PackedInt64Array = PackedInt64Array([0])
var _max_us: PackedInt64Array = PackedInt64Array([0])
var _slow_frames: PackedInt32Array = PackedInt32Array([0])
var _frames := 0
var _enabled_at := 0
var _markers: Array[Node] = []
var _original: Dictionary = {}
var _pending: Array[Node] = []


class Marker extends Node:
	var probe
	var index := 0

	func _process(_delta: float) -> void:
		probe.mark(index)

	func _physics_process(_delta: float) -> void:
		probe.mark(index)


func _init(physics_phase: bool) -> void:
	physics = physics_phase


func set_enabled(value: bool, host: Node) -> void:
	if enabled == value:
		return
	enabled = value
	_host = host
	if value:
		_enabled_at = Time.get_ticks_usec()
		host.get_tree().node_added.connect(_on_node_added)
		_classify(host.get_tree().root)
		print("[perf %s] %d grupos marcados; la fase se reparte por grupo." % [_label(), _keys.size()])
	else:
		host.get_tree().node_added.disconnect(_on_node_added)
		print(summary())
		_restore()


func mark(index: int) -> void:
	_marks[index] = Time.get_ticks_usec()


## Clasifica los nodos que entraron en el árbol desde el último frame.
func flush_pending() -> void:
	if not enabled or _pending.is_empty():
		return
	for node in _pending:
		if is_instance_valid(node) and node.is_inside_tree():
			_assign(node)
	_pending.clear()


## Cierra una pasada: 'first_us' es la marca de la sonda inicial y 'now_us' la del cierre.
func close_tick(first_us: int, now_us: int) -> void:
	if not enabled:
		return
	var prev := first_us
	var prev_slot := 0
	for index in _order:
		var t := _marks[index]
		if t <= 0:
			continue
		_frame_us[prev_slot] += maxi(0, t - prev)
		prev = t
		prev_slot = index + 1
		_marks[index] = 0
	_frame_us[prev_slot] += maxi(0, now_us - prev)


## Grupos más caros del frame cerrado, o "" si ninguno llega a 'min_ms'.
func report(min_ms: float = 0.3) -> String:
	if not enabled:
		return ""
	var slots: Array[int] = []
	for i in _frame_us.size():
		if _frame_us[i] >= int(min_ms * 1000.0):
			slots.append(i)
	if slots.is_empty():
		return ""
	slots.sort_custom(func(a: int, b: int) -> bool: return _frame_us[a] > _frame_us[b])
	var parts := PackedStringArray()
	for i in mini(8, slots.size()):
		var slot := slots[i]
		var label := UNSORTED if slot == 0 else "%s x%d" % [_keys[slot - 1], _key_nodes[slot - 1]]
		parts.append("%s %.1f ms" % [label, _frame_us[slot] / 1000.0])
	var line := "[pico %s] %s" % [_label(), "  ".join(parts)]
	if _frame_us[0] >= 1000:
		line += "  · " + _unsorted_census()
	return line


## Acumula el frame cerrado en el resumen de la pasada y lo pone a cero.
func reset_frame() -> void:
	if enabled:
		_frames += 1
		for i in _frame_us.size():
			var v := _frame_us[i]
			_total_us[i] += v
			_max_us[i] = maxi(_max_us[i], v)
			if v >= SLOW_US:
				_slow_frames[i] += 1
	_frame_us.fill(0)


## Resumen de la pasada por grupo: total, ms por segundo, peor frame y frames por encima de SLOW_US.
func summary() -> String:
	var seconds := maxf((Time.get_ticks_usec() - _enabled_at) / 1000000.0, 0.001)
	var slots: Array[int] = []
	for i in _total_us.size():
		if _total_us[i] >= 1000:
			slots.append(i)
	slots.sort_custom(func(a: int, b: int) -> bool: return _total_us[a] > _total_us[b])
	var lines := PackedStringArray(["[perf %s resumen] %.1f s, %d frames" % [_label(), seconds, _frames]])
	for i in mini(10, slots.size()):
		var slot := slots[i]
		var label := UNSORTED if slot == 0 else "%s x%d" % [_keys[slot - 1], _key_nodes[slot - 1]]
		lines.append("  %-34s %7.1f ms  %5.2f ms/s  peor %5.1f ms  frames>%d ms %d" % [
			label, _total_us[slot] / 1000.0, _total_us[slot] / 1000.0 / seconds,
			_max_us[slot] / 1000.0, SLOW_US / 1000, _slow_frames[slot]])
	return "\n".join(lines)


func _label() -> String:
	return "fisica" if physics else "proc"


func _on_node_added(node: Node) -> void:
	if not (node is Marker):
		_pending.append(node)


## Baja por todo el árbol: el VoxelInstancer y sus escenas cuelgan del terreno. Solo se salta los
## cuerpos de colisión del instancer, que son miles y no procesan.
func _classify(node: Node) -> void:
	if node.get_class() in SKIP_CLASSES:
		return
	_assign(node)
	for child in node.get_children(true):
		_classify(child)


func _assign(node: Node) -> void:
	if node is Marker or node == _host or node.get_parent() == _host:
		return
	if node.get_class() in SKIP_CLASSES:
		return
	var id := node.get_instance_id()
	if not (_is_processing(node) or _is_lazy(node)):
		return
	var original: int = _original.get(id, node.process_physics_priority if physics else node.process_priority)
	if original < 0:
		return
	var key := _key_for(node)
	if original != 0:
		key += "@%d" % original
	var index: int = _key_index.get(key, -1)
	if index < 0:
		index = _add_group(key, original)
	if not _original.has(id):
		_original[id] = original
		_key_nodes[index] += 1
	_set_priority(node, _key_priority[index])


func _is_processing(node: Node) -> bool:
	if physics:
		return node.is_physics_processing() or node.is_physics_processing_internal() or node.has_method("_physics_process")
	return node.is_processing() or node.is_processing_internal() or node.has_method("_process")


func _is_lazy(node: Node) -> bool:
	if node.get_script() != null:
		return false
	for c in LAZY_CLASSES:
		if node.is_class(c):
			return true
	return false


func _key_for(node: Node) -> String:
	var script: Script = node.get_script()
	var key: String = script.resource_path.get_file().get_basename() if script != null else node.get_class()
	if key.is_empty():
		key = node.get_class() + " (script interno)"
	# Tierra y Luna montan el mismo terreno: sin el dueño se suman en un solo grupo.
	if script == null and node.owner != null and (node is VoxelLodTerrain or node is VoxelInstancer):
		key += ":" + node.owner.name
	return key


## Quién está procesando ahora sin grupo. Recorre el árbol: solo se llama al volcar un pico.
func _unsorted_census() -> String:
	var counts: Dictionary = {}
	_census(_host.get_tree().root, counts)
	if counts.is_empty():
		return "sin nodos procesando fuera de grupo"
	var names := counts.keys()
	names.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	var parts := PackedStringArray()
	for i in mini(6, names.size()):
		parts.append("%s:%d" % [names[i], int(counts[names[i]])])
	return "fuera de grupo[" + " ".join(parts) + "]"


func _census(node: Node, counts: Dictionary) -> void:
	if node.get_class() in SKIP_CLASSES:
		return
	if not (node is Marker or node == _host or node.get_parent() == _host or _original.has(node.get_instance_id())):
		var active := false
		if physics:
			active = node.is_physics_processing() or node.is_physics_processing_internal()
		else:
			active = node.is_processing() or node.is_processing_internal()
		if active:
			var key := _key_for(node)
			counts[key] = int(counts.get(key, 0)) + 1
	for child in node.get_children(true):
		_census(child, counts)


## Prioridad del grupo = original x1000 + posición; el marcador va una unidad por delante.
func _add_group(key: String, original: int) -> int:
	var index := _keys.size()
	_keys.append(key)
	_key_index[key] = index
	_key_nodes.append(0)
	_key_priority.append(original * 1000 + 2 * index + 2)
	_marks.append(0)
	_frame_us.resize(index + 2)
	_total_us.resize(index + 2)
	_max_us.resize(index + 2)
	_slow_frames.resize(index + 2)
	_order.append(index)
	_order.sort_custom(func(a: int, b: int) -> bool: return _key_priority[a] < _key_priority[b])
	var marker := Marker.new()
	marker.name = "%sMarker%d" % [_label().capitalize(), index]
	marker.probe = self
	marker.index = index
	marker.process_mode = Node.PROCESS_MODE_ALWAYS
	_set_priority(marker, _key_priority[index] - 1)
	_host.add_child(marker)
	marker.set_process(not physics)
	marker.set_physics_process(physics)
	_markers.append(marker)
	return index


func _set_priority(node: Node, priority: int) -> void:
	if physics:
		node.process_physics_priority = priority
	else:
		node.process_priority = priority


func _restore() -> void:
	for id in _original:
		var node := instance_from_id(id) as Node
		if node != null:
			_set_priority(node, int(_original[id]))
	for marker in _markers:
		marker.queue_free()
	_markers.clear()
	_original.clear()
	_pending.clear()
	_keys.clear()
	_key_index.clear()
	_key_nodes.clear()
	_key_priority.clear()
	_order.clear()
	_marks.clear()
	_frame_us = PackedInt64Array([0])
	_total_us = PackedInt64Array([0])
	_max_us = PackedInt64Array([0])
	_slow_frames = PackedInt32Array([0])
	_frames = 0
