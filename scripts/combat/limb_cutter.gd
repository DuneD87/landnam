class_name LimbCutter
extends RefCounted

## Corta una malla con piel por un plano que cruza un hueso, como un tajo que cercena un miembro.
##
## El plano vive en el marco de ese hueso tal y como lo ven los pesos de la piel (bind), así que el
## corte se decide sobre el reposo: aunque el codo esté doblado del todo, la mano sigue al otro lado
## del plano y se va con el antebrazo. Qué cae de cada lado no lo decide solo el plano (es infinito
## y cruzaría el tronco): un vértice se va con el miembro si su hueso dominante es el cortado o
## cuelga de él, y queda por delante del plano.
##
## Los triángulos que cruzan se parten por el plano, así que el borde es un anillo limpio y no una
## escalera de triángulos. Ese anillo se cierra con una tapa por cada lado (la carne, la grasa y el
## hueso los pinta stump_flesh.gdshader), rígida con el hueso cortado.
##
## Trabaja sobre arrays sueltos y puede ir en cualquier hilo: source() lee la malla y build() la
## monta, los dos en el hilo principal.

## Cuánto se abomba el centro de la tapa, en fracción del radio del corte.
const CAP_BULGE := 0.16
## Distancia al plano de los vértices que no se pueden medir contra él (no llevan peso del hueso
## cortado): solo dicen de qué lado están.
const FAR := 1.0e9

## Marcas por bind de la piel: ajeno, el hueso cortado, o un hueso que cuelga de él.
const OTHER := 0
const OWN := 1
const BELOW := 2


## Lo que hace falta de [mesh] para cortarla: sus superficies (arrays, blend shapes, tipo,
## material activo en [instance]) y el hueso dominante de cada vértice, por bind.
static func source(mesh: ArrayMesh, instance: MeshInstance3D) -> Dictionary:
	var data := {
		surfaces = [],
		blend_names = PackedStringArray(),
		blend_mode = mesh.blend_shape_mode,
		name = mesh.resource_name,
	}
	for b in mesh.get_blend_shape_count():
		data.blend_names.append(mesh.get_blend_shape_name(b))
	for s in mesh.get_surface_count():
		data.surfaces.append({
			arrays = mesh.surface_get_arrays(s),
			blend = mesh.surface_get_blend_shape_arrays(s),
			primitive = mesh.surface_get_primitive_type(s),
			flags = mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS,
			material = mesh.surface_get_material(s),
			active = instance.get_active_material(s) if instance != null else mesh.surface_get_material(s),
		})
	return data


## Monta una malla con [surfaces] (las que devuelve cut()). [keep_empty] conserva las superficies
## que se han quedado sin triángulos (con uno degenerado), para que los materiales que la instancia
## pone por índice de superficie sigan cayendo donde caían; si no, se quitan y cada superficie lleva
## su material activo.
static func build(surfaces: Array, blend_names: PackedStringArray, blend_mode: int, name: String,
		keep_empty: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.resource_name = name
	mesh.blend_shape_mode = blend_mode as Mesh.BlendShapeMode
	for blend_name in blend_names:
		mesh.add_blend_shape(blend_name)
	for surface: Dictionary in surfaces:
		var arrays: Array = surface.arrays
		if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			if not keep_empty:
				continue
			arrays = arrays.duplicate()
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 0, 0])
		mesh.add_surface_from_arrays(surface.primitive, arrays, surface.blend, {}, surface.flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1,
				surface.material if keep_empty else surface.get("active", surface.material))
	return mesh


## Corta [surface] (una de source() o de un corte anterior) con el corte [spec]:
## {marks: PackedByteArray (OTHER/OWN/BELOW por bind), to_bone: Array (por bind del hueso cortado
## o de los que cuelgan de él, el Transform3D que lleva la malla al marco del hueso cortado con el
## miembro estirado en reposo), bind (el del hueso cortado, -1 si la piel no lo tiene), origin y
## normal (el plano, en el marco del hueso; la normal mira hacia la punta del miembro)}.
##
## Devuelve {touched}; si el corte toca la superficie, además kept (la superficie sin el miembro),
## severed (el miembro, si [want_severed]) y, si [want_caps] y la piel conoce el hueso, cap_kept y
## cap_severed (las tapas de cada lado, superficies sueltas sin material).
static func cut(surface: Dictionary, spec: Dictionary, want_severed: bool, want_caps: bool) -> Dictionary:
	var arrays: Array = surface.arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := verts.size()
	if n == 0 or bones.is_empty() or indices.is_empty() or surface.primitive != Mesh.PRIMITIVE_TRIANGLES:
		return {touched = false}
	var wc := bones.size() / n
	var marks: PackedByteArray = spec.marks
	var to_bone: Array = spec.to_bone
	var bind: int = spec.bind
	var origin: Vector3 = spec.origin
	var normal: Vector3 = spec.normal

	# De qué lado cae cada vértice y a qué distancia del plano.
	var side := PackedByteArray()
	side.resize(n)
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(-FAR)
	var any := false
	for i in n:
		var dom := -1
		var dom_w := 0.0
		var on_bone := false
		var base := i * wc
		for k in wc:
			var w := weights[base + k]
			if w <= 0.0:
				continue
			var b := bones[base + k]
			if w > dom_w:
				dom_w = w
				dom = b
			if b < marks.size() and marks[b] == OWN:
				on_bone = true
		var mark := marks[dom] if dom >= 0 and dom < marks.size() else OTHER
		if mark == OTHER and not (on_bone and bind >= 0):
			continue
		# Lo que cuelga del hueso cortado también se mide contra el plano, con el miembro estirado:
		# así la caña de una bota, pesada al pie, se corta a la altura de la pierna y no donde
		# cambian los pesos, y una mano no se queda en el muñón por llevar el codo doblado.
		var m: Transform3D = to_bone[dom if mark != OTHER else bind]
		var s := normal.dot(m * verts[i] - origin)
		if mark != OTHER and s > 0.0:
			side[i] = 1
			dist[i] = s
			any = true
		elif s <= 0.0:
			# Lo ajeno que queda por delante del plano (el tronco, al cortar arriba) se queda, pero
			# no se puede interpolar contra él: la arista se parte por la mitad.
			dist[i] = s
	if not any:
		return {touched = false}

	var buf := Buffers.new(arrays, surface.blend, wc)
	var kept := PackedInt32Array()
	var severed := PackedInt32Array()
	var edges := {}
	# Pares de vértices nuevos: los tramos del anillo del corte.
	var rim := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var b := indices[t + 1]
		var c := indices[t + 2]
		var sa := side[a]
		var sb := side[b]
		var sc := side[c]
		if sa == sb and sb == sc:
			if sa == 1:
				severed.append(a)
				severed.append(b)
				severed.append(c)
			else:
				kept.append(a)
				kept.append(b)
				kept.append(c)
			continue
		# El vértice que queda solo a su lado va primero, sin cambiar el sentido de giro: el
		# contorno es lone → lp → p → q → lq.
		var lone := a
		var p := b
		var q := c
		if sa == sc:
			lone = b
			p = c
			q = a
		elif sa == sb:
			lone = c
			p = a
			q = b
		var lp := buf.split(lone, p, dist, edges)
		var lq := buf.split(lone, q, dist, edges)
		rim.append(lp)
		rim.append(lq)
		if side[lone] == 1:
			severed.append(lone)
			severed.append(lp)
			severed.append(lq)
			kept.append(lp)
			kept.append(p)
			kept.append(q)
			kept.append(lp)
			kept.append(q)
			kept.append(lq)
		else:
			kept.append(lone)
			kept.append(lp)
			kept.append(lq)
			severed.append(lp)
			severed.append(p)
			severed.append(q)
			severed.append(lp)
			severed.append(q)
			severed.append(lq)

	var result := {touched = true}
	result.kept = buf.surface(surface, kept)
	if want_severed:
		result.severed = buf.compact(surface, severed, marks, bind)
	if want_caps and bind >= 0 and rim.size() >= 6:
		var from_bone := (to_bone[bind] as Transform3D).affine_inverse()
		var center := from_bone * origin
		var out := (from_bone * (origin + normal) - center).normalized()
		result.cap_kept = _cap(buf, rim, center, out, bind, wc)
		result.cap_severed = _cap(buf, rim, center, -out, bind, wc)
	return result


## Tapa del corte: un abanico desde el eje del hueso (abombado hacia fuera) hasta cada tramo del
## anillo, mirando hacia [out]. COLOR.r va de 0 en el centro a 1 en el borde (la piel), y UV son
## coordenadas en el plano en radios del corte, para el ruido del shader.
static func _cap(buf: Buffers, rim: PackedInt32Array, center: Vector3, out: Vector3, bind: int,
		wc: int) -> Dictionary:
	var u := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := out.cross(u)
	var radius := 0.0
	for idx in rim:
		var d := buf.verts[idx] - center
		radius += (d - out * d.dot(out)).length()
	radius = maxf(radius / rim.size(), 1e-6)
	var tip := center + out * radius * CAP_BULGE
	var pos := PackedVector3Array([tip])
	var nor := PackedVector3Array([out])
	var uv := PackedVector2Array([Vector2.ZERO])
	var col := PackedColorArray([Color(0, 0, 0, 1)])
	var index := PackedInt32Array()
	for s in range(0, rim.size(), 2):
		var a := buf.verts[rim[s]]
		var b := buf.verts[rim[s + 1]]
		# Godot toma por cara delantera la que gira en sentido horario vista de frente.
		if (a - tip).cross(b - tip).dot(out) > 0.0:
			var swap := a
			a = b
			b = swap
		index.append(0)
		index.append(pos.size())
		index.append(pos.size() + 1)
		for point in [a, b]:
			var d: Vector3 = point - center
			d -= out * d.dot(out)
			pos.append(point)
			nor.append((out + d.normalized() * 0.35).normalized())
			uv.append(Vector2(d.dot(u), d.dot(w)) / radius)
			col.append(Color(1, 0, 0, 1))
	var bone_ids := PackedInt32Array()
	bone_ids.resize(pos.size() * wc)
	var bone_weights := PackedFloat32Array()
	bone_weights.resize(pos.size() * wc)
	for i in pos.size():
		bone_ids[i * wc] = bind
		bone_weights[i * wc] = 1.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_BONES] = bone_ids
	arrays[Mesh.ARRAY_WEIGHTS] = bone_weights
	arrays[Mesh.ARRAY_INDEX] = index
	return {
		arrays = arrays, blend = [], primitive = Mesh.PRIMITIVE_TRIANGLES,
		flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if wc == 8 else 0, material = null,
	}


## Los atributos de una superficie, copiados para añadirles los vértices del corte.
class Buffers:
	var verts: PackedVector3Array
	var normals: PackedVector3Array
	var tangents: PackedFloat32Array
	var uvs: PackedVector2Array
	var uv2s: PackedVector2Array
	var colors: PackedColorArray
	var bones: PackedInt32Array
	var weights: PackedFloat32Array
	var wc: int
	## Por blend shape: [vértices, normales, tangentes] (vacíos si no los trae).
	var blend: Array[Array] = []

	func _init(arrays: Array, blend_arrays: Array, weight_count: int) -> void:
		wc = weight_count
		verts = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		normals = _copy(arrays[Mesh.ARRAY_NORMAL], PackedVector3Array())
		tangents = _copy(arrays[Mesh.ARRAY_TANGENT], PackedFloat32Array())
		uvs = _copy(arrays[Mesh.ARRAY_TEX_UV], PackedVector2Array())
		uv2s = _copy(arrays[Mesh.ARRAY_TEX_UV2], PackedVector2Array())
		colors = _copy(arrays[Mesh.ARRAY_COLOR], PackedColorArray())
		bones = (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).duplicate()
		weights = (arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).duplicate()
		for shape: Array in blend_arrays:
			blend.append([
				_copy(shape[Mesh.ARRAY_VERTEX], PackedVector3Array()),
				_copy(shape[Mesh.ARRAY_NORMAL], PackedVector3Array()),
				_copy(shape[Mesh.ARRAY_TANGENT], PackedFloat32Array()),
			])

	static func _copy(value: Variant, empty: Variant) -> Variant:
		return value.duplicate() if value != null else empty

	## Vértice nuevo donde la arista [i]–[j] cruza el plano (uno por arista, compartido por los
	## dos triángulos que la tocan). Si uno de los dos no se puede medir, a mitad de camino.
	func split(i: int, j: int, dist: PackedFloat32Array, edges: Dictionary) -> int:
		var key := mini(i, j) * 16777216 + maxi(i, j)
		if edges.has(key):
			return edges[key]
		var f := 0.5
		if absf(dist[i]) < FAR * 0.5 and absf(dist[j]) < FAR * 0.5 and dist[i] != dist[j]:
			f = clampf(dist[i] / (dist[i] - dist[j]), 0.0, 1.0)
		var index := verts.size()
		verts.append(verts[i].lerp(verts[j], f))
		if not normals.is_empty():
			normals.append(normals[i].lerp(normals[j], f).normalized())
		if not tangents.is_empty():
			var ti := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
			var tj := Vector3(tangents[j * 4], tangents[j * 4 + 1], tangents[j * 4 + 2])
			var t := ti.lerp(tj, f).normalized()
			tangents.append(t.x)
			tangents.append(t.y)
			tangents.append(t.z)
			tangents.append(tangents[i * 4 + 3])
		if not uvs.is_empty():
			uvs.append(uvs[i].lerp(uvs[j], f))
		if not uv2s.is_empty():
			uv2s.append(uv2s[i].lerp(uv2s[j], f))
		if not colors.is_empty():
			colors.append(colors[i].lerp(colors[j], f))
		_mix_weights(i, j, f)
		for shape in blend:
			var bv: PackedVector3Array = shape[0]
			if not bv.is_empty():
				bv.append(bv[i].lerp(bv[j], f))
			var bn: PackedVector3Array = shape[1]
			if not bn.is_empty():
				bn.append(bn[i].lerp(bn[j], f).normalized())
			var bt: PackedFloat32Array = shape[2]
			if not bt.is_empty():
				for k in 4:
					bt.append(lerpf(bt[i * 4 + k], bt[j * 4 + k], f))
		edges[key] = index
		return index

	## Pesos del vértice nuevo: los de los dos extremos mezclados, quedándose con los wc mayores.
	func _mix_weights(i: int, j: int, f: float) -> void:
		var acc := {}
		for k in wc:
			var wi := weights[i * wc + k] * (1.0 - f)
			if wi > 0.0:
				acc[bones[i * wc + k]] = acc.get(bones[i * wc + k], 0.0) + wi
			var wj := weights[j * wc + k] * f
			if wj > 0.0:
				acc[bones[j * wc + k]] = acc.get(bones[j * wc + k], 0.0) + wj
		var order: Array = acc.keys()
		order.sort_custom(func(x: int, y: int) -> bool: return acc[x] > acc[y])
		var total := 0.0
		for k in mini(wc, order.size()):
			total += acc[order[k]]
		for k in wc:
			if k < order.size() and total > 0.0:
				bones.append(order[k])
				weights.append(acc[order[k]] / total)
			else:
				bones.append(0)
				weights.append(0.0)

	## La superficie entera (todos los vértices, también los del otro lado, que no se dibujan) con
	## los triángulos [index]. Así no hay que renumerar nada.
	func surface(source: Dictionary, index: PackedInt32Array) -> Dictionary:
		var arrays := _arrays()
		arrays[Mesh.ARRAY_INDEX] = index
		var shapes := []
		for shape in blend:
			shapes.append(_blend_arrays(shape[0], shape[1], shape[2]))
		var out := source.duplicate()
		out.arrays = arrays
		out.blend = shapes
		return out

	## Solo los vértices que usan los triángulos [index], renumerados (el miembro es una parte
	## pequeña de la malla y se dibuja aparte). Lo que pesaba en huesos ajenos al miembro ([marks]
	## OTHER: el hombro, el brazo de arriba) pasa al hueso cortado ([bind]; si la piel no lo tiene,
	## al del miembro que más pese): en la pieza suelta esos huesos se quedan donde estaban y
	## estirarían la malla hasta allí.
	func compact(source: Dictionary, index: PackedInt32Array, marks: PackedByteArray, bind: int) -> Dictionary:
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		remap.fill(-1)
		var used := PackedInt32Array()
		var out_index := PackedInt32Array()
		out_index.resize(index.size())
		for k in index.size():
			var v := index[k]
			if remap[v] < 0:
				remap[v] = used.size()
				used.append(v)
			out_index[k] = remap[v]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _gather3(verts, used)
		if not normals.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = _gather3(normals, used)
		if not tangents.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = _gather_f(tangents, used, 4)
		if not uvs.is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = _gather2(uvs, used)
		if not uv2s.is_empty():
			arrays[Mesh.ARRAY_TEX_UV2] = _gather2(uv2s, used)
		if not colors.is_empty():
			var c := PackedColorArray()
			c.resize(used.size())
			for k in used.size():
				c[k] = colors[used[k]]
			arrays[Mesh.ARRAY_COLOR] = c
		var b := PackedInt32Array()
		b.resize(used.size() * wc)
		for k in used.size():
			for m in wc:
				b[k * wc + m] = bones[used[k] * wc + m]
		var w := _gather_f(weights, used, wc)
		_own_weights(b, w, marks, bind)
		arrays[Mesh.ARRAY_BONES] = b
		arrays[Mesh.ARRAY_WEIGHTS] = w
		arrays[Mesh.ARRAY_INDEX] = out_index
		var shapes := []
		for shape in blend:
			var bv: PackedVector3Array = shape[0]
			var bn: PackedVector3Array = shape[1]
			var bt: PackedFloat32Array = shape[2]
			shapes.append(_blend_arrays(_gather3(bv, used) if not bv.is_empty() else bv,
					_gather3(bn, used) if not bn.is_empty() else bn,
					_gather_f(bt, used, 4) if not bt.is_empty() else bt))
		var out := source.duplicate()
		out.arrays = arrays
		out.blend = shapes
		return out

	## Pasa a [bind] (o al hueso del miembro que más pese) el peso de los huesos ajenos ([marks]).
	func _own_weights(b: PackedInt32Array, w: PackedFloat32Array, marks: PackedByteArray, bind: int) -> void:
		for v in b.size() / wc:
			var base := v * wc
			var target := bind
			if target < 0:
				var best := 0.0
				for m in wc:
					var bone := b[base + m]
					if bone < marks.size() and marks[bone] != OTHER and w[base + m] > best:
						best = w[base + m]
						target = bone
			if target < 0:
				continue
			var moved := 0.0
			var slot := -1
			for m in wc:
				var bone := b[base + m]
				if bone == target:
					slot = m
				elif w[base + m] > 0.0 and (bone >= marks.size() or marks[bone] == OTHER):
					moved += w[base + m]
					w[base + m] = 0.0
			if moved <= 0.0:
				continue
			if slot < 0:
				for m in wc:
					if w[base + m] <= 0.0:
						slot = m
						b[base + m] = target
						break
			w[base + slot] += moved

	func _arrays() -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		if not normals.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = normals
		if not tangents.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = tangents
		if not uvs.is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = uvs
		if not uv2s.is_empty():
			arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		if not colors.is_empty():
			arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		return arrays

	static func _blend_arrays(v: PackedVector3Array, n: PackedVector3Array, t: PackedFloat32Array) -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		if not v.is_empty():
			arrays[Mesh.ARRAY_VERTEX] = v
		if not n.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = n
		if not t.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = t
		return arrays

	static func _gather3(src: PackedVector3Array, used: PackedInt32Array) -> PackedVector3Array:
		var out := PackedVector3Array()
		out.resize(used.size())
		for k in used.size():
			out[k] = src[used[k]]
		return out

	static func _gather2(src: PackedVector2Array, used: PackedInt32Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(used.size())
		for k in used.size():
			out[k] = src[used[k]]
		return out

	static func _gather_f(src: PackedFloat32Array, used: PackedInt32Array, stride: int) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(used.size() * stride)
		for k in used.size():
			for m in stride:
				out[k * stride + m] = src[used[k] * stride + m]
		return out
