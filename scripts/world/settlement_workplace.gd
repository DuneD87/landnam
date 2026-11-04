class_name SettlementWorkplace extends Resource

## Un sitio de trabajo de una construcción (SettlementPrefab.workplaces): la leñera, el huerto o el
## banco. SettlementManager lo pone como decorado con la casa (SettlementDecor) y los aldeanos con
## oficio trabajan en él (Villager). Lo de fuera se asienta en el terreno al trazar el poblado
## (SettlementLayout) y cuenta en la huella de la casa: no pisa otras construcciones.

## &"woodpile" (leñador, con hacha), &"garden" (granjero, con azada) o &"bench" (artesano, con martillo).
@export var kind: StringName = &"woodpile"
## Su pose en la grid principal (m). Fuera, el origen va a ras de suelo (la altura la pone el terreno);
## dentro, en lo alto del suelo de la casa.
@export var pose := Transform3D.IDENTITY
## Dentro de la casa (en su suelo) o fuera (en el terreno).
@export var indoor := false
## Lo que ocupa a ras de suelo (m, a lo largo de X y Z de su pose, centrado en ella).
@export var size := Vector2(2.0, 2.0)
## Dónde se pone cada uno que trabaja en él (uno por punto) y hacia dónde mira, en su pose (m).
@export var stands := PackedVector3Array()
@export var looks := PackedVector3Array()


## Sus esquinas a ras de suelo, en la grid principal.
func corners() -> PackedVector3Array:
	var half := size * 0.5
	var out := PackedVector3Array()
	for q: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y),
			Vector2(-half.x, half.y)]:
		out.append(pose * Vector3(q.x, 0.0, q.y))
	return out
