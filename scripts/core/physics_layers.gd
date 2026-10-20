class_name PhysicsLayers
extends RefCounted

## Las capas de física del proyecto, como bits de collision_layer / collision_mask. Una capa nueva
## se añade aquí (y con su nombre en project.godot, layer_names/3d_physics) para no pisar otra.

## Capa 1: terreno, rocas, árboles, grids estáticas y barcos.
const WORLD := 1
## Capa 2: cuerpos dinámicos (grids que se mueven) y criaturas vivas. Muertas pasan a la 0.
const BODIES := 1 << 1
## Capa 9: hurtboxes. Nada choca con ella; la consultan los golpes y los proyectiles.
const HURTBOX := 1 << 8
## Capa 12: las partes de un muñeco de trapo, que chocan entre sí y con el suelo, no con el jugador.
const RAGDOLL := 1 << 11
## Capa 13: lo que se recoge del suelo. Nadie choca con ella; solo la consulta GroundPickup.
const PICKUP := 1 << 12
## Capa 17: el suelo bajo la banquisa, que solo pisa quien está sobre el hielo.
const SEA_ICE_FLOOR := 1 << 16
