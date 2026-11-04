class_name SettlementPopulation extends RefCounted

## Quién vive en un poblado: un vecino por lecho de sus casas (SettlementPrefab.beds), alguno vacío,
## cada uno con su nombre, su aspecto (una semilla para CharacterAppearance.randomize_values), su muda
## de pieles y, si hay sitio de trabajo para él (SettlementWorkplace), su oficio y su herramienta. Sale
## siempre igual del plano y de la semilla: no se guarda.

## Parte de los lechos con alguien.
const OCCUPANCY := 0.8
## A veces lleva algo en la cabeza (la muda sin ello): la cabeza del animal de su ropa si la hay
## (HEADS, por la primera parte del id de la prenda del tronco), y si no la capucha de oso.
const HOOD_CHANCE := 0.12
const HOOD := &"fur_hood"
const HEADS := {
	&"fur": [&"fur_headdress", &"fur_hood"],
	&"deer": [&"deer_headdress"],
	&"boar": [&"boar_headdress"],
}

const MALE_NAMES := ["Ásbjörn", "Bjarni", "Egil", "Einar", "Eirík", "Gísli", "Grím", "Gunnar", "Hákon",
	"Hallbjörn", "Harald", "Helgi", "Hrafn", "Ingólf", "Ívar", "Ketil", "Kolbein", "Leif", "Njál", "Óláf",
	"Orm", "Ragnar", "Sigurd", "Snorri", "Steinar", "Svein", "Thorbjörn", "Thorkel", "Thorstein", "Ulf",
	"Vigfús", "Önund"]
const FEMALE_NAMES := ["Álfhild", "Ásta", "Ástrid", "Bergthóra", "Bodil", "Dagný", "Freydís", "Fríða",
	"Gríma", "Gudrún", "Gunnhild", "Gyda", "Halla", "Helga", "Hild", "Ingrid", "Jórunn", "Ragnhild",
	"Rannveig", "Sigríd", "Sigrún", "Solveig", "Thóra", "Thordís", "Thorgerd", "Thórunn", "Ulfhild", "Unn",
	"Vigdís", "Yrsa"]
## La herramienta de cada oficio (por sitio de trabajo), a veces la de bronce.
const TOOLS := {
	&"woodpile": [&"stone_axe_01", &"bronze_axe"],
	&"garden": [&"stone_hoe_01", &"bronze_hoe"],
	&"bench": [&"stone_hammer_01", &"stone_hammer_01"],
}
const BRONZE_CHANCE := 0.3
## Mudas de pieles: ids de ItemData de la armadura de la edad de piedra que se fabrica (no la vieja de
## hide_*). Las ligeras de manto, taparrabos y mocasines; las de abrigo, de casaca, calzas y botas; con
## manoplas o guanteletes alguna, y un par mezcladas.
const OUTFITS := [
	[&"fur_mantle", &"fur_loincloth", &"fur_moccasins"],
	[&"fur_mantle", &"fur_loincloth", &"fur_moccasins", &"fur_mittens"],
	[&"deer_mantle", &"deer_loincloth", &"deer_moccasins"],
	[&"deer_mantle", &"deer_loincloth", &"deer_moccasins", &"deer_mittens"],
	[&"boar_mantle", &"boar_loincloth", &"boar_moccasins"],
	[&"boar_mantle", &"boar_loincloth", &"boar_moccasins", &"boar_mittens"],
	[&"fox_mantle", &"fox_loincloth", &"fox_moccasins"],
	[&"fox_mantle", &"fox_loincloth", &"fox_moccasins", &"fox_mittens"],
	[&"deer_mantle", &"fur_loincloth", &"deer_moccasins"],
	[&"fur_coat", &"fur_breeches", &"fur_boots"],
	[&"fur_coat", &"fur_breeches", &"fur_boots", &"fur_gauntlets"],
	[&"bison_coat", &"bison_breeches", &"bison_boots"],
	[&"bison_coat", &"bison_breeches", &"bison_boots", &"bison_gauntlets"],
	[&"antler_coat", &"antler_breeches", &"antler_boots"],
	[&"arctic_coat", &"arctic_breeches", &"arctic_boots", &"arctic_gauntlets"],
	[&"fur_coat", &"bison_breeches", &"fur_boots"],
]
## El nombre de un poblado: la primera parte (lo que hay allí) y la segunda (qué clase de sitio es).
const PLACE_HEADS := ["Hrafn", "Ulfs", "Eik", "Stein", "Birki", "Hval", "Sel", "Hóla", "Reykja", "Fjarðar",
	"Mel", "Sand", "Hlíðar", "Ás", "Bjarnar", "Grjót", "Lax", "Hest", "Kálfa", "Vatns", "Örn", "Mýrar",
	"Breiða", "Hvíta", "Svarta", "Eyvindar", "Þóris", "Kolla"]
const PLACE_TAILS := ["staðir", "bær", "vík", "nes", "holt", "dalur", "fell", "á", "garður", "tún", "hólar",
	"eyri", "hlíð", "vellir", "brekka", "skógur"]


## Lo que lleva en la cabeza quien viste [outfit] (la semilla [look] elige entre las que van con ella).
static func head_for(outfit: Array[StringName], look: int) -> StringName:
	var animal := String(outfit[0]).get_slice("_", 0) if not outfit.is_empty() else ""
	var heads: Array = HEADS.get(StringName(animal), [HOOD])
	return heads[absi(look) % heads.size()]


## El nombre del poblado [v]: siempre el mismo para la misma semilla.
static func village_name(v: int, seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, v, "name"])
	return String(PLACE_HEADS[rng.randi() % PLACE_HEADS.size()]) + String(PLACE_TAILS[rng.randi() % PLACE_TAILS.size()])


## Los vecinos del poblado [v] (su plano [plan]; [prefabs]: SettlementPrefab por id), en orden de casa y
## de lecho: [{"id": "<poblado>:<casa>:<lecho>", "name", "sex", "look": semilla del aspecto, "outfit":
## Array[StringName], "home": índice de la casa en el plano, "bed": índice del lecho en su prefab, y si
## tiene oficio "job": {"building", "work" (índice en sus "work" del plano), "stand", "kind", "tool"}}].
static func residents(plan: Dictionary, v: int, prefabs: Dictionary, seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, v, "people"])
	var out: Array[Dictionary] = []
	var buildings: Array = plan.get("buildings", [])
	for b in buildings.size():
		var prefab: SettlementPrefab = prefabs.get(buildings[b].prefab)
		if prefab == null:
			continue
		for k in prefab.beds.size():
			# Cada tirada se hace aunque el lecho quede vacío: un vecino no cambia por los de antes.
			var here := rng.randf() < OCCUPANCY
			var sex := &"male" if rng.randf() < 0.5 else &"female"
			var names: Array = MALE_NAMES if sex == &"male" else FEMALE_NAMES
			var name: String = names[rng.randi() % names.size()]
			var look := rng.randi()
			var outfit: Array[StringName] = []
			outfit.assign(OUTFITS[rng.randi() % OUTFITS.size()])
			var hood := rng.randf() < HOOD_CHANCE
			if not here:
				continue
			if hood:
				outfit.append(head_for(outfit, look))
			out.append({"id": "%d:%d:%d" % [v, b, k], "name": name, "sex": sex, "look": look, "outfit": outfit,
				"home": b, "bed": k})
	_assign_jobs(out, buildings, hash([seed, v, "work"]))
	return out


## Reparte los puestos de los sitios de trabajo del plano entre [people], al azar, uno por puesto.
static func _assign_jobs(people: Array[Dictionary], buildings: Array, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var posts: Array[Dictionary] = []
	for b in buildings.size():
		var work: Array = buildings[b].get("work", [])
		for w in work.size():
			for s in (work[w].stands as PackedVector3Array).size():
				posts.append({"building": b, "work": w, "stand": s, "kind": StringName(work[w].kind)})
	var order: Array = range(people.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	for p in mini(posts.size(), people.size()):
		var post: Dictionary = posts[p]
		var tools: Array = TOOLS.get(post.kind, [])
		if not tools.is_empty():
			post.tool = tools[1] if rng.randf() < BRONZE_CHANCE else tools[0]
		people[order[p]].job = post
