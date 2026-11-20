class_name RiverWater extends Node3D

## Lámina de agua propia de los ríos y lagos, a su altura (no la del mar).
##
## Los ríos van a la cota del agua horneada (RiverLevels, seg[4..5]), en cintas
## continuas a lo largo de la red (la sopa de tramos de RiverField se reconstruye en cadenas por sus
## extremos). Los lagos (RiverHydrology.extract_lakes) son láminas planas a la cota de relleno. Todo
## cuelga del VoxelLodTerrain, así que comparte sus coordenadas (las del generador) y sigue al planeta
## y al origen flotante.

const SHADER := preload("res://shaders/water/river_water.gdshader")
## Lado de la celda con que se agrupan las mallas (m).
const CHUNK := 1500.0
const VISIBLE_RANGE := 8000.0
## Lo que la cinta se mete bajo la orilla a cada lado (m).
const EDGE_MARGIN := 4.0
## Diferencia de cota de los afluentes, para que no parpadeen al solaparse con el río principal.
const TRIBUTARY_DROP := 0.05

var _material: ShaderMaterial
var _sea_radius := 0.0


## 'sea_radius': radio de la superficie del mar; los tramos que quedan por debajo (desembocaduras) no
## llevan lámina propia, ya los cubre el océano.
func build(field: Dictionary, radius: float, sea_radius: float = 0.0) -> void:
	_sea_radius = sea_radius
	for c in get_children():
		c.queue_free()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("normal_map", _make_normal_texture())
	var chunks := {}
	var t := Time.get_ticks_msec()
	var river_quads := _build_rivers(field, radius, chunks)
	var lake_quads := _build_lakes(field, radius, chunks)
	for key in chunks:
		var st: Dictionary = chunks[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = st.v
		arrays[Mesh.ARRAY_NORMAL] = st.n
		arrays[Mesh.ARRAY_TEX_UV] = st.uv
		arrays[Mesh.ARRAY_TEX_UV2] = st.uv2
		arrays[Mesh.ARRAY_INDEX] = st.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = st.origin
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = VISIBLE_RANGE
		mi.visibility_range_end_margin = 500.0
		add_child(mi)
	print("[RiverWater] %d tramos de río y %d celdas de lago en %d mallas (%.1f s)" % [river_quads, lake_quads,
		chunks.size(), (Time.get_ticks_msec() - t) / 1000.0])


## Agrega un cuadrilátero (4 vértices en orden a-b-c-d alrededor) a la malla de su celda.
static func _quad(chunks: Dictionary, pts: Array, ups: Array, uvs: Array, uv2s: Array) -> void:
	var center: Vector3 = (pts[0] + pts[2]) * 0.5
	var key := Vector3i((center / CHUNK).floor())
	if not chunks.has(key):
		chunks[key] = {"origin": (Vector3(key) + Vector3.ONE * 0.5) * CHUNK, "v": PackedVector3Array(),
			"n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(),
			"i": PackedInt32Array()}
	var st: Dictionary = chunks[key]
	var base: int = st.v.size()
	for k in 4:
		st.v.append(pts[k] - st.origin)
		st.n.append(ups[k])
		st.uv.append(uvs[k])
		st.uv2.append(uv2s[k])
	st.i.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _build_rivers(field: Dictionary, radius: float, chunks: Dictionary) -> int:
	var seg: PackedFloat32Array = field.get("seg", PackedFloat32Array())
	var count := seg.size() / 8
	if count == 0:
		return 0
	var hs: Vector2i = field.hydro_size
	var max_half := 1.0
	for k in count:
		max_half = maxf(max_half, seg[k * 8 + 6])

	# Nodos por extremo (redondeado): posición, cota del agua, semianchura y tangente acumulada.
	var node_of := {}
	var nodes_p := PackedVector3Array()
	var nodes_t := PackedVector3Array()
	var nodes_w := PackedFloat32Array()
	var seg_nodes := PackedInt32Array()
	seg_nodes.resize(count * 2)
	for k in count:
		var o := k * 8
		for e in 2:
			var key := Vector2i(roundi(seg[o + e * 2] * 64.0), roundi(seg[o + e * 2 + 1] * 64.0))
			key.x = posmod(key.x, hs.x * 64)
			var id: int = node_of.get(key, -1)
			if id < 0:
				id = nodes_p.size()
				node_of[key] = id
				nodes_p.append(RiverField.hydro_dir(seg[o + e * 2], seg[o + e * 2 + 1], hs.x, hs.y))
				nodes_t.append(Vector3.ZERO)
				nodes_w.append(0.0)
			seg_nodes[k * 2 + e] = id
	# Tangente de cada nodo: dirección de los tramos que lo tocan, pesada por anchura (el río principal
	# manda en las confluencias).
	for k in count:
		var a := seg_nodes[k * 2]
		var b := seg_nodes[k * 2 + 1]
		var d := nodes_p[b] - nodes_p[a]
		var wgt := seg[k * 8 + 6]
		nodes_t[a] += d.normalized() * wgt
		nodes_t[b] += d.normalized() * wgt
		nodes_w[a] = maxf(nodes_w[a], seg[k * 8 + 6])
		nodes_w[b] = maxf(nodes_w[b], seg[k * 8 + 7])

	# Distancia acumulada aguas abajo, para que la textura corra continua por cada cadena: los tramos
	# en orden de lecho descendente (el lecho baja aguas abajo).
	var order := range(count)
	order.sort_custom(func(x, y): return seg[x * 8 + 4] > seg[y * 8 + 4])
	var dist := PackedFloat32Array()
	dist.resize(nodes_p.size())
	for k in order:
		var a := seg_nodes[k * 2]
		var b := seg_nodes[k * 2 + 1]
		dist[b] = maxf(dist[b], dist[a] + (nodes_p[b] - nodes_p[a]).length() * radius)

	# Pendiente por nodo (media de sus tramos): por tramo, la espuma de rápidos cambiaba de golpe en
	# cada unión y dibujaba líneas rectas de orilla a orilla.
	var node_slope := PackedFloat32Array()
	var node_wsum := PackedFloat32Array()
	node_slope.resize(nodes_p.size())
	node_wsum.resize(nodes_p.size())
	for k in count:
		var o := k * 8
		var a := seg_nodes[k * 2]
		var b := seg_nodes[k * 2 + 1]
		var length_m := (nodes_p[b] - nodes_p[a]).length() * radius
		var sl := absf(seg[o + 4] - seg[o + 5]) / maxf(length_m, 1.0)
		for e in [a, b]:
			node_slope[e] += sl * length_m
			node_wsum[e] += length_m
	for i in nodes_p.size():
		node_slope[i] /= maxf(node_wsum[i], 1.0)

	for k in count:
		var o := k * 8
		var a := seg_nodes[k * 2]
		var b := seg_nodes[k * 2 + 1]
		var ups := [nodes_p[a], nodes_p[a], nodes_p[b], nodes_p[b]]
		var drop := TRIBUTARY_DROP * (1.0 - minf(seg[o + 6], seg[o + 7]) / max_half)
		var la := radius + seg[o + 4] - drop
		var lb := radius + seg[o + 5] - drop
		if la < _sea_radius + 0.2 and lb < _sea_radius + 0.2:
			continue
		# La desembocadura acaba en el nivel del mar, no inclinada hacia el fondo.
		la = maxf(la, _sea_radius)
		lb = maxf(lb, _sea_radius)
		var ta := nodes_t[a].normalized()
		var tb := nodes_t[b].normalized()
		var sa := ta.cross(nodes_p[a]).normalized() * (seg[o + 6] + EDGE_MARGIN)
		var sb := tb.cross(nodes_p[b]).normalized() * (seg[o + 7] + EDGE_MARGIN)
		var pa := nodes_p[a] * la
		var pb := nodes_p[b] * lb
		var length_m := (pb - pa).length()
		var sa_slope := node_slope[a]
		var sb_slope := node_slope[b]
		var u0 := dist[a] / 10.0
		var u1 := u0 + length_m / 10.0
		var width := (seg[o + 6] + seg[o + 7]) * 0.5 / max_half
		_quad(chunks, [pa - sa, pb - sb, pb + sb, pa + sa], ups,
			[Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)],
			[Vector2(sa_slope, width), Vector2(sb_slope, width), Vector2(sb_slope, width),
				Vector2(sa_slope, width)])
	return count


func _build_lakes(field: Dictionary, radius: float, chunks: Dictionary) -> int:
	var img: Image = field.get("lake")
	if img == null:
		return 0
	var w := img.get_width()
	var h := img.get_height()
	var levels := img.get_data().to_float32_array()
	# Lago más una celda alrededor (con la cota del vecino), que queda bajo la orilla.
	var cover := PackedFloat32Array()
	cover.resize(w * h)
	cover.fill(RiverHydrology.NO_LAKE)
	var cells := 0
	for i in w * h:
		var lv := levels[i]
		if lv == RiverHydrology.NO_LAKE:
			continue
		cells += 1
		var y := i / w
		var x := i - y * w
		for dy in range(-1, 2):
			var yy := y + dy
			if yy < 0 or yy >= h:
				continue
			for dx in range(-1, 2):
				var j := yy * w + posmod(x + dx, w)
				cover[j] = maxf(cover[j], lv)
	for i in w * h:
		var lv := cover[i]
		if lv == RiverHydrology.NO_LAKE:
			continue
		var y := i / w
		var x := i - y * w
		var r := radius + lv
		var d00 := RiverField.hydro_dir(x, y, w, h)
		var d10 := RiverField.hydro_dir(x + 1, y, w, h)
		var d11 := RiverField.hydro_dir(x + 1, y + 1, w, h)
		var d01 := RiverField.hydro_dir(x, y + 1, w, h)
		var pts := [d00 * r, d10 * r, d11 * r, d01 * r]
		var uvs := []
		for p in pts:
			uvs.append(Vector2(p.x + p.z, p.y) / 10.0)
		_quad(chunks, pts, [d00, d10, d11, d01], uvs,
			[Vector2(-1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, 1.0)])
	return cells


## Mapa de normales de olas suaves (sin costuras) para la corriente.
func _make_normal_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 4.0
	tex.noise = noise
	return tex
