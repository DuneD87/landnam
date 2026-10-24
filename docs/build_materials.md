# Texturas de los bloques de construcción

La madera son troncos apilados y la piedra un muro de cantos rodados. Las dos texturas salen de
`tools/building/gen_block_textures.py`, que dibuja la geometría (cilindros, piedras) y de ella saca
todos los mapas, de modo que altura, normal y oclusión casan y el parallax no flota.

La paja usa el mismo generador (`--only thatch --size 1024`), con tallos secos a lo largo de V,
tonos por tallo y extremos escalonados. Sus cuatro mapas están en `textures/build_materials/thatch/`
y el material independiente en `data/building/thatch.tres`. Cubre también 2×2 m; el relieve de
textura es de 12 mm (`heightmap_scale = 0.6`), además de las hiladas de la propia malla. Para
generar solo paja bastan numpy y Pillow; los troncos y la piedra también requieren scipy.

| Mapa | Contenido | Espacio |
|------|-----------|---------|
| `_albedo` | Color | sRGB |
| `_normal` | Normal, convención OpenGL (Y+) | Lineal |
| `_orm` | R = oclusión, G = roughness, B = metalness (0) | Lineal |
| `_height` | Altura, blanco = más saliente | Lineal |

Cada textura cubre **2 × 2 m** y tilea en los dos ejes: 8 troncos de 25 cm, o unas 13 hiladas de
piedra. Los materiales (`data/items/material/wood.tres`, `stone.tres`) son `ORMMaterial3D` con
deep parallax y `uv1_scale = 0.5`.

## UV en metros

`ChunkMeshBuilder` proyecta cada vértice sobre el plano de su cara y emite la UV en metros de la
grid (`planar_uv`). U va siempre en horizontal y V hacia abajo por la cara, así que los troncos
quedan tumbados en paredes y rampas; en suelos y techos U sigue el eje X de la grid. Con eso:

- la textura sigue de un bloque al de al lado sin costura,
- no se deforma en los triángulos de rampas y esquinas,
- un tronco mide lo mismo en un bloque de 0,25 m que en uno de 2 m.

`BlockMeshGenerator` usa la misma proyección para que los iconos enseñen la escala real. Un material
de bloque nuevo tiene que poner en `uv1_scale` la inversa de los metros que cubre su textura.

Los tejados usan `ThatchRoofMesh`: proyecta con los ejes de la pieza girada para que los tallos
sigan la pendiente incluso al rotar o reflejar el bloque. `BuildMaterial.allowed_block_ids` limita
las formas ofrecidas por material: paja ofrece faldón y cumbrera; piedra y vidrio conservan
sus seis formas, y madera añade el panel triangular para frontones. Una lista vacía permite todas.

Los paneles cuadrados de madera usan una variante de `BlockData` con la cara exterior al ras
del muro; los triángulos tienen la misma cara y todo su grosor hacia dentro. Los iconos,
el fantasma y las colisiones usan también la variante. Se mantiene la misma proyección de UV
del muro para que el parallax no marque juntas entre superficies a distinta profundidad. Si hay
un cubo macizo detrás, el mallador conserva la separación de las caras para evitar parpadeos.

## Parallax

`heightmap_scale` es el relieve en metros dividido entre `0,01 × 2 m`: 6 en la madera (12,5 cm, el
radio del tronco) y 3,5 en la piedra (7 cm). El script imprime el valor que corresponde a cada
textura. Si el relieve se desliza al revés al mover la cámara, activar
`heightmap_flip_binormal` en el material.

## Regenerar

Requiere numpy, scipy y Pillow. Si el Python del sistema no los trae, en un venv aparte:

```sh
python3 -m venv /tmp/texvenv && /tmp/texvenv/bin/pip install numpy scipy pillow
/tmp/texvenv/bin/python tools/building/gen_block_textures.py
/tmp/texvenv/bin/python tools/building/gen_block_textures.py --only logs --preview /tmp/prev
```

Las semillas son fijas: la misma ejecución da los mismos PNG. `--preview` deja un render con luz
rasante, sin parallax, del mosaico 2×2 y de un recorte a resolución completa. Los `.import` solo se
escriben si no existen, para no pisar el uid que añade Godot.
