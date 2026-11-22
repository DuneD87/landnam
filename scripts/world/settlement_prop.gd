class_name SettlementProp extends Resource

## Un adorno de una construcción de los poblados (SettlementPrefab.props): barriles, cajas, sacos, la
## mercancía de un puesto, el letrero de la tienda, el yunque o la cruz del campanario. Decorado como los
## sitios de trabajo (SettlementDecor.prop): ni se guarda ni se recoge, y sale y se va con su casa.

## Qué es (SettlementDecor.prop): &"barrel", &"crate", &"sack", &"chest", &"anvil", &"forge", &"cross",
## &"sign", &"hide_rack", &"fish_rack", &"goods" (un objeto del juego, [item]).
@export var kind: StringName = &"barrel"
## Su pose en la grid principal (m). Sobre el suelo de la casa, en su muro o, con [grounded], en el
## terreno de fuera (la altura la pone el terreno al trazar el poblado, como la leñera).
@export var pose := Transform3D.IDENTITY
@export var grounded := false
## La mercancía (&"goods": el id del ItemData, que se ve con su escena) o la seña del letrero (&"sign":
## el id de un objeto, que se pinta en la tabla).
@export var item: StringName = &""
## Tamaño (1 = el suyo).
@export var scale := 1.0
