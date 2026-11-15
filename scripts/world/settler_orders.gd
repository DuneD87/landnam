class_name SettlerOrders
extends RefCounted

## Los oficios que se mandan a los colonos, que se dan solo desde el trono (ThroneView): cada uno una
## vez, con su texto, su dibujo (OrderGlyphs), su color (el de su zona en el suelo y el de su icono), su
## categoría y si pide marcar una zona. Un oficio nuevo es una entrada más en ORDERS (y su SettlerTask).

enum Category {RESOURCES, FOOD, WORKS, DEFENSE}
## NONE: no tiene zona (la hoguera de la base). BASE: se marca o, con clic derecho, alrededor de la base.
## REQUIRED: hay que marcarla.
enum Zone {NONE, BASE, REQUIRED}

const CATEGORIES: Array[Category] = [Category.RESOURCES, Category.FOOD, Category.WORKS, Category.DEFENSE]
const CATEGORY_NAMES := {Category.RESOURCES: "SETTLER_CAT_RESOURCES", Category.FOOD: "SETTLER_CAT_FOOD",
	Category.WORKS: "SETTLER_CAT_WORKS", Category.DEFENSE: "SETTLER_CAT_DEFENSE"}

## En el orden en que salen: "job" y "shift" (el turno de la guardia) son lo que se manda
## (SettlerWork.assign); "order" el texto del botón y "name" el del oficio.
const ORDERS := [
	{"job": SettlerWork.Job.FELL, "shift": 0, "order": "SETTLER_ORDER_FELL", "name": "SETTLER_JOB_FELL",
		"glyph": &"fell", "category": Category.RESOURCES, "zone": Zone.BASE, "color": Color(0.55, 0.9, 0.35)},
	{"job": SettlerWork.Job.MINE, "shift": 0, "order": "SETTLER_ORDER_MINE", "name": "SETTLER_JOB_MINE",
		"glyph": &"mine", "category": Category.RESOURCES, "zone": Zone.BASE, "color": Color(0.72, 0.8, 0.95)},
	{"job": SettlerWork.Job.CLEAR, "shift": 0, "order": "THRONE_ORDER_CLEAR", "name": "SETTLER_JOB_CLEAR",
		"glyph": &"clear", "category": Category.RESOURCES, "zone": Zone.REQUIRED, "color": Color(1.0, 0.72, 0.25)},
	{"job": SettlerWork.Job.HUNT, "shift": 0, "order": "SETTLER_ORDER_HUNT", "name": "SETTLER_JOB_HUNT",
		"glyph": &"hunt", "category": Category.FOOD, "zone": Zone.BASE, "color": Color(0.85, 0.6, 0.4)},
	{"job": SettlerWork.Job.FISH, "shift": 0, "order": "SETTLER_ORDER_FISH", "name": "SETTLER_JOB_FISH",
		"glyph": &"fish", "category": Category.FOOD, "zone": Zone.BASE, "color": Color(0.35, 0.9, 0.9)},
	{"job": SettlerWork.Job.COOK, "shift": 0, "order": "SETTLER_ORDER_COOK", "name": "SETTLER_JOB_COOK",
		"glyph": &"cook", "category": Category.FOOD, "zone": Zone.NONE, "color": Color(1.0, 0.55, 0.3)},
	{"job": SettlerWork.Job.WATER, "shift": 0, "order": "SETTLER_ORDER_WATER", "name": "SETTLER_JOB_WATER",
		"glyph": &"water", "category": Category.FOOD, "zone": Zone.BASE, "color": Color(0.45, 0.65, 1.0)},
	{"job": SettlerWork.Job.BUILD, "shift": 0, "order": "SETTLER_ORDER_BUILD", "name": "SETTLER_JOB_BUILD",
		"glyph": &"build", "category": Category.WORKS, "zone": Zone.BASE, "color": Color(0.95, 0.85, 0.45)},
	{"job": SettlerWork.Job.GUARD, "shift": 0, "order": "THRONE_ORDER_GUARD_DAY", "name": "SETTLER_JOB_GUARD_DAY",
		"glyph": &"guard_day", "category": Category.DEFENSE, "zone": Zone.REQUIRED, "color": Color(0.95, 0.3, 0.3)},
	{"job": SettlerWork.Job.GUARD, "shift": 1, "order": "THRONE_ORDER_GUARD_NIGHT", "name": "SETTLER_JOB_GUARD_NIGHT",
		"glyph": &"guard_night", "category": Category.DEFENSE, "zone": Zone.REQUIRED, "color": Color(0.95, 0.3, 0.3)},
]

## Sin oficio (o parado del todo): su dibujo y color.
const IDLE_GLYPH := &"idle"
const IDLE_COLOR := Color("9c968c")


## La entrada de [job] (y de su turno, si es la guardia), o {}.
static func find(job: SettlerWork.Job, shift := 0) -> Dictionary:
	for order: Dictionary in ORDERS:
		if order.job == job and (job != SettlerWork.Job.GUARD or order.shift == shift):
			return order
	return {}


## La entrada del oficio de [c], o {} si no tiene.
static func of(c: Companion) -> Dictionary:
	if c.work.job == SettlerWork.Job.NONE:
		return {}
	return find(c.work.job, c.work.shift)


static func in_category(category: Category) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for order: Dictionary in ORDERS:
		if order.category == category:
			out.append(order)
	return out


## El color de la zona de [job] en el suelo.
static func color_of(job: SettlerWork.Job) -> Color:
	var order := find(job)
	return order.color if not order.is_empty() else Color.WHITE


## El nombre del oficio (sin traducir) de [job] con su turno.
static func name_of(job: SettlerWork.Job, shift := 0) -> String:
	var order := find(job, shift)
	return order.name if not order.is_empty() else "SETTLER_JOB_NONE"


## Qué puesto de la lista ocupa el oficio de [c] (los sin oficio, al final): para ordenarla.
static func rank_of(c: Companion) -> int:
	var order := of(c)
	return ORDERS.find(order) if not order.is_empty() else ORDERS.size()
