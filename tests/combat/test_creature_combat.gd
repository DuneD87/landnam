extends Node

## Combate de las criaturas sin el planeta: los datos de cada especie casan con su esqueleto y sus
## clips, la elección de ataque respeta distancias, ángulos, cooldowns y lo que hace el objetivo,
## los combos encadenan lo que deben, el seguimiento se compromete, el avance se frena, la
## armadura aguanta y un zarpazo del oso (canal de animación + huesos + barrido) hiere de verdad a
## lo que tiene delante.
##   godot --headless --path . res://tests/combat/test_creature_combat.tscn

const ANIMALS_DIR := "res://scenes/animals"

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	await get_tree().physics_frame
	_check_profiles()
	await _check_turn()
	await _check_pick()
	await _check_situations()
	await _check_follow_ups()
	await _check_runner_steering()
	await _check_swipe_hits()
	await _check_attacks_land()
	await _check_territory()
	await _check_home_and_gait()
	_check_sound_events()
	_check_player_voice()
	print("CREATURE COMBAT TESTS: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Cada escena de animal con CreatureCombatState: perfil puesto, ids únicos, clips en su
## AnimationPlayer, ventanas dentro del ataque, huesos en su esqueleto y combos que existen.
func _check_profiles() -> void:
	var checked := 0
	for file in DirAccess.get_files_at(ANIMALS_DIR):
		if not file.ends_with(".tscn"):
			continue
		var animal := (load("%s/%s" % [ANIMALS_DIR, file]) as PackedScene).instantiate() as NPCController
		if animal == null:
			continue
		add_child(animal)
		for state in animal.ai_controller.get_children():
			if not state is CreatureCombatState:
				continue
			checked += 1
			_check_profile(file, animal, (state as CreatureCombatState).profile)
		animal.queue_free()
	check(checked > 0, "hay escenas con CreatureCombatState (%d)" % checked)


func _check_profile(file: String, animal: NPCController, profile: CreatureCombatProfile) -> void:
	if profile == null:
		check(false, "%s: CreatureCombatState sin perfil" % file)
		return
	check(not profile.attacks.is_empty(), "%s: el perfil trae ataques" % file)
	var player := animal.npc_model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var skeleton := animal.get_skeleton()
	var ids := {}
	for attack in profile.attacks:
		ids[attack.id] = ids.get(attack.id, 0) + 1
	var problems: PackedStringArray = []
	for attack in profile.attacks:
		if ids[attack.id] > 1:
			problems.append("id repetido %s" % attack.id)
		if not player.has_animation(attack.anim):
			problems.append("%s: no hay clip '%s'" % [attack.id, attack.anim])
		if attack.distance.x > attack.distance.y:
			problems.append("%s: distancia al revés" % attack.id)
		if attack.commit_time() > attack.first_hit():
			problems.append("%s: se compromete después del primer golpe" % attack.id)
		for follow in attack.follow_ups:
			if not ids.has(follow):
				problems.append("%s: encadena '%s', que no está en el perfil" % [attack.id, follow])
		for hit in attack.hits:
			if hit.from > hit.to or hit.to > attack.end:
				problems.append("%s: ventana %.2f–%.2f fuera de 0–%.2f" % [attack.id, hit.from, hit.to, attack.end])
			for bone in hit.bones:
				if skeleton == null or skeleton.find_bone(bone) < 0:
					problems.append("%s: no hay hueso '%s'" % [attack.id, bone])
	for anim in profile.stagger_anims + [profile.threaten_anim]:
		if anim != &"" and not player.has_animation(anim):
			problems.append("no hay clip '%s'" % anim)
	# Todo nombre de sonido de los datos suena (con clips o sintetizado).
	var sounds: Array = [profile.threaten_sound, profile.attack_sound, profile.swing_sound,
		profile.stagger_sound, animal.hurt_sound, animal.death_sound]
	for attack in profile.attacks:
		sounds.append(attack.sound)
		for hit in attack.hits:
			sounds.append(hit.sound)
	for state in animal.ai_controller.get_children():
		if state is TerritorialState:
			sounds.append((state as TerritorialState).warn_sound)
	for sound in sounds:
		if sound != &"" and not CombatFx.has_sound(sound):
			problems.append("no suena '%s'" % sound)
	check(problems.is_empty(), "%s: ataques coherentes con su esqueleto y sus clips %s" % [file, problems])


## El giro limitado del cuerpo: no pasa del máximo por paso y llega si le sobra.
func _check_turn() -> void:
	var bear := _spawn_bear()
	await get_tree().physics_frame
	bear._turn_toward(Vector3.RIGHT, deg_to_rad(30.0))
	var turned := rad_to_deg(Vector3.BACK.angle_to(bear.global_basis.z.normalized()))
	check(absf(turned - 30.0) < 0.5, "el giro limitado no pasa de 30° por paso (%.1f°)" % turned)
	bear._turn_toward(Vector3.RIGHT, deg_to_rad(180.0))
	check(bear.global_basis.z.normalized().distance_to(Vector3.RIGHT) < 0.01, "y llega si le sobra")
	bear.queue_free()


## La elección: solo los que llegan a la distancia, dentro de su ángulo y sin cooldown.
func _check_pick() -> void:
	var bear := _spawn_bear()
	var target := _target(Vector3(0, 0, 5))
	await get_tree().physics_frame
	var state := _engage(bear, target.body)
	var close_ids := {}
	var far_ids := {}
	for i in 80:
		var a := state._pick_attack(2.0, state.profile.attacks)
		if a != null:
			close_ids[a.id] = true
		var b := state._pick_attack(7.0, state.profile.attacks)
		if b != null:
			far_ids[b.id] = true
	check(close_ids.has(&"swipe") and close_ids.has(&"double") and not close_ids.has(&"charge"),
		"a 2 m elige zarpazos y no embiste (%s)" % [close_ids.keys()])
	check(far_ids.keys() == [&"charge"], "a 7 m solo embiste (%s)" % [far_ids.keys()])
	check(state._pick_attack(20.0, state.profile.attacks) == null, "a 20 m no llega ningún ataque")
	state._cooldowns[&"charge"] = 2.0
	check(state._pick_attack(7.0, state.profile.attacks) == null, "con la embestida en cooldown, a 7 m no ataca")
	state._cooldowns.clear()
	# De lado (90°) la embestida (45° como mucho) no sale.
	target.body.global_position = Vector3(7, 0, 0)
	check(state._pick_attack(7.0, state.profile.attacks) == null, "con el objetivo de lado no embiste")
	state.exit()
	bear.queue_free()
	target.body.queue_free()


## Lo que lee del objetivo y cómo cambia la elección: al que se recupera de un golpe le castiga
## con el zarpazo rápido.
func _check_situations() -> void:
	var bear := _spawn_bear()
	var target := _target(Vector3(0, 0, 2), &"recovering")
	await get_tree().physics_frame
	var state := _engage(bear, target.body)
	# Los cuerpos miran por +Z: girado media vuelta, el blanco mira al oso.
	target.body.global_basis = Basis(Vector3.UP, PI)
	var seen := CombatRead.situations(bear, target.body, Vector3.ZERO)
	check(&"recovering" in seen, "lee lo que el objetivo dice de sí mismo (%s)" % [seen])
	check(&"back_turned" not in seen, "un objetivo de cara no da la espalda")
	check(&"fleeing" in CombatRead.situations(bear, target.body, Vector3(0, 0, 6)), "alejándose a 6 m/s huye")
	target.body.global_basis = Basis.IDENTITY
	check(&"back_turned" in CombatRead.situations(bear, target.body, Vector3.ZERO), "mirando hacia fuera, da la espalda")
	target.body.global_basis = Basis(Vector3.UP, PI)
	var counts := {&"swipe": 0, &"double": 0}
	for i in 600:
		var a := state._pick_attack(2.0, state.profile.attacks)
		if a != null and counts.has(a.id):
			counts[a.id] += 1
	check(counts[&"swipe"] > counts[&"double"] * 1.4,
		"al que se recupera le castiga sobre todo con el zarpazo (%d contra %d)" % [counts[&"swipe"], counts[&"double"]])
	state.exit()
	bear.queue_free()
	target.body.queue_free()


## Los combos: solo encadena lo que dice el ataque y nunca pasa del tope.
func _check_follow_ups() -> void:
	var bear := _spawn_bear()
	var target := _target(Vector3(0, 0, 2))
	await get_tree().physics_frame
	var state := _engage(bear, target.body)
	var swipe := _attack(state, &"swipe")
	var chained := {}
	state.combo = 1
	for i in 200:
		var next := state._pick_follow_up(swipe)
		chained[next.id if next != null else &"-"] = true
	check(chained.has(&"double") and chained.has(&"-") and chained.size() == 2,
		"tras el zarpazo encadena el doble o nada (%s)" % [chained.keys()])
	state.combo = state.profile.max_combo
	var any := false
	for i in 100:
		any = any or state._pick_follow_up(swipe) != null
	check(not any, "con el combo al tope (%d) no encadena más" % state.profile.max_combo)
	state.exit()
	bear.queue_free()
	target.body.queue_free()


## Lo que el ataque pide al cuerpo: giro rápido hasta comprometerse y lento después, avance que se
## frena antes del objetivo y armadura solo en su tramo.
func _check_runner_steering() -> void:
	var bear := _spawn_bear()
	var target := _target(Vector3(0, 0, 2.0))
	await get_tree().physics_frame
	var state := _engage(bear, target.body)
	var swipe := _attack(state, &"swipe")
	var runner := state.runner
	runner.start(swipe)
	var ctl := bear.ai_controller
	var dt := 1.0 / 60.0
	var windup_rate := -1.0
	var active_rate := -1.0
	var lunge_speed := 0.0
	var armor_in := -1.0
	var armor_out := -1.0
	while runner.update(dt):
		if runner.time > 0.0 and runner.time < swipe.commit_time() and windup_rate < 0.0:
			windup_rate = ctl.turn_rate
		if runner.time > swipe.commit_time() + 0.05 and active_rate < 0.0:
			active_rate = ctl.turn_rate
		# Aquí el oso no se mueve (no hay planeta): la distancia no se gasta y el freno se ve al
		# entrar en el tramo, no al final.
		if runner.time > swipe.lunge.x and lunge_speed <= 0.0:
			lunge_speed = ctl.movement.speed
		if armor_in < 0.0 and runner.time > swipe.armor.x + 0.05:
			armor_in = runner.absorb_poise(30.0)
		if armor_out < 0.0 and runner.time > swipe.armor.y + 0.05:
			armor_out = runner.absorb_poise(30.0)
	var full := swipe.lunge.z / ((swipe.lunge.y - swipe.lunge.x) / swipe.speed)
	check(is_equal_approx(windup_rate, swipe.track_windup), "preparando gira a %.0f°/s (%.0f)" % [swipe.track_windup, windup_rate])
	check(is_equal_approx(active_rate, swipe.track_active), "comprometido gira a %.0f°/s (%.0f)" % [swipe.track_active, active_rate])
	check(lunge_speed > 0.05 and lunge_speed < full * 0.9,
		"a 2 m el avance se frena antes del objetivo (%.2f de %.2f m/s)" % [lunge_speed, full])
	check(is_equal_approx(armor_in, 0.0), "la armadura del zarpazo se traga un golpe de 30 de desgaste (%.0f)" % armor_in)
	check(is_equal_approx(armor_out, 30.0), "fuera de su tramo, no (%.0f)" % armor_out)
	state.exit()
	bear.queue_free()
	target.body.queue_free()


## Un zarpazo de verdad: el canal de animación mueve la zarpa y el barrido golpea al blanco de
## delante una sola vez, en la ventana del golpe.
func _check_swipe_hits() -> void:
	var bear := _spawn_bear()
	var target := _target(Vector3(0, 0, 1.9))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := _engage(bear, target.body)
	var swipe := _attack(state, &"swipe")
	state.runner.start(swipe)
	var health := target.health as HealthComponent
	# Las lambdas copian las variables locales: lo que cuentan va en un diccionario.
	var got := {"hits": 0, "at": -1.0}
	health.hit_received.connect(func(_info, _applied):
		got.hits += 1
		if got.at < 0.0:
			got.at = state.runner.time)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var frames := 0
	while state.runner.update(dt) and frames < 600:
		await get_tree().physics_frame
		frames += 1
	check(not state.runner.is_running(), "el zarpazo acaba (%d fotogramas)" % frames)
	check(got.hits == 1, "el zarpazo golpea una vez al blanco de delante (%d)" % got.hits)
	check(got.at >= swipe.hits[0].from and got.at <= swipe.hits[0].to + 0.05,
		"y dentro de su ventana (%.2f en %.2f–%.2f)" % [got.at, swipe.hits[0].from, swipe.hits[0].to])
	check(health.health < health.max_health, "le quita vida (%.0f)" % health.health)
	check(state.runner.landed == 1, "el ataque cuenta el golpe dado (%d)" % state.runner.landed)
	state.exit()
	bear.queue_free()
	target.body.queue_free()


## Cada ataque de cada especie, lanzado contra un blanco quieto delante en los dos extremos de su
## distancia, acierta: el alcance y las ventanas medidas casan con el clip y con el avance. El
## cuerpo se mueve y gira aquí con lo que pide el ataque (no hay planeta que lo haga).
func _check_attacks_land() -> void:
	for file in DirAccess.get_files_at(ANIMALS_DIR):
		if not file.ends_with(".tscn"):
			continue
		var scene := load("%s/%s" % [ANIMALS_DIR, file]) as PackedScene
		var probe := scene.instantiate() as NPCController
		var profile: CreatureCombatProfile = null
		if probe != null:
			for state in probe.get_node("AIController").get_children():
				if state is CreatureCombatState:
					profile = (state as CreatureCombatState).profile
			probe.free()
		if profile == null:
			continue
		for attack in profile.attacks:
			for dist in [maxf(attack.distance.x, 1.6), attack.distance.y]:
				var landed := await _land(scene, attack.id, dist)
				check(landed, "%s: %s acierta a un blanco quieto a %.1f m" % [file, attack.id, dist])


func _land(scene: PackedScene, id: StringName, dist: float) -> bool:
	var animal := scene.instantiate() as NPCController
	add_child(animal)
	animal.global_transform = Transform3D.IDENTITY
	var target := _target(Vector3(0, 0, dist))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state: CreatureCombatState = null
	for child in animal.ai_controller.get_children():
		if child is CreatureCombatState:
			state = child
	animal.ai_controller.target = target.body
	state.enter()
	state.runner.start(_attack(state, id))
	var ctl := animal.ai_controller
	var dt := 1.0 / Engine.physics_ticks_per_second
	var frames := 0
	while state.runner.update(dt) and frames < 600:
		if ctl.desired_direction != Vector3.ZERO:
			animal.global_position += ctl.desired_direction * ctl.movement.speed * dt
		if ctl.desired_facing != Vector3.ZERO:
			animal._turn_toward(ctl.desired_facing, deg_to_rad(ctl.turn_rate if ctl.turn_rate > 0.0 else 720.0) * dt)
		await get_tree().physics_frame
		frames += 1
	var landed := state.runner.landed > 0 or (target.health as HealthComponent).health < 500.0
	state.exit()
	animal.queue_free()
	target.body.queue_free()
	return landed


## Defender el territorio: vigila de lejos, avisa y se impacienta a tiro de aviso, ataca si se le
## mete encima o se le acaba la paciencia, y se calma si el intruso se va.
func _check_territory() -> void:
	var lion := (load("%s/Lion.tscn" % ANIMALS_DIR) as PackedScene).instantiate() as NPCController
	add_child(lion)
	lion.global_transform = Transform3D.IDENTITY
	var target := _target(Vector3(0, 0, 26))
	await get_tree().physics_frame
	var state := lion.ai_controller.get_node("TerritorialState") as TerritorialState
	lion.ai_controller.target = target.body
	state.annoyance = 0.0
	state.enter()
	var dt := 1.0 / 60.0
	var next := &""
	for i in 120:
		next = state.update(dt)
	check(next == &"" and is_zero_approx(state.annoyance), "a %.0f m lo vigila sin impacientarse" % 26.0)
	target.body.global_position = Vector3(0, 0, 18)
	var waited := 0.0
	while next == &"" and waited < 30.0:
		next = state.update(dt)
		waited += dt
	check(next == state.combat_state and waited < state.patience,
		"a 18 m se le acaba la paciencia y ataca (%.1f s, aguanta %.1f al borde)" % [waited, state.patience])
	state.annoyance = 0.0
	target.body.global_position = Vector3(0, 0, state.attack_distance - 1.0)
	check(state.update(dt) == state.combat_state, "si se le mete a menos de %.0f m ataca al momento" % state.attack_distance)
	target.body.global_position = Vector3(0, 0, state.calm_distance + 2.0)
	check(state.update(dt) == state.calm_state, "si se va más allá de %.0f m se calma" % state.calm_distance)
	var idle := lion.ai_controller.get_node("IdleState") as IdleState
	target.body.global_position = Vector3(0, 0, 20)
	idle.enter()
	check(idle.update(dt) == &"TerritorialState", "en reposo, un intruso a 20 m le pone a defender su sitio")
	lion.queue_free()
	target.body.queue_free()


## El centro del territorio va en el marco del planeta (sobrevive al rebase del origen flotante) y
## los clips de correr van al ritmo del cuerpo.
func _check_home_and_gait() -> void:
	var lion := (load("%s/Lion.tscn" % ANIMALS_DIR) as PackedScene).instantiate() as NPCController
	add_child(lion)
	var planet := Node3D.new()
	add_child(planet)
	lion.planet = planet
	lion.set_home(Vector3(100, 0, 50))
	planet.global_position -= Vector3(4000, 0, 0)
	check(lion.get_home().is_equal_approx(Vector3(-3900, 0, 50)), "el centro del territorio sigue al planeta en un rebase (%s)" % lion.get_home())
	lion.planet = null
	var tree := lion.animation_controller.animation_tree
	check(lion._gait.size() == 2, "el león ajusta el ritmo de sus clips de correr y esprintar (%d)" % lion._gait.size())
	lion.movement.velocity = Vector3(0, 0, 12.5)
	lion._update_gait()
	var rate: float = tree.get("parameters/gait_sprint/scale")
	check(is_equal_approx(rate, 12.5 / 15.4), "a 12,5 m/s el clip de esprintar (15,4 m/s) va a %.2f" % rate)
	lion.queue_free()
	planet.queue_free()


## Los sonidos grabados del combate (data/audio/events/combat_*.tres): cada uno con variantes que
## se leen y duran algo, y CombatFx los prefiere a los sintetizados.
func _check_sound_events() -> void:
	var problems: PackedStringArray = []
	var count := 0
	for file in DirAccess.get_files_at("res://data/audio/events"):
		if not file.begins_with("combat_") or not file.ends_with(".tres"):
			continue
		count += 1
		var ev := load("res://data/audio/events/" + file) as SoundEvent
		if ev == null or ev.streams.is_empty():
			problems.append("%s sin clips" % file)
			continue
		for stream in ev.streams:
			if stream == null or stream.get_length() < 0.05:
				problems.append("%s: clip vacío" % file)
		var id := StringName(file.trim_prefix("combat_").trim_suffix(".tres"))
		if CombatFx._event(id) != AudioManager.get_event(ev.event_id):
			problems.append("CombatFx no usa el grabado de %s" % id)
	check(count >= 20 and problems.is_empty(), "%d sonidos grabados del combate, todos con clips %s" % [count, problems])


## La voz del jugador va con su sexo: la de mujer si el personaje lo es.
func _check_player_voice() -> void:
	var combat := PlayerCombat.new()
	var saved: CharacterData = GameManager.character
	var character := CharacterData.new()
	GameManager.character = character
	character.appearance.values[AppearanceCatalog.SEX] = &"female"
	var female := [combat._voice(&"player_hurt"), combat._voice(&"player_death")]
	character.appearance.values[AppearanceCatalog.SEX] = &"male"
	var male := [combat._voice(&"player_hurt"), combat._voice(&"player_death")]
	GameManager.character = saved
	combat.free()
	check(female == [&"player_hurt_female", &"player_death_female"] and male == [&"player_hurt", &"player_death"],
		"la jugadora se queja con voz de mujer y el jugador con la de hombre (%s, %s)" % [female, male])


func _spawn_bear() -> NPCController:
	var bear := (load("%s/Bear.tscn" % ANIMALS_DIR) as PackedScene).instantiate() as NPCController
	add_child(bear)
	bear.global_transform = Transform3D.IDENTITY
	return bear


## Pone al oso a pelear contra [target] sin pasar por la percepción.
func _engage(bear: NPCController, target: Node3D) -> CreatureCombatState:
	var state := bear.ai_controller.get_node("CombatState") as CreatureCombatState
	bear.ai_controller.target = target
	state.enter()
	return state


func _attack(state: CreatureCombatState, id: StringName) -> CreatureAttack:
	for attack in state.profile.attacks:
		if attack.id == id:
			return attack
	return null


## Un blanco con vida y hurtbox. [situation]: lo que dice estar haciendo (get_combat_situation).
func _target(pos: Vector3, situation: StringName = &"") -> Dictionary:
	var body := Node3D.new()
	if situation != &"":
		var script := GDScript.new()
		script.source_code = "extends Node3D\nfunc get_combat_situation() -> StringName:\n\treturn &\"%s\"\n" % situation
		script.reload()
		body.set_script(script)
	add_child(body)
	body.global_position = pos
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 500.0
	body.add_child(health)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	Hurtbox.attach(body, body, shape, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0)))
	return {"body": body, "health": health}
