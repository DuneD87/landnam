class_name RenderLayers
extends RefCounted

## Las capas de render (VisualInstance3D.layers, cull_mask de luces y calcos) que el código usa
## para elegir a quién pinta un calco. Una nueva se añade aquí y en project.godot
## (layer_names/3d_render).

## Capa 19: los árboles que se pueden mellar (TreeDetailRenderer); la muesca solo pinta esta.
const NOTCH := 1 << 18
## Capa 20: las mallas que se pueden manchar de sangre (BloodStains).
const STAINABLE := 1 << 19
