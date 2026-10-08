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
	await _check_parried()
	await _check_perception()
	await _check_memory()
	await _check_turns()
	await _check_flank()
	await _check_pack_alert()
	await _check_pack_no_bites()
	await _check_variants()
	await _check_pack_spawn()
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
	# El que suena de verdad (el de AnimationController): el modelo instanciado puede traer el suyo.
	var player := animal.animation_controller.animator if animal.animation_controller != null \
		and animal.animation_controller.animator != null \
		else animal.npc_model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
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
		profile.stagger_sound, profile.wait_sound, animal.hurt_sound, animal.death_sound]
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
	# Sus variantes: con nombre único, tamaños con sentido y que solo quitan ataques que tiene.
	var variant_problems: PackedStringArray = []
	if animal.variants.size() < 2:
		variant_problems.append("sin variedad de tamaños")
	var variant_ids := {}
	for v in animal.variants:
		if v == null or v.id == &"" or variant_ids.has(v.id):
			variant_problems.append("variante sin nombre o repetida")
			continue
		variant_ids[v.id] = true
		if v.size.x <= 0.0 or v.size.x > v.size.y:
			variant_problems.append("%s: tamaño %s" % [v.id, v.size])
		for id in v.excluded_attacks:
			if not ids.has(id):
				variant_problems.append("%s: quita '%s', que no está en el perfil" % [v.id, id])
	check(variant_problems.is_empty(), "%s: variantes coherentes con el perfil (%d) %s" % [file, animal.variants.size(), variant_problems])


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
		var variant_count := 0
		if probe != null:
			for state in probe.get_node("AIController").get_children():
				if state is CreatureCombatState:
					profile = (state as CreatureCombatState).profile
			variant_count = probe.variants.size()
			probe.free()
		if profile == null:
			continue
		# Con el tamaño de la escena y, si la especie tiene variantes, con el más chico y el más
		# grande: el alcance y las distancias crecen con el cuerpo.
		var extremes := [0] if variant_count == 0 else [0, -1, 1]
		for attack in profile.attacks:
			for extreme in extremes:
				for dist in [maxf(attack.distance.x, 1.6), attack.distance.y]:
					var landed: Variant = await _land(scene, attack.id, dist, extreme)
					if landed == null:
						continue
					check(landed, "%s%s: %s acierta a un blanco quieto a %.1f m (por su tamaño)" % [file,
						["", " (el más grande)", " (el más chico)"][extreme], attack.id, dist])


## Lanza [id] contra un blanco quieto a [dist] m (por el tamaño del cuerpo). [extreme]: 0 = el
## tamaño de la escena, -1 = la variante más chica a su mínimo, 1 = la más grande a su máximo.
## null si esa variante no hace ese ataque.
func _land(scene: PackedScene, id: StringName, dist: float, extreme: int = 0) -> Variant:
	var animal := scene.instantiate() as NPCController
	add_child(animal)
	animal.global_transform = Transform3D.IDENTITY
	_fix_size(animal, extreme)
	if not animal.can_use_attack(id):
		animal.queue_free()
		return null
	var target := _target(Vector3(0, 0, dist * animal.body_size))
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
	lion.apply_variant(null)
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
	lion.apply_variant(null)
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


## Un zarpazo parado en seco a mitad de barrido: el ataque se corta sin romper nada, el blanco no
## pierde vida y el oso se queda vendido parried_time.
func _check_parried() -> void:
	var bear := _spawn_bear()
	var target := _target(Vector3(0, 0, 1.9))
	# El blanco mira al oso (los cuerpos miran por +Z) y alza un escudo justo antes del golpe.
	target.body.global_basis = Basis(Vector3.UP, PI)
	var shield := ItemData.new()
	shield.armor_slot = ItemData.ArmorSlot.OFFHAND
	shield.guard_reduction = 0.9
	# Ventana amplia: aquí se prueba qué pasa al parar, no la puntería.
	shield.parry_window = 1.0
	shield.guard_arc = 70.0
	var guard := Guard.new()
	guard.item = shield
	guard.body = target.body
	(target.health as HealthComponent).guard = guard
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := _engage(bear, target.body)
	var swipe := _attack(state, &"swipe")
	state._set_phase(CreatureCombatState.Phase.ATTACK)
	state.runner.start(swipe)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var frames := 0
	while state.runner.is_running() and frames < 600:
		if not guard.raised and state.runner.time > swipe.hits[0].from:
			guard.raise()
		guard.update(dt)
		state.runner.update(dt)
		await get_tree().physics_frame
		frames += 1
	var health := target.health as HealthComponent
	check(health.health == health.max_health and state.phase == CreatureCombatState.Phase.STAGGER
		and is_equal_approx(state._phase_length, state.profile.parried_time),
		"parado en seco: el blanco no pierde vida y el oso se queda vendido %.1f s" % state.profile.parried_time)
	state.exit()
	bear.queue_free()
	target.body.queue_free()


## La percepción mira hacia donde mira el cuerpo (+Z) y desde los ojos: ve lo que tiene delante
## por encima de un murete, no lo que tiene detrás fuera de su oído, ni lo que tapa una pared alta.
func _check_perception() -> void:
	var bear := _spawn_bear()
	var perception := bear.perception
	perception.set_physics_process(false)
	var ahead := _target(Vector3(0, 0, 20))
	var behind := _target(Vector3(0, 0, -20))
	await get_tree().physics_frame
	check(perception._can_detect(ahead.body), "ve lo que tiene delante a 20 m")
	check(not perception._can_detect(behind.body), "no ve lo que tiene detrás a 20 m, fuera de su oído")
	var low := _wall(Vector3(0, 0.3, 10), Vector3(6, 0.6, 0.3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(perception._can_detect(ahead.body),
		"por encima de un murete de 60 cm lo sigue viendo (ojos a %.1f m)" % perception.eye_height)
	low.free()
	var high := _wall(Vector3(0, 1.5, 10), Vector3(6, 3.0, 0.3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not perception._can_detect(ahead.body), "una pared alta lo tapa")
	high.free()
	bear.queue_free()
	ahead.body.queue_free()
	behind.body.queue_free()


## Con memoria, al perderlo de vista no lo suelta: sabe dónde lo vio y hacia dónde iba, deja de
## atacar y va a buscarlo; si en memory_time no lo vuelve a ver, lo olvida.
func _check_memory() -> void:
	var bear := _spawn_bear()
	var perception := bear.perception
	perception.set_physics_process(false)
	var ctl := bear.ai_controller
	var target := _target(Vector3(0, 0, 20))
	perception._player_cache = target.body
	await get_tree().physics_frame
	var lost := [false]
	perception.target_lost.connect(func() -> void: lost[0] = true)
	perception._physics_step(perception.check_interval)
	check(ctl.target == target.body and ctl.target_seen, "lo ve y lo toma por objetivo")
	# Corre de lado a 5 m/s (la IA le mide la velocidad) y se mete tras una pared alta.
	var dt := 0.1
	for i in 5:
		target.body.global_position += Vector3(5, 0, 0) * dt
		ctl._track_target(dt)
	var seen_at: Vector3 = target.body.global_position
	var wall := _wall(Vector3(0, 1.5, 15), Vector3(30, 3.0, 0.3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	perception._physics_step(perception.check_interval)
	check(ctl.target == target.body and not ctl.target_seen and not lost[0], "tras la pared no lo suelta: lo recuerda sin verlo")
	ctl._track_target(1.0)
	var search := ctl.search_position(2.0)
	check(ctl.last_seen_position().is_equal_approx(seen_at) and search.x > seen_at.x + 3.0,
		"lo busca donde lo vio, adelantado hacia donde corría (%s → %s)" % [seen_at, search])
	var state := bear.ai_controller.get_node("CombatState") as CreatureCombatState
	state.enter()
	state.update(dt)
	var to_search := ctl.project_on_gravity_plane(search - bear.global_position)
	check(state.phase == CreatureCombatState.Phase.SEARCH and ctl.desired_direction.dot(to_search) > 0.9,
		"sin verlo no ataca: va a buscarlo")
	ctl._track_target(perception.memory_time)
	perception._physics_step(perception.check_interval)
	check(ctl.target == null and lost[0], "pasados %.0f s sin verlo, lo olvida" % perception.memory_time)
	state.exit()
	wall.free()
	bear.queue_free()
	target.body.queue_free()


## Varios contra uno: como mucho CombatDirector.MAX_TURNS atacan a la vez y los demás esperan en
## corro, sin echarse encima; al soltar uno su turno, entra el que esperaba.
func _check_turns() -> void:
	CombatDirector.reset()
	var target := _target(Vector3.ZERO)
	var bears: Array[NPCController] = []
	for i in 3:
		var bear := _spawn_bear()
		bear.perception.set_physics_process(false)
		var pos := Vector3(sin(TAU * i / 3.0), 0, cos(TAU * i / 3.0)) * 5.0
		bear.global_transform = Transform3D(Basis.looking_at(-pos, Vector3.UP, true), pos)
		bears.append(bear)
	await get_tree().physics_frame
	var states: Array[CreatureCombatState] = []
	for bear in bears:
		states.append(_engage(bear, target.body))
	for state in states:
		state.update(0.05)
	var waiters := states.filter(func(st: CreatureCombatState) -> bool: return st.is_waiting())
	check(CombatDirector.turns(target.body) == CombatDirector.MAX_TURNS and waiters.size() == 1,
		"tres osos contra uno: atacan %d y el tercero espera en corro (%d esperando)" % [CombatDirector.turns(target.body), waiters.size()])
	if waiters.size() == 1:
		var waiter: CreatureCombatState = waiters[0]
		waiter.update(0.05)
		var to_target := waiter.controller.project_on_gravity_plane(-waiter.controller.npc.global_position)
		check(waiter.controller.desired_direction.dot(to_target) < 0.1, "el que espera no se echa encima")
		for state in states:
			if state != waiter:
				state.exit()
				break
		waiter.update(0.05)
		check(CombatDirector.has_turn(target.body, waiter.controller.npc) and not waiter.is_waiting(),
			"al soltar uno su turno, entra el que esperaba")
	for state in states:
		state.exit()
	for bear in bears:
		bear.queue_free()
	target.body.queue_free()


## En el corro se reparten: a la espalda del objetivo si el perfil lo pide (flank_bias), y si otro
## ya la cubre, abiertos a un lado.
func _check_flank() -> void:
	CombatDirector.reset()
	var target := _target(Vector3.ZERO)
	var first := _spawn_bear()
	first.perception.set_physics_process(false)
	first.global_position = Vector3(6, 0, 0)
	await get_tree().physics_frame
	var state := _engage(first, target.body)
	state.profile = state.profile.duplicate()
	state.profile.flank_bias = 1.0
	# El blanco mira a +Z: su espalda es -Z.
	var dir := state._pick_flank_dir()
	check(dir.z < -0.7, "con flank_bias 1 espera a la espalda del objetivo (%s)" % dir)
	var second := _spawn_bear()
	second.perception.set_physics_process(false)
	second.global_position = Vector3(0, 0, -7)
	var other := _engage(second, target.body)
	dir = state._pick_flank_dir()
	check(rad_to_deg(dir.angle_to(Vector3.FORWARD)) > 40.0, "si otro le cubre ya la espalda, se abre a un lado (%s)" % dir)
	state.exit()
	other.exit()
	first.queue_free()
	second.queue_free()
	target.body.queue_free()


## Manada: el lobo que ve al objetivo avisa a los suyos a tiro (alert_radius), que van a por él; no
## al que está lejos ni al oso de al lado. Y su muerte arranca su clip desde el principio.
func _check_pack_alert() -> void:
	CombatDirector.reset()
	var scene := load("%s/Wolf.tscn" % ANIMALS_DIR) as PackedScene
	var wolves: Array[NPCController] = []
	for pos in [Vector3.ZERO, Vector3(6, 0, 0), Vector3(-8, 0, 4), Vector3(70, 0, 0)]:
		var wolf := scene.instantiate() as NPCController
		add_child(wolf)
		wolf.global_position = pos
		wolf.perception.set_physics_process(false)
		wolves.append(wolf)
	var bear := _spawn_bear()
	bear.global_position = Vector3(0, 0, 8)
	bear.perception.set_physics_process(false)
	var target := _target(Vector3(0, 0, 20))
	await get_tree().physics_frame
	wolves[0].ai_controller.target = target.body
	wolves[0]._on_target_detected(target.body)
	var called := wolves.slice(1, 3).filter(func(w: NPCController) -> bool:
		return w.ai_controller.target == target.body and w.ai_controller.get_current_state() == &"CombatState")
	check(called.size() == 2, "el lobo que lo ve avisa a los dos de su manada a tiro, que van a por él (%d)" % called.size())
	check(wolves[3].ai_controller.target == null, "al que está a 70 m no le llega el aviso")
	check(bear.ai_controller.target != target.body, "el oso de al lado no es de la manada")
	check(wolves[0].animation_controller._has_death_seek, "al morir, su clip de muerte arranca desde el principio")
	for wolf in wolves:
		wolf.queue_free()
	bear.queue_free()
	target.body.queue_free()
	CombatDirector.reset()


## Los de la manada no se muerden entre ellos: el mordisco que le cae encima a un compañero lo
## atraviesa sin hacerle nada.
func _check_pack_no_bites() -> void:
	var scene := load("%s/Wolf.tscn" % ANIMALS_DIR) as PackedScene
	var wolf := scene.instantiate() as NPCController
	var mate := scene.instantiate() as NPCController
	add_child(wolf)
	add_child(mate)
	wolf.global_transform = Transform3D.IDENTITY
	mate.global_position = Vector3(0, 0, 1.4)
	wolf.perception.set_physics_process(false)
	mate.perception.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(wolf.is_ally(mate) and not wolf.is_ally(wolf) and not wolf.is_ally(_spawn_bear_free()),
		"los lobos son aliados entre ellos, no de sí mismos ni del oso")
	var state := _engage(wolf, mate)
	state.runner.start(_attack(state, &"bite"))
	var dt := 1.0 / Engine.physics_ticks_per_second
	var frames := 0
	while state.runner.update(dt) and frames < 600:
		await get_tree().physics_frame
		frames += 1
	check(state.runner.landed == 0 and mate.health_component.health == mate.health_component.max_health,
		"el mordisco no hiere al compañero que tiene delante (%d golpes, %.0f de vida)" % [state.runner.landed, mate.health_component.health])
	state.exit()
	wolf.queue_free()
	mate.queue_free()


## Un oso suelto (fuera del árbol) para preguntar por la especie.
func _spawn_bear_free() -> NPCController:
	var bear := (load("%s/Bear.tscn" % ANIMALS_DIR) as PackedScene).instantiate() as NPCController
	bear.queue_free()
	return bear


## Fija el tamaño de [animal]: 0 = el de la escena, -1 = su variante más chica a su mínimo, 1 = la
## más grande a su máximo.
func _fix_size(animal: NPCController, extreme: int) -> void:
	if extreme == 0 or animal.variants.is_empty():
		animal.apply_variant(null)
		return
	var pick: CreatureVariant = animal.variants[0]
	for v in animal.variants:
		if (extreme < 0 and v.size.x < pick.size.x) or (extreme > 0 and v.size.y > pick.size.y):
			pick = v
	animal.apply_variant(pick, pick.size.x if extreme < 0 else pick.size.y)


## Variedad de lobos: cada uno sortea variante (joven, adulto, grande), tamaño y pelaje; el cuerpo,
## la vida, el daño, la guardia y la voz van con ella; el joven no derriba; en una manada solo hay un
## macho grande.
func _check_variants() -> void:
	var scene := load("%s/Wolf.tscn" % ANIMALS_DIR) as PackedScene
	var wolf := scene.instantiate() as NPCController
	add_child(wolf)
	wolf.perception.set_physics_process(false)
	var by_id := {}
	for v in wolf.variants:
		by_id[v.id] = v
	check(by_id.has(&"joven") and by_id.has(&"adulto") and by_id.has(&"grande"), "el lobo tiene joven, adulto y grande (%s)" % [by_id.keys()])
	var large: CreatureVariant = by_id[&"grande"]
	var young: CreatureVariant = by_id[&"joven"]
	var capsule := wolf.collision_shape.shape as CapsuleShape3D
	var base_radius: float = wolf._base.radius
	var base_health: float = wolf._base.max_health

	wolf.apply_variant(large, large.size.y)
	var strength := pow(large.size.y / large.mid_size(), 2.0)
	check(is_equal_approx(wolf.health_component.max_health, base_health * large.health * strength)
		and wolf.health_component.health == wolf.health_component.max_health,
		"el grande tiene más vida (%.0f, la especie %.0f)" % [wolf.health_component.max_health, base_health])
	check(is_equal_approx(capsule.radius, base_radius * large.size.y) and is_equal_approx(wolf.npc_model.scale.x, large.size.y)
		and is_equal_approx(wolf.collision_shape.position.y, 0.36 * large.size.y),
		"y es más grande: modelo ×%.2f, cápsula de %.2f m" % [wolf.npc_model.scale.x, capsule.radius])
	check(is_equal_approx(wolf.damage_scale, large.damage * strength) and wolf.voice_pitch < 1.0
		and wolf.movement.speed < 2.5, "pega más fuerte (×%.2f), con voz más grave, y es algo más lento (%.2f m/s)" % [wolf.damage_scale, wolf.movement.speed])

	# Su mordisco, a la distancia de su tamaño, hiere lo que dice su variante.
	var target := _target(Vector3(0, 0, 1.6 * wolf.body_size))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := _engage(wolf, target.body)
	var bite := _attack(state, &"bite")
	state.runner.start(bite)
	var ctl := wolf.ai_controller
	var dt := 1.0 / Engine.physics_ticks_per_second
	var frames := 0
	while state.runner.update(dt) and frames < 600:
		if ctl.desired_direction != Vector3.ZERO:
			wolf.global_position += ctl.desired_direction * ctl.movement.speed * dt
		await get_tree().physics_frame
		frames += 1
	var lost: float = 500.0 - (target.health as HealthComponent).health
	var expected := 0.0
	for hit in bite.hits:
		expected += hit.damage * wolf.damage_scale
	check(lost > bite.hits[0].damage * 1.2 and lost <= expected + 0.01,
		"el mordisco del grande quita %.0f (el de la especie, %.0f)" % [lost, bite.hits[0].damage])
	state.exit()
	target.body.queue_free()

	# El joven no derriba: nunca elige el derribo, aunque esté a su distancia.
	wolf.global_transform = Transform3D.IDENTITY
	wolf.apply_variant(young, young.mid_size())
	var prey := _target(Vector3(0, 0, 3.0))
	state = _engage(wolf, prey.body)
	var takedowns := 0
	for i in 60:
		var pick := state._pick_attack(3.0, state.profile.attacks, true)
		if pick != null and pick.id == &"takedown":
			takedowns += 1
	check(not wolf.can_use_attack(&"takedown") and takedowns == 0, "el joven no derriba (%d de 60)" % takedowns)
	state.exit()
	prey.body.queue_free()

	# Sorteo: variedad de tamaños y pelajes, sin tocar el material de la especie.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sizes: Array[float] = []
	var seen := {}
	var colors := {}
	for i in 60:
		wolf.roll_variant(rng)
		sizes.append(wolf.body_size)
		seen[wolf.variant.id] = seen.get(wolf.variant.id, 0) + 1
		colors[wolf._coat[0].albedo_color] = true
	check(seen.size() == 3 and sizes.min() < 0.9 and sizes.max() > 1.1,
		"salen de las tres (%s) y de %.2f a %.2f de tamaño" % [seen, sizes.min(), sizes.max()])
	var shared := load("res://models/animals/wolf/wolf_body.tres") as StandardMaterial3D
	check(colors.size() >= 3 and shared.albedo_color == Color.WHITE,
		"con pelajes distintos (%d) en una copia propia del material" % colors.size())

	# Manada: si el que la encabeza es el grande, el que sortee grande al salir se queda en otra.
	wolf.apply_variant(large)
	var members: Array[NPCController] = []
	for i in 6:
		var member := scene.instantiate() as NPCController
		add_child(member)
		member.perception.set_physics_process(false)
		member.apply_variant(large)
		member.join_group(wolf)
		members.append(member)
	var larges := members.filter(func(m: NPCController) -> bool: return m.variant == large).size()
	check(larges == 0 and members.all(func(m: NPCController) -> bool: return m.variant != null),
		"en su manada no sale otro grande (%d de 6)" % larges)
	for member in members:
		member.queue_free()
	wolf.queue_free()


## Una especie que sale en grupo (group_size) sale junta, cerca del primero; y deambulando no se
## aleja de su casa (WanderState.home_radius), que en la manada es la misma para todos.
func _check_pack_spawn() -> void:
	var profile := GroundFaunaProfile.new()
	profile.animal_scene = load("%s/Wolf.tscn" % ANIMALS_DIR)
	profile.group_size = Vector2i(4, 4)
	profile.group_spread = 10.0
	var habitat_script := GDScript.new()
	habitat_script.source_code = "extends AmbientFaunaHabitat\nfunc is_spawn_valid(_p: Vector3, _c: float) -> bool:\n\treturn true\n"
	habitat_script.reload()
	var habitat: AmbientFaunaHabitat = habitat_script.new()
	var observer := Node3D.new()
	add_child(observer)
	var spawner := AmbientFaunaSpawner.new()
	add_child(spawner)
	spawner.set_physics_process(false)
	spawner.setup(profile, habitat, observer)
	var point := Vector3(40, 0, 0)
	var leader := spawner._get_available_animal()
	leader.profile = profile
	leader.activate(point, habitat, spawner._rng)
	var placed := spawner._spawn_group(leader, point, 10)
	var near := spawner._pool.filter(func(a: AmbientAnimal) -> bool:
		return a.in_play() and a.global_position.distance_to(point) <= profile.group_spread + 0.01)
	check(placed == 3 and near.size() == 4, "una manada de 4 sale junta, a menos de %.0f m del primero (%d)" % [profile.group_spread, near.size()])
	check(spawner._spawn_group(leader, point, 1) <= 1, "sin pasarse de la población que falta")
	var wolf := leader as NPCController
	var wander := wolf.ai_controller.get_node("WanderState") as WanderState
	# Un planeta mínimo: su marco para la casa, y sin mar (AIController.is_in_water pregunta por él).
	var planet_script := GDScript.new()
	planet_script.source_code = "extends Node3D\nvar planet = null\n"
	planet_script.reload()
	var planet := Node3D.new()
	planet.set_script(planet_script)
	add_child(planet)
	wolf.planet = planet
	wolf.set_home(Vector3(100, 0, 0))
	wolf.global_position = Vector3(100 + wander.home_radius * 0.9, 0, 0)
	var farthest := 0.0
	for i in 40:
		farthest = maxf(farthest, wander._pick_wander_target().distance_to(Vector3(100, 0, 0)))
	wolf.planet = null
	check(farthest <= wander.home_radius + 0.01, "deambula sin salirse de %.0f m de su casa (%.1f)" % [wander.home_radius, farthest])
	spawner.queue_free()
	observer.queue_free()
	planet.queue_free()


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	add_child(body)
	body.global_position = center
	return body


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
	# Al tamaño de la escena: al aparecer sortea uno de sus variantes.
	bear.apply_variant(null)
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
