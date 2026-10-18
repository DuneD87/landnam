class_name Armor
extends RefCounted

## La protección contra los golpes de combate, la de la ropa y la armadura puestas y la piel de los
## animales. Cada pieza protege por tipo de golpe (tajo, contundente, perforante: ItemData.DamageKind)
## y solo donde cubre (Region). Ver docs/combat.md#armadura.
##
## Cómo quita: un golpe de [D] contra [A] de protección deja D·D/(D + A). La armadura para mejor lo
## flojo que lo fuerte: con A = D el golpe se queda en la mitad, pero un golpe del triple de A
## todavía entra con tres cuartos. Una mordida de lobo contra una coraza de hueso apenas hace mella;
## una embestida de mamut pasa casi entera. La penetración del arma (ItemData.armor_penetration)
## ignora esa parte de A.

## Partes que cubre una pieza. Más finas que las zonas de vida de BodyDamage (un brazo es brazo,
## antebrazo y mano): un brazal no protege el hombro.
enum Region {HEAD, TORSO, UPPER_ARMS, FOREARMS, HANDS, THIGHS, SHINS, FEET}

const REGION_NAMES := {
	Region.HEAD: "cabeza", Region.TORSO: "tronco", Region.UPPER_ARMS: "brazos",
	Region.FOREARMS: "antebrazos", Region.HANDS: "manos", Region.THIGHS: "muslos",
	Region.SHINS: "espinillas", Region.FEET: "pies",
}

## Lo que cubre una pieza sin cobertura propia (ItemData.coverage = 0), según su hueco.
const SLOT_COVERAGE := {
	ItemData.ArmorSlot.HEAD: 1 << Region.HEAD,
	ItemData.ArmorSlot.CHEST: (1 << Region.TORSO) | (1 << Region.UPPER_ARMS),
	ItemData.ArmorSlot.HANDS: (1 << Region.HANDS) | (1 << Region.FOREARMS),
	ItemData.ArmorSlot.LEGS: (1 << Region.THIGHS) | (1 << Region.SHINS),
	ItemData.ArmorSlot.FEET: 1 << Region.FEET,
}

const KIND_NAMES := {
	ItemData.DamageKind.SLASH: "Tajo", ItemData.DamageKind.BLUNT: "Contundente",
	ItemData.DamageKind.PIERCE: "Perforante",
}

## Tope de penetración: ningún arma atraviesa la armadura como si no estuviera.
const MAX_PENETRATION := 0.8


## Lo que queda de un golpe de [amount] contra [protection], con [penetration] (0-1).
static func mitigate(amount: float, protection: float, penetration: float = 0.0) -> float:
	if amount <= 0.0:
		return 0.0
	var a := maxf(protection, 0.0) * (1.0 - clampf(penetration, 0.0, MAX_PENETRATION))
	return amount * amount / (amount + a)


## La protección de [values] (x tajo, y contundente, z perforante) contra un golpe de [kind].
static func against(values: Vector3, kind: ItemData.DamageKind) -> float:
	match kind:
		ItemData.DamageKind.BLUNT:
			return values.y
		ItemData.DamageKind.PIERCE:
			return values.z
	return values.x


## La protección de una pieza: x tajo, y contundente, z perforante.
static func of(data: ItemData) -> Vector3:
	if data == null:
		return Vector3.ZERO
	return Vector3(data.armor_slash, data.armor_blunt, data.armor_pierce)


## Las partes que cubre [data] (bits de Region).
static func coverage_of(data: ItemData) -> int:
	if data == null:
		return 0
	if data.coverage != 0:
		return data.coverage
	return int(SLOT_COVERAGE.get(data.armor_slot, 0))


static func covers(data: ItemData, region: Region) -> bool:
	return coverage_of(data) & (1 << region) != 0


## La protección de cada parte (índice Region) con [pieces] puestas: las capas se suman (una
## coraza sobre la ropa de pieles protege lo de las dos).
static func table(pieces: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(Region.size())
	out.fill(Vector3.ZERO)
	for data: ItemData in pieces:
		if data == null:
			continue
		var values := of(data)
		if values == Vector3.ZERO:
			continue
		var mask := coverage_of(data)
		for region in Region.size():
			if mask & (1 << region):
				out[region] += values
	return out


## Lo que suman [pieces] por tipo de golpe, cubran lo que cubran: la cifra de la pantalla de equipo.
static func total(pieces: Array) -> Vector3:
	var out := Vector3.ZERO
	for data: ItemData in pieces:
		out += of(data)
	return out


## «tronco, brazos y muslos».
static func describe_coverage(mask: int) -> String:
	var names := PackedStringArray()
	for region in Region.size():
		if mask & (1 << region):
			names.append(REGION_NAMES[region])
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " y " + names[names.size() - 1]
