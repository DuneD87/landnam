# Ambiente del fondo marino

Polvo en suspensión y flora procedural. La óptica (niebla, cáusticas, haces)
está en [ocean_water.md](ocean_water.md); la fauna, en
[ambient_fauna.md](ambient_fauna.md).

## Polvo en suspensión

`UnderwaterDust` (`scripts/water/underwater_dust.gd`) es un `MultiMeshInstance3D`
que crea `OceanSystem` al montar el agua. **No es un sistema de partículas.** Las
motas están clavadas a una retícula fija en coordenadas del mundo: su posición
sale de la celda que ocupan, así que no se mueven, ni nacen, ni mueren, y el
shader no usa `TIME` en ninguna parte. Al desplazarte solo cambia qué celdas
rodean a la cámara, y el paralaje que eso produce es la señal de profundidad que
el agua abierta no tiene.

El primer intento sí eran partículas vivas, con deriva y ciclo de vida, y se leía
como nieve: puntos claros en movimiento sobre agua oscura. Dos decisiones lo
separan de aquello, y conviene no deshacerlas:

- **Quietas.** `tests/water/test_underwater_dust.gd` renderiza el mismo encuadre
  con segundos de diferencia y exige cero píxeles de cambio; también comprueba
  que al volver al mismo sitio se ve lo mismo, que es lo que prueba que están
  ancladas al mundo y no a la cámara. Necesita ventana: en `--headless` no hay
  nada que capturar.
- **Del color del agua.** Las motas no tienen color propio: parten del color de
  la niebla a la profundidad de la cámara, calculado con la misma mezcla que usa
  el compositor (`uw_depth_color`), y cada una se aparta de él dentro de
  `shade_range`. Unas quedan más claras y otras más oscuras que el agua, como el
  detritus real, pero ninguna es blanca, y al oscurecerse el agua en profundidad
  el polvo la acompaña. Un color fijo era lo que las hacía parecer nieve.
- **Cercanas.** El campo se apaga a unos cinco metros: una mota aislada lejos, en
  medio del agua, vuelve a leerse como una estrella por tenue que sea. Las muy
  pegadas a la cámara se encogen para que ninguna haga borrón.

Son **opacas** a propósito: el compositor calcula la niebla desde el búfer de
profundidad, así que una mota transparente recibiría la niebla de lo que tiene
detrás. Escribiendo profundidad, cada mota recibe la suya. Solo se dibujan con la
cámara sumergida, según el mismo plano de línea de flotación que usan la
superficie y la niebla, y no dentro de un compartimento seco de un barco.

Ajustes del nodo: `cell_size` (0.5 m) manda la separación, `grid_side` (20) el
alcance, `shade_range` el contraste contra el agua, y la densidad va por
profundidad, de `surface_occupancy` arriba a `occupancy` a partir de
`full_density_depth`. Son 8000 motas en una sola llamada de dibujado.

## Flora sumergida

Cuatro especies procedurales, sin texturas y con color por vértice, en el mismo
estilo que la fauna marina:

| Especie | Altura | Profundidad | Triángulos |
| --- | --- | --- | --- |
| `seagrass` (pradera) | 0.8 m | 2–22 m | 192 |
| `kelp` (laminaria) | 4.7 m | 6–40 m | 1006 |
| `sea_fan` (gorgonia) | 1.4 m | 5–35 m | 1782 |
| `coral` (cuerno de alce) | 1.0 m | 3–20 m | 3640 |

Se instancian con el sistema de vegetación que ya existía: cada especie es un
item del JSON del planeta con su generador, y el filtro de altura del generador
es lo que las mantiene bajo el agua. Las alturas del JSON son relativas al radio
del planeta y el mar está en `-water_level`, así que una franja de 2 a 22 m de
profundidad se escribe como `min_height: -72, max_height: -52`.

El material viaja **dentro** de la malla horneada, porque el planeta recoge los
materiales de item con `surface_get_material`. El shader
(`shaders/vegetation/marine_flora.gdshader`) mueve la planta con la corriente,
no con el viento: dos armónicos, peso creciente hacia la punta, fase según la
posición del mundo para que las matas vecinas no ondulen a la vez, y la punta
baja al inclinarse en vez de estirarse. El coral y la gorgonia son rígidos y
solo acusan la corriente en las puntas.

El color varía en dos niveles, que es lo que evita el campo clonado. Dentro de
una planta, el horneador desvía en tono y claridad el color de cada hoja o rama
(`_vary`), moviendo poco la saturación, que es lo que delata un tinte falso.
Entre plantas, el shader saca un tono y una claridad propios del **origen de la
instancia**, y los aplica sobre una paleta por especie (`tint_cool` y
`tint_warm`): verdes en la pradera, pardos y oliva en la laminaria, rosas y
morados en la gorgonia, y tostados calcáreos con puntas claras en el coral. Sale
de la posición, así que no hace falta pasar datos por instancia al multimesh.

Los generadores usan además un **ruido de parcheo** (`"noise"` en el JSON), que
agrupa las plantas en manchas en vez de repartirlas parejas por el fondo. Lo
resuelve `FastNoiseLite` dentro del generador; no hace falta un grafo de vóxel.

Para regenerar las mallas:

```sh
godot --headless --path . --script res://tools/vegetation/bake_marine_flora.gd
```

Para revisarlas, `tests/vegetation/marine_flora_preview.tscn` las muestra a
escala con el vaivén en marcha; con `-- --capture` guarda las vistas en
`build/vegetation/`. El cableado (mallas, materiales, items y franjas de
profundidad) lo comprueba `tests/vegetation/test_marine_flora.tscn`.
