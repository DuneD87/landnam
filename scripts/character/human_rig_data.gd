class_name HumanRigData
extends Resource

## How the human bodies sit on the player skeleton, per sex, as baked by
## tools/character/bake_character_human.gd. The skeleton keeps the player's
## bone orientations (so its animations play unchanged) but each body has its
## own joint positions:
##  - `skins`: the bind poses of the body meshes for those joints;
##  - `bone_offsets`: what BodyProportions adds to each bone's local position
##    so the animated skeleton reaches them.
## Both are keyed by sex (&"male", &"female"); offsets by bone name.

@export var skins := {}
@export var bone_offsets := {}
## Rest heights (player skin space, male base) of anatomical landmarks the
## materials use, such as where the underwear bands go.
@export var landmarks := {}
## Skin albedo per sex, and its mean colour (the skin shader tints relative to it).
@export var skin_textures := {}
@export var skin_tones := {}
