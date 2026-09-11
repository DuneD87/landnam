class_name Cannonball
extends Node3D

## Bala de cañón: proyectil rápido con trayectoria propia. No es un RigidBody a propósito — avanza
## a mano cada paso de física y sondea con un rayo del punto anterior al nuevo. A 300 m/s un cuerpo
## físico recorre 5 m por frame y atraviesa un casco de un metro sin llegar a tocarlo; el rayo,
## que cubre el segmento entero, no puede saltárselo.

const SPEED := 300.0
const MAX_LIFETIME := 6.0
## Radio de la bala sin cargar, en metros. Manda a la vez sobre lo que se ve y sobre lo que rompe:
## el boquete es una esfera de este radio. Con menos de una celda de la grid rompe igualmente el
## bloque que toca, por el mínimo de damage_sphere.
const DEFAULT_RADIUS := 0.5
## Radio del disparo a plena carga, en metros. Es un número de sensación y hay que tunearlo a ojo:
## cuánto rompe depende de la geometría del blanco, no solo del radio. Sobre celda de 1 m, a 4 m son
## unos 50 bloques en un mamparo suelto y ~150 si la esfera atraviesa varias cubiertas. Derivarlo de
## IMPACT_MAX_BLOCKS era falsa precisión: ese tope supone materia maciza y contra un casco no muerde.
const MAX_CHARGED_RADIUS := 4.0
## Empujón (kg·m/s) que transmite al cuerpo golpeado. Sin esto, un impacto que abre un boquete
## enorme no mueve el barco ni un centímetro y se ve falso.
const IMPULSE := 15000.0
## Terreno y grids, estáticas y dinámicas (los cuerpos dinámicos están en las capas 1 y 2).
const HIT_MASK := 3
## Julios POR BLOQUE alcanzado, si el item no define su propio 'damage'. La energía total del
## disparo sale de esto por los bloques que se estima que caben en el boquete (ver blast_cells), así
## que un radio mayor trae su propia energía en vez de repartir el mismo presupuesto en una esfera
## más ancha. Este número decide otra cosa: cuánta dureza atraviesa (un bloque de 600 J cede con
## 600 J o más).
const DEFAULT_ENERGY_PER_BLOCK := 1200.0

## El mesh y su material son iguales en todos los disparos: se construyen una vez y se comparten.
## Crear recursos del RenderingServer por evento cuesta una espera al hilo de render.
static var _shared_mesh: Mesh = null

## Radio de ESTA bala: lo fija quien dispara, según lo que haya cargado el gatillo.
var radius: float = DEFAULT_RADIUS

var _visual: MeshInstance3D = null
var _velocity: Vector3 = Vector3.ZERO
var _energy: float = 0.0
var _planet_node: Node3D = null
var _age: float = 0.0


## Lanza la bala. Hay que añadirla a la escena ANTES de llamar aquí: coloca por global_position.
func setup(from: Vector3, direction: Vector3, energy_per_block: float, planet_node: Node3D,
	blast_radius: float = DEFAULT_RADIUS) -> void:

	radius = maxf(blast_radius, 0.05)
	_energy = energy_per_block * blast_cells()
	if _visual:
		_visual.scale = Vector3.ONE * radius
	_planet_node = planet_node
	_velocity = direction.normalized() * SPEED
	global_position = from
	reset_physics_interpolation()


func _ready() -> void:
	add_to_group("floating_origin")
	# El mesh es una esfera unidad compartida y el tamaño entra por la escala del nodo: así el
	# radio puede variar por disparo sin crear un recurso nuevo cada vez, que cuesta una espera
	# al hilo de render.
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_shared_mesh()
	_visual.scale = Vector3.ONE * radius
	add_child(_visual)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > MAX_LIFETIME:
		queue_free()
		return

	if _planet_node:
		var down: Vector3 = (_planet_node.global_pos - global_position).normalized()
		_velocity += down * _planet_node.gravity_strength * delta

	var from := global_position
	var to := from + _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = HIT_MASK
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var reached: Vector3 = to if hit.is_empty() else hit["position"]
	_hit_creatures(from, reached)

	if hit.is_empty():
		global_position = to
		return

	_on_hit(hit)


## Criaturas que la bala cruza en este paso. Peces y pájaros no tienen capa de colisión propia
## (si la tuvieran, el jugador y los barcos tropezarían con ellos), así que se buscan por grupo y
## se miden contra el segmento recorrido. No frenan la bala: encajan el impacto y el disparo sigue.
func _hit_creatures(from: Vector3, to: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(AmbientAnimal.GROUP):
		var creature := node as AmbientAnimal
		if creature == null or not creature.active:
			continue
		var reach := radius + creature.impact_radius
		var closest := Geometry3D.get_closest_point_to_segment(creature.global_position, from, to)
		if closest.distance_squared_to(creature.global_position) <= reach * reach:
			creature.take_damage(_energy, self)


func _on_hit(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var collider = hit.get("collider")
	var destroyed := 0

	if collider is DynamicGridBody:
		# A un cuerpo dinámico hay que dañarlo desde aquí: al revés que en una colisión, él no se
		# entera de nada (no hay contacto que su _integrate_forces pueda ver).
		var body := collider as DynamicGridBody
		destroyed = body.apply_damage_at(point, _energy, radius)
		body.apply_impulse(_velocity.normalized() * IMPULSE, point - body.global_position)
	elif collider is Node and (collider as Node).has_meta("grid_id"):
		destroyed = _damage_static(collider as Node, point)
	elif collider != null and collider.has_method("take_damage"):
		collider.take_damage(_energy)

	# Si algo se rompió, apply_damage_at ya ha lanzado sus cascotes; si no (terreno, blindaje que
	# aguanta), aquí va la chispa que dice que el disparo llegó a alguna parte.
	if destroyed == 0:
		BlockDebris.burst(self, point, _up_at(point), 2)

	queue_free()


func _damage_static(node: Node, point: Vector3) -> int:
	var grid := GridManager.get_grid(str(node.get_meta("grid_id")))
	if not (grid is PlanetGrid):
		return 0

	grid.begin_batch_edit()
	var result: Dictionary = grid.damage_sphere(point, _energy, radius)
	grid.end_batch_edit()

	var destroyed: int = (result["destroyed"] as Array).size()
	if destroyed > 0:
		BlockDebris.burst(self, point, _up_at(point), destroyed, grid.cell_size)
		var loudness := clampf(float(destroyed) / DynamicGridBody.IMPACT_LOUD_BLOCKS, 0.0, 1.0)
		AudioManager.play_material(&"block_impact",
			SurfaceAudio.dominant_family(result["destroyed"]), point,
			{"volume_offset_db": lerpf(-12.0, 0.0, loudness)})
	return destroyed


func _up_at(point: Vector3) -> Vector3:
	if not _planet_node:
		return Vector3.UP
	return (point - _planet_node.global_pos).normalized()


## Bloques que se espera encontrar dentro del boquete, para presupuestar la energía. Se estima como
## el DISCO que la esfera recorta en una pared (pi·r²) y no como su volumen (4/3·pi·r³): un casco es
## una cáscara, no materia maciza, y con el volumen la energía salía unas cinco veces pasada.
## Contra algo de verdad macizo se queda corta, y entonces manda la energía y no el radio, que es
## lo razonable: una bala no vacía una montaña.
func blast_cells() -> float:
	return PI * pow(maxf(radius, 0.6), 2.0)


static func _get_shared_mesh() -> Mesh:
	if _shared_mesh:
		return _shared_mesh

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 6

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.10, 0.11)
	mat.metallic = 0.8
	mat.roughness = 0.45
	mesh.material = mat

	_shared_mesh = mesh
	return _shared_mesh
