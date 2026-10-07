extends Node

## Núcleo del combate sin el planeta: barrido de hoja, hurtboxes, daño, aguante y proyectiles.
##   godot --headless --path . res://tests/combat/test_combat_core.tscn

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _target(pos: Vector3, max_health: float = 100.0) -> Dictionary:
	var body := Node3D.new()
	get_tree().root.add_child(body)
	body.global_position = pos
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = max_health
	body.add_child(health)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var box := Hurtbox.attach(body, body, shape, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)))
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.2
	var head := Hurtbox.attach(body, body, head_shape, Transform3D(Basis.IDENTITY, Vector3(0, 1.9, 0)), &"head", 1.5)
	return {"body": body, "health": health, "box": box, "head": head}


func _run() -> void:
	await get_tree().physics_frame
	var space := get_tree().root.get_world_3d().direct_space_state
	var t := _target(Vector3(0, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Una hoja que cruza de lado a lado en un solo tick no puede saltarse el cuerpo.
	var sweep := MeleeSweep.new(0.05)
	sweep.sweep(space, Vector3(-3, 1.0, 0), Vector3(-2.2, 1.0, 0))
	var hits := sweep.sweep(space, Vector3(2.2, 1.0, 0), Vector3(3, 1.0, 0))
	check(hits.size() == 1, "el barrido interpola: un tajo rápido que atraviesa el cuerpo acierta (%d)" % hits.size())
	check(sweep.sweep(space, Vector3(-3, 1.0, 0), Vector3(3, 1.0, 0)).is_empty(), "un dueño se golpea una vez por pasada")
	sweep.reset()
	check(not sweep.sweep(space, Vector3(-0.5, 1.0, 0), Vector3(0.5, 1.0, 0)).is_empty(), "reset() permite el siguiente golpe")

	# Una hoja que pasa lejos no acierta.
	sweep.reset()
	sweep.sweep(space, Vector3(-3, 1.0, 3), Vector3(-2, 1.0, 3))
	check(sweep.sweep(space, Vector3(2, 1.0, 3), Vector3(3, 1.0, 3)).is_empty(), "una hoja a 3 m no acierta")

	# Esquivar: el hurtbox apagado no se golpea.
	(t.box as Hurtbox).set_enabled(false)
	(t.head as Hurtbox).set_enabled(false)
	await get_tree().physics_frame
	sweep.reset()
	check(sweep.sweep(space, Vector3(-0.5, 1.0, 0), Vector3(0.5, 1.0, 0)).is_empty(), "hurtbox apagado (esquiva) no recibe")
	(t.box as Hurtbox).set_enabled(true)
	(t.head as Hurtbox).set_enabled(true)
	await get_tree().physics_frame

	# Si toca cabeza y cuerpo en el mismo tick, cuenta la cabeza.
	sweep.reset()
	var both := sweep.sweep(space, Vector3(0, 0.5, 0), Vector3(0, 2.1, 0))
	check(both.size() == 1 and (both[0].hurtbox as Hurtbox).part == &"head", "cabeza y cuerpo a la vez: manda la cabeza")

	# Daño: armadura y parte.
	var health: HealthComponent = t.health
	health.defense = 10.0
	var applied := (t.box as Hurtbox).receive(DamageInfo.create(30.0, null, Vector3.ZERO, Vector3.FORWARD))
	check(is_equal_approx(applied, 27.0), "armadura del 10%% reduce 30 a 27 (%.2f)" % applied)
	applied = (t.head as Hurtbox).receive(DamageInfo.create(20.0, null, Vector3.ZERO, Vector3.FORWARD))
	check(is_equal_approx(applied, 27.0), "cabeza x1,5 con armadura: 20 → 27 (%.2f)" % applied)
	var died := [false]
	health.died.connect(func(): died[0] = true)
	(t.box as Hurtbox).receive(DamageInfo.create(500.0, null, Vector3.ZERO, Vector3.FORWARD))
	check(died[0] and health.is_dead, "la vida a cero mata")
	health.revive()
	check(not health.is_dead and health.health == health.max_health, "revive() la deja llena")

	# Aguante.
	var stamina := StaminaComponent.new()
	get_tree().root.add_child(stamina)
	check(stamina.spend(60.0) and stamina.spend(60.0), "con barra se puede empezar aunque no alcance")
	check(stamina.exhausted and not stamina.spend(5.0), "agotado no se puede gastar")
	for i in 120:
		await get_tree().physics_frame
	check(not stamina.exhausted and stamina.stamina > 0.0, "se recupera tras la pausa (%.1f)" % stamina.stamina)

	# Proyectil: una flecha rápida acierta y se clava en el objetivo.
	var far := _target(Vector3(0, 0, -30))
	await get_tree().physics_frame
	var arrow := CombatProjectile.new()
	arrow.kind = CombatProjectile.Kind.ARROW
	arrow.damage = 30.0
	get_tree().root.add_child(arrow)
	arrow.launch(Vector3(0, 1.0, 0), Vector3(0, 0, -1), 60.0)
	var before: float = (far.health as HealthComponent).health
	for i in 60:
		await get_tree().physics_frame
	check((far.health as HealthComponent).health < before, "la flecha a 60 m/s acierta a 30 m (%.0f → %.0f)" % [before, (far.health as HealthComponent).health])
	check(is_instance_valid(arrow) and arrow.get_parent() == far.box, "la flecha queda clavada en el hurtbox")

	await _check_guard()

	print("COMBAT CORE TESTS: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Guardia (Guard): bloqueo de frente, nada por la espalda, parada en seco al alzarla, flechas
## solo con escudo, rotura sin aguante y el botón machacado que no abre paradas.
func _check_guard() -> void:
	var t := _target(Vector3(10, 0, 0))
	var body: Node3D = t.body
	var health: HealthComponent = t.health
	var stamina := StaminaComponent.new()
	body.add_child(stamina)
	var shield := ItemData.new()
	shield.armor_slot = ItemData.ArmorSlot.OFFHAND
	shield.guard_reduction = 0.9
	shield.guard_stability = 50.0
	shield.guard_arc = 60.0
	shield.parry_window = 0.2
	shield.guard_projectiles = true
	var guard := Guard.new()
	guard.item = shield
	guard.body = body
	guard.stamina = stamina
	health.guard = guard
	var attacker := Node3D.new()
	attacker.set_script(_parry_listener())
	add_child(attacker)
	attacker.global_position = body.global_position + Vector3(0, 0, 2)
	await get_tree().physics_frame
	# El cuerpo mira por +Z: el atacante, delante.
	var hit := func(dir: Vector3, ranged := false, parryable := true) -> DamageInfo:
		var info := DamageInfo.create(40.0, attacker, body.global_position, dir, 40.0)
		info.ranged = ranged
		info.parryable = parryable
		return info
	guard.raise()
	var info: DamageInfo = hit.call(Vector3(0, 0, -1))
	var before := health.health
	health.receive_hit(info)
	check(info.guarded == Guard.Result.PARRIED and health.health == before and attacker.parried == 1,
		"al alzarla, un golpe de frente se para en seco y el atacante se entera (%d)" % attacker.parried)
	guard.raised_time = 0.5
	info = hit.call(Vector3(0, 0, -1))
	var st_before := stamina.stamina
	before = health.health
	health.receive_hit(info)
	check(info.guarded == Guard.Result.BLOCKED and is_equal_approx(before - health.health, 4.0) and info.poise == 0.0,
		"pasada la ventana se bloquea: 40 → %.0f y no tambalea" % (before - health.health))
	check(stamina.stamina < st_before, "bloquear cuesta aguante (%.0f → %.0f)" % [st_before, stamina.stamina])
	info = hit.call(Vector3(0, 0, 1))
	before = health.health
	health.receive_hit(info)
	check(info.guarded == Guard.Result.NONE and before - health.health > 30.0, "por la espalda no para nada")
	info = hit.call(Vector3(0, 0, -1), true)
	health.receive_hit(info)
	check(info.guarded == Guard.Result.BLOCKED, "el escudo para flechas")
	guard.lower()
	guard.raise()
	info = hit.call(Vector3(0, 0, -1), false, false)
	health.receive_hit(info)
	check(info.guarded == Guard.Result.BLOCKED, "una embestida (no se puede parar) se bloquea aunque se alce justo")
	# Machacar el botón: alzarla y bajarla sin parar nada cierra las paradas un rato.
	guard.lower()
	guard.raise()
	guard.lower()
	guard.raise()
	check(not guard.in_parry_window(), "machacar el botón no abre otra parada enseguida")
	guard.lower()
	var sword := ItemData.new()
	sword.two_handed = true
	sword.guard_reduction = 0.6
	sword.guard_arc = 50.0
	guard.item = sword
	guard.raise()
	guard.raised_time = 1.0
	info = hit.call(Vector3(0, 0, -1), true)
	health.receive_hit(info)
	check(info.guarded == Guard.Result.NONE, "una espada no para flechas")
	stamina.stamina = 3.0
	health.revive()
	info = hit.call(Vector3(0, 0, -1))
	before = health.health
	health.receive_hit(info)
	check(info.guarded == Guard.Result.BROKEN and info.poise >= Guard.BREAK_POISE and before - health.health > 16.0,
		"sin aguante la guardia cede: pasa casi todo (%.0f) y tambalea" % (before - health.health))
	health.guard = null
	attacker.queue_free()
	body.queue_free()


func _parry_listener() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar parried := 0\nfunc on_parried(_info) -> void:\n\tparried += 1\n"
	script.reload()
	return script
