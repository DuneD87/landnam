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

## Masa de construcción

`BuildMaterial` separa la densidad del material (`density_kg_m3`) de la proporción de
material sólido en la construcción (`solid_fraction`). Son valores de balance del juego.
La masa es el volumen geométrico del bloque × densidad × proporción sólida.

| Material | Densidad configurada | Proporción sólida | Masa por m³ de bloque |
|---|---|---|---|
| Madera de construcción | 500 kg/m³ | 0,10 | 50 kg |
| Piedra | 2400 kg/m³ | 1 | 2400 kg |
| Vidrio | 2500 kg/m³ | 1 | 2500 kg |
| Paja | 80 kg/m³ | 1 | 80 kg |

La madera representa tablas y entramados dentro del volumen que ocupa la pieza. Un cubo
de 1 m pesa 50 kg; uno de 0,5 m pesa 6,25 kg y uno de 2 m, 400 kg. Rampas, paneles y
celdas navales usan la fracción de volumen de su geometría. Un bloque sin material
conocido conserva el respaldo de 500 kg/m³ para partidas antiguas.

El volumen estanco de colisión se conserva para la flotación; aligerar una estructura
no multiplica el volumen de agua que puede desplazar. Con menos peso, un barco necesita
sumergirse menos para equilibrarse. La masa agregada se actualiza con las ediciones,
conversiones y separaciones de las grids, y se vuelve a calcular al cargar una partida.
La masa mínima de un cuerpo dinámico sigue siendo 10 kg.

La flotación se habilita por separado con `BuildMaterial.buoyant`. **Solo la madera**
la tiene activada. Piedra, vidrio, paja y materiales desconocidos aportan peso y
resistencia al agua, pero no empuje ascendente. Un casco de madera puede sostener
estos materiales como carga; si se supera su capacidad, se hunde todo el conjunto.
Las cajas fusionadas separan materiales flotantes y lastre, también en el LOD lejano,
para que añadir piedra no aumente la capacidad de flotación.

```sh
godot --headless --path . res://tests/building/test_building_mass.tscn
godot --headless --path . res://tests/building/test_boat_water.tscn
```

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
