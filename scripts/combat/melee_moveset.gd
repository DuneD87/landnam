class_name MeleeMoveset
extends RefCounted

## Golpes cuerpo a cuerpo de cada familia de armas: qué animación suena y sus tiempos. Los
## ligeros encadenan un combo; el pesado se carga manteniendo el botón; corriendo o saliendo de
## una voltereta sale el golpe a la carrera. Cada golpe es atómico (ver PlayerCombat).
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

static var _families: Dictionary = {}


static func _build() -> Dictionary:
	var h := HORIZONTAL
	var v := VERTICAL
	var heavy := _with(v, {"speed": 0.85, "charge": 0.50, "lunge": Vector3(0.36, 0.88, 1.05),
		"armor": Vector3(0.45, 1.0, 20.0)})
	var dash := _with(h, {"lunge": Vector3(0.2, 0.95, 1.6), "damage": 1.1, "poise": 1.2, "stamina": 1.2})
	var one_hand := {"light": [h, v], "heavy": [heavy], "dash": [dash]}
	# A dos manos: más lento y aguantando más mientras golpea.
	var two_hand := {
		"light": [_with(h, {"speed": 0.8, "armor": Vector3(0.6, 1.08, 15.0)}),
			_with(v, {"speed": 0.8, "armor": Vector3(0.5, 0.98, 15.0)})],
		"heavy": [_with(heavy, {"speed": 0.7, "armor": Vector3(0.45, 1.0, 35.0)})],
		"dash": [_with(dash, {"speed": 0.85, "armor": Vector3(0.5, 1.08, 15.0)})],
	}
	return {
		&"sword": SWORD,
		&"axe": one_hand,
		&"mace": one_hand,
		# La lanza pica de arriba abajo: es lo más parecido a una estocada que trae el rig.
		&"spear": {"light": [v], "heavy": [heavy], "dash": [_with(v, {"lunge": Vector3(0.2, 0.88, 1.6)})]},
		&"greatsword": two_hand,
		&"heavy2h": two_hand,
	}


static func _with(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


## Familia de golpes del arma.
static func family_for(data: ItemData) -> StringName:
	if data == null:
		return &"sword"
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
	# Herramientas: el hacha de piedra tala y el pico pica; contra una criatura, como un hacha.
	return &"axe"


## Golpe [index] (el combo da la vuelta) de tipo [kind] ("light", "heavy", "dash").
static func move(family: StringName, kind: String, index: int) -> Dictionary:
	if _families.is_empty():
		_families = _build()
	var fam: Dictionary = _families.get(family, _families[&"sword"])
	var list: Array = fam.get(kind, fam["light"])
	return list[posmod(index, list.size())]
