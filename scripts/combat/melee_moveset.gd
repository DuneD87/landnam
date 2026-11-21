class_name MeleeMoveset
extends RefCounted

## Golpes cuerpo a cuerpo de cada familia de armas: qué animación suena y sus tiempos. Los
## ligeros encadenan un combo; el pesado se carga manteniendo el botón; saliendo de una voltereta
## sale el golpe a la carrera. En marcha, cualquiera se da sin pararse y sin su paso adelante
## (PlayerCombat.RUN_ATTACK_PACE). Cada golpe es atómico (ver PlayerCombat).
##
## Tiempos en segundos de la animación a ritmo 1, medidos sobre ella (por la velocidad de la
## mano):
##   anim     animación del AnimationPlayer del jugador (las de la librería "combat", sin prefijo)
##   speed    ritmo (escala de tiempo), sobre el attack_speed del arma
##   from     desde dónde empieza a sonar (golpes sacados de un tramo de un combo)
##   hit      Vector2 ventana en que la hoja hiere
##   commit   hasta cuándo el golpe no se corta; lo pulsado mientras tanto sale aquí
##   end      dónde se deja de oír la animación si no se hace otra cosa (moverse la corta antes)
##   lunge    Vector3(desde, hasta, metros): paso adelante del cuerpo
##   track    hasta cuándo se puede reorientar hacia el objetivo
##   charge   dónde se queda quieto mientras se carga (pesados)
##   armor    Vector3(desde, hasta, guardia): hyperarmor, golpes que no lo tambalean
##   damage, poise, stamina  multiplicadores sobre los del arma

## Los dos golpes que trae el rig, mientras cada familia no tenga sus animaciones.
const HORIZONTAL := {"anim": &"attack_horizontal", "hit": Vector2(0.74, 1.08), "commit": 1.3, "end": 1.62,
	"lunge": Vector3(0.40, 0.95, 0.85), "track": 0.6}
const VERTICAL := {"anim": &"attack_vertical", "hit": Vector2(0.62, 0.98), "commit": 1.2, "end": 1.50,
	"lunge": Vector3(0.36, 0.88, 0.75), "track": 0.5}

## Espada a una mano (Mixamo): el combo de tres tajos partido en golpes, cada uno sigue la
## animación donde la dejó el anterior; al encadenar, la transición es la del propio combo. Si
## no se encadena, la animación se funde a la guardia en "end" (los dos primeros) o sigue hasta
## volver a ella (el último).
const SWORD := {
	"light": [
		# Sube la espada y baja en diagonal con una zancada.
		{"anim": &"sword_combo", "speed": 1.1, "from": 0.2, "hit": Vector2(0.88, 1.28), "commit": 1.33, "end": 1.33,
			"lunge": Vector3(0.85, 1.25, 0.6), "track": 0.8},
		# Gira y la baja en vertical.
		{"anim": &"sword_combo", "speed": 1.1, "from": 1.33, "hit": Vector2(1.86, 2.14), "commit": 2.37, "end": 2.37,
			"lunge": Vector3(1.80, 2.10, 0.45), "track": 1.8},
		# Tajo horizontal a la derecha, y de vuelta a la guardia.
		{"anim": &"sword_combo", "speed": 1.1, "from": 2.37, "hit": Vector2(2.82, 3.14), "commit": 3.27, "end": 4.2,
			"lunge": Vector3(2.80, 3.10, 0.5), "track": 2.8, "damage": 1.15, "poise": 1.2},
	],
	# Salto: se agacha (ahí carga), salta girando y cae clavando la espada; aguanta en el aire.
	"heavy": [
		{"anim": &"sword_heavy", "hit": Vector2(1.22, 1.46), "charge": 0.45, "commit": 1.75, "end": 2.43,
			"lunge": Vector3(0.55, 1.30, 1.3), "track": 0.5, "armor": Vector3(0.5, 1.5, 25.0)},
	],
	# A la carrera: el tajo con zancada del combo, sin la subida.
	"dash": [
		{"anim": &"sword_combo", "speed": 1.1, "from": 0.6, "hit": Vector2(0.88, 1.28), "commit": 1.33, "end": 1.33,
			"lunge": Vector3(0.6, 1.25, 1.5), "track": 0.7, "damage": 1.1, "poise": 1.2, "stamina": 1.2},
	],
}

## Repertorios de los packs: ventanas medidas sobre las manos a 30 fps. Cada ligero
## tiene su propia recuperación; el tercero remata con más daño y desgaste de guardia.
const GREATSWORD := {
	"light": [
		{"anim": &"greatsword_slash_1", "hit": Vector2(0.48, 0.77), "commit": 0.98, "end": 1.26,
			"lunge": Vector3(0.35, 0.72, 0.65), "track": 0.40, "armor": Vector3(0.42, 0.80, 18.0)},
		{"anim": &"greatsword_slash_3", "from": 0.20, "hit": Vector2(0.73, 1.10), "commit": 1.30, "end": 1.83,
			"lunge": Vector3(0.50, 1.0, 0.55), "track": 0.55, "armor": Vector3(0.65, 1.12, 18.0)},
		{"anim": &"greatsword_slash_5", "hit": Vector2(0.28, 0.68), "commit": 1.0, "end": 1.43,
			"lunge": Vector3(0.18, 0.60, 0.55), "track": 0.22, "damage": 1.2, "poise": 1.35,
			"stamina": 1.1, "armor": Vector3(0.24, 0.75, 24.0)},
	],
	"heavy": [
		{"anim": &"greatsword_heavy", "hit": Vector2(0.96, 1.32), "charge": 0.48,
			"commit": 1.68, "end": 2.16, "lunge": Vector3(0.55, 1.20, 1.20), "track": 0.48,
			"armor": Vector3(0.50, 1.40, 38.0), "poise": 1.2, "air": Vector2(0.55, 1.30)},
	],
	"dash": [
		{"anim": &"greatsword_dash", "from": 0.80, "hit": Vector2(1.08, 1.56),
			"commit": 1.76, "end": 2.13, "lunge": Vector3(0.80, 1.42, 1.55), "track": 0.93,
			"damage": 1.1, "poise": 1.2, "stamina": 1.2, "armor": Vector3(1.0, 1.6, 18.0)},
	],
}

const SHIELD := {
	"light": [
		{"anim": &"shield_slash_1", "hit": Vector2(0.51, 0.72), "commit": 0.94, "end": 1.50,
			"lunge": Vector3(0.35, 0.64, 0.45), "track": 0.42},
		{"anim": &"shield_slash_3", "from": 0.22, "hit": Vector2(0.71, 0.96), "commit": 1.16, "end": 1.66,
			"lunge": Vector3(0.48, 0.87, 0.35), "track": 0.57},
		{"anim": &"shield_slash_5", "hit": Vector2(0.47, 0.74), "commit": 0.97, "end": 1.36,
			"lunge": Vector3(0.32, 0.68, 0.55), "track": 0.40, "damage": 1.15, "poise": 1.3},
	],
	"heavy": [
		{"anim": &"shield_slash_4", "from": 0.25, "hit": Vector2(1.19, 1.46), "charge": 0.75,
			"commit": 1.80, "end": 2.43, "lunge": Vector3(0.92, 1.40, 0.9), "track": 0.80,
			"armor": Vector3(0.95, 1.48, 20.0)},
	],
	"dash": [
		{"anim": &"shield_dash", "from": 0.18, "hit": Vector2(0.45, 0.73), "commit": 0.96, "end": 1.30,
			"lunge": Vector3(0.20, 0.67, 1.20), "track": 0.35, "damage": 1.1, "stamina": 1.15},
	],
}

static var _families: Dictionary = {}


static func _build() -> Dictionary:
	var h := HORIZONTAL
	var v := VERTICAL
	var heavy := _with(v, {"speed": 0.85, "charge": 0.50, "lunge": Vector3(0.36, 0.88, 1.05),
		"armor": Vector3(0.45, 1.0, 20.0)})
	var dash := _with(h, {"lunge": Vector3(0.2, 0.95, 1.6), "damage": 1.1, "poise": 1.2, "stamina": 1.2})
	var one_hand := {"light": [h, v], "heavy": [heavy], "dash": [dash]}
	return {
		&"sword": SWORD,
		&"axe": one_hand,
		&"mace": one_hand,
		# La lanza pica de arriba abajo: es lo más parecido a una estocada que trae el rig.
		&"spear": {"light": [v], "heavy": [heavy], "dash": [_with(v, {"lunge": Vector3(0.2, 0.88, 1.6)})]},
		# El pico entra siempre de arriba abajo, también contra una criatura.
		&"pickaxe": {"light": [v], "heavy": [heavy], "dash": [_with(v, {"lunge": Vector3(0.2, 0.88, 1.6)})]},
		# El hacha de talar, siempre de lado, como al tronco; el pesado se carga atrás, antes del tajo.
		&"hatchet": {"light": [h], "dash": [dash], "heavy": [_with(h, {"speed": 0.85, "charge": 0.58,
			"lunge": Vector3(0.40, 0.95, 1.05), "armor": Vector3(0.5, 1.08, 20.0)})]},
		&"shield": SHIELD,
		&"greatsword": GREATSWORD,
		&"heavy2h": {"light": GREATSWORD.light.map(func(m: Dictionary) -> Dictionary: return _with(m, {"speed": 0.88})),
			"heavy": GREATSWORD.heavy, "dash": GREATSWORD.dash},
	}


static func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


## Familia de golpes del arma.
static func family_for(data: ItemData, with_shield: bool = false) -> StringName:
	if data == null:
		return &"sword"
	if with_shield and not data.two_handed and data.weapon_type in [ItemData.WeaponType.SWORD, ItemData.WeaponType.AXE, ItemData.WeaponType.MACE]:
		return &"shield"
	var two := data.two_handed
	match data.weapon_type:
		ItemData.WeaponType.SWORD:
			return &"greatsword" if two else &"sword"
		ItemData.WeaponType.AXE:
			return &"heavy2h" if two else &"axe"
		ItemData.WeaponType.MACE:
			return &"heavy2h" if two else &"mace"
		ItemData.WeaponType.SPEAR:
			return &"spear"
	# Herramientas: el pico pica, la azada cava y el martillo clava en vertical, y el hacha tala en
	# horizontal; lo demás, contra una criatura, pega como un hacha.
	match data.tool_type:
		ItemData.ToolType.PICKAXE, ItemData.ToolType.HOE, ItemData.ToolType.HAMMER:
			return &"pickaxe"
		ItemData.ToolType.AXE:
			return &"hatchet"
	return &"axe"


## Golpe [index] (el combo da la vuelta) de tipo [kind] ("light", "heavy", "dash").
static func move(family: StringName, kind: String, index: int) -> Dictionary:
	if _families.is_empty():
		_families = _build()
	var fam: Dictionary = _families.get(family, _families[&"sword"])
	var list: Array = fam.get(kind, fam["light"])
	return list[posmod(index, list.size())]
