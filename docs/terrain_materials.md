# Mapas del material del terreno

`planet_biomes.gdshader` comparte las lecturas triplanares de los mapas escalares:

| Canal | Dato | Espacio |
|-------|------|---------|
| R | Roughness | Lineal |
| G | Oclusión ambiental (AO) | Lineal |
| B | Altura | Lineal |

Los JSON de Tierra y Luna declaran `biome_settings.packed_material_textures`, en el mismo orden que
`textures`, y `slope_packed_material_texture`. `reef_settings.packed_material_texture` reutiliza un
mapa compatible para R/G. Los archivos originales y sus rutas se conservan para regenerar los mapas.
Un JSON sin los campos nuevos carga los mapas separados. No se empaquetan imágenes durante la carga
del planeta, y los mapas separados no se cargan cuando existe la versión empaquetada.

Para regenerar los ocho materiales (Python 3 y Pillow):

```sh
python3 tools/terrain/pack_material_maps.py
python3 tools/terrain/pack_material_maps.py --check
```

Después hay que abrir el proyecto en Godot para importar los PNG, o usar el ejecutable compatible
con Voxel Tools con `--headless --editor --path . --import`. La importación usa compresión VRAM de
alta calidad y mipmaps; los mapas empaquetados no llevan `source_color` ni importación de normales.
R/G/B reproducen exactamente el canal rojo de cada PNG original antes de la compresión VRAM.

Por cada material activo, roughness/AO/altura pasan de hasta nueve lecturas a tres. El parallax
mantiene sus tres muestras de altura previas al desplazamiento de UV, leyendo B. Biomas, pendientes,
nieve, hielo y escollos usan la misma codificación. Albedo y normales mantienen sus muestras.

`TerrainMaterialData.mean_luma()` extrae el último mip del albedo importado al cargar el planeta,
lo convierte de sRGB a lineal y cachea la luminancia. El detalle cercano y la capa lejana reutilizan
ese escalar, evitando leer el mip 1×1 por fragmento. Un `ShaderMaterial` creado fuera de `Planet`
puede mantener el comportamiento anterior dejando `albedo_means_ready=false`.

**Material del terreno**, en Opciones → Gráficos, controla el detalle cercano, parallax y antitiling
independientemente de la geometría. Ver [options.md](options.md). La calidad Alta conserva los
efectos del planeta; el empaquetado y las medias precalculadas se usan en las tres calidades.
