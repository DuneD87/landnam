class_name SettlementFire extends Node3D

## La hoguera de la plaza de un poblado (SettlementVillagers): la de los jugadores (CampfireVisual, la
## llama, su luz y su sonido) sin lo que la hace un objeto de la partida (combustible, inventario, se
## guarda). Se enciende al atardecer, cuando el pueblo se junta en corro (Villager), y se apaga de noche.

const VISUAL := preload("res://scenes/world/campfire_visual.tscn")
const FLAME_MATERIAL := preload("res://data/resources/torch_flame_material.tres")
const FIRE_SCRIPT := preload("res://scripts/effects/volumetric_fire.gd")
const AUDIO_SCRIPT := preload("res://scripts/audio/entity_audio.gd")
## Encendida entre estas horas solares del sitio.
const LIT_FROM := 18.0
const LIT_UNTIL := 23.0
## Lo que se apartan de ella los que andan por la plaza (m).
const CLEARANCE := 1.2

var lit := false
var _visual: CampfireVisual
var _flame: MeshInstance3D
var _light: OmniLight3D
var _audio: Node


func _ready() -> void:
	_visual = VISUAL.instantiate()
	add_child(_visual)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = CampfireVisual.RADIUS
	cylinder.height = 0.24
	shape.shape = cylinder
	shape.position.y = 0.1
	body.add_child(shape)
	add_child(body)
	# Como en Campfire: antes que la llama y con este nombre (VolumetricFire la busca para que parpadee).
	_light = OmniLight3D.new()
	_light.name = "OmniLight3D"
	_light.light_color = Color(1.0, 0.68, 0.4)
	_light.light_energy = 3.0
	_light.omni_range = Campfire.LIGHT_RADIUS + 3.0
	_light.shadow_enabled = true
	_light.distance_fade_enabled = true
	_light.distance_fade_shadow = 20.0
	_light.position.y = 0.5
	add_child(_light)
	_flame = MeshInstance3D.new()
	var quad := QuadMesh.new()
	var material := FLAME_MATERIAL.duplicate() as ShaderMaterial
	material.set_shader_parameter(&"fire_height", 0.75)
	material.set_shader_parameter(&"fire_width", 0.5)
	quad.material = material
	_flame.mesh = quad
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.extra_cull_margin = 2.0
	_flame.position.y = 0.04
	_flame.set_script(FIRE_SCRIPT)
	add_child(_flame)
	_audio = Node.new()
	_audio.set_script(AUDIO_SCRIPT)
	_audio.set(&"loop_event", &"fire_loop")
	_audio.set(&"loop_autostart", false)
	_flame.add_child(_audio)
	_apply()


## Si toca que esté encendida a la hora [hour].
static func lit_at(hour: float) -> bool:
	return hour >= LIT_FROM and hour < LIT_UNTIL


func set_lit(value: bool) -> void:
	if value == lit:
		return
	lit = value
	_apply()


func _apply() -> void:
	if _flame == null:
		return
	# La llama sube por la vertical: la hoguera va en el suelo de la plaza, con su +Y hacia arriba.
	_flame.set_instance_shader_parameter(&"up_axis", global_basis.y.normalized() if is_inside_tree() else Vector3.UP)
	_visual.set_lit(lit)
	_flame.visible = lit
	_light.visible = lit
	if _audio.has_method(&"set_loop_active"):
		_audio.call(&"set_loop_active", lit)
