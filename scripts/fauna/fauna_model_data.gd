class_name FaunaModelData
extends Resource

## Un animal con esqueleto y sus clips (los de un pack, como WildMesh) para la fauna ambiental: qué
## escena, con qué material y a qué escala, el cuerpo que choca, y qué clip pone quieto y a cada
## velocidad. Lo monta SkinnedFaunaModel; dos especies pueden compartir modelo y clips con otro
## material y otra escala (el conejo y la liebre ártica).

## El modelo importado (FBX) con su AnimationPlayer.
@export var scene: PackedScene
## Sus clips, sacados con tools/fauna/extract_animations.gd (sin prefijo y en bucle los ciclos).
## Las pistas van como en la escena importada, desde la raíz del modelo.
@export var animations: AnimationLibrary
## Para todas las superficies del modelo. null = el que traiga.
@export var material: Material
## Uno por superficie de la malla, en su orden, para los modelos con una textura por parte (el
## tiburón). Manda sobre material.
@export var surface_materials: Array[Material] = []
## Escala del modelo a la especie: la de un adulto medio. La de cada individuo varía además con su
## variante (las del perfil).
@export var scale: float = 1.0
## Giro del modelo (grados) para que mire hacia -Z, hacia donde anda el cuerpo: los del pack miran
## hacia +Z.
@export var yaw: float = 180.0
## Cápsula vertical que choca con el suelo (m, a escala 1 de la especie).
@export var collision_radius: float = 0.13
@export var collision_height: float = 0.4

@export_group("Clips")
@export var idle_clip: StringName = &"Idle"
## A ratos, al quedarse quieto, hace esto (pastar, olfatear): un clip de entrada y otro en bucle
## mientras siga quieto. Vacío = siempre idle_clip.
@export var rest_clips: Array[StringName] = []
@export_range(0.0, 1.0) var rest_chance: float = 0.4
## Ciclos de marcha, de más lento a más rápido, y la velocidad de suelo de cada uno (m/s del modelo
## a escala 1, medida sobre los pies en apoyo): cada clip se acelera o se frena a la velocidad del
## cuerpo, y se usa el que menos tenga que cambiar.
@export var gait_clips: Array[StringName] = []
@export var gait_speeds: PackedFloat32Array = []
## Muerte: la hace el cadáver (FaunaCorpse) sobre su copia del esqueleto, así que las pistas van
## desde el Skeleton3D (".:Hueso", como las saca tools/fauna/retarget_clip.gd). null = el cadáver se
## queda en la pose en que murió y rueda.
@export var death: Animation
## Fundido entre clips (s).
@export var blend_time: float = 0.2
