extends WorldEnvironment

func _ready() -> void:
	var material = environment.sky.sky_material as ShaderMaterial
	material.render_priority = 100

func _process(delta: float) -> void:
	pass
