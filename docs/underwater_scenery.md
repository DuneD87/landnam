# Ambiente del fondo marino

Polvo en suspensión bajo el agua. La óptica (niebla, cáusticas, haces)
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
