# Marcadores del mapa

Con **M** se abre el mapa del planeta actual. **Clic derecho** en un punto abre la ficha de un
marcador nuevo. **Marcar mi posición** usa la posición del jugador. En la ficha se elige entre
casa, recursos, cueva, campamento, peligro, punto de interés y tumba, con un nombre opcional.
**Aplicar** o **Enter** acepta; **Cancelar** o **Esc** descarta la edición.

Un clic sobre un marcador existente permite cambiarle el nombre o el icono, o borrarlo.
Arrastrar desde un marcador sigue desplazando el mapa. Los iconos mantienen su tamaño al hacer
zoom; los nombres personalizados aparecen debajo y el resto se muestra al señalar o editar.
La ficha, sus controles y los iconos tienen un tamaño mínimo legible en 720p y crecen con
la resolución de la pantalla. La zona de clic acompaña al tamaño visible del marcador.
Esc cierra primero la ficha y, si ya está cerrada, el mapa. La X devuelve el control al jugador.

Al morir aparece automáticamente una **tumba** con el texto **Última muerte**. Cada muerte
actualiza ese mismo marcador, incluso al morir en otro planeta; las marcas personales y las
tumbas colocadas a mano se conservan. Se crea aunque el mapa esté cerrado o siga generándose,
y permanece al recuperar los objetos. Se puede editar o borrar como cualquier marcador;
la próxima muerte vuelve a fijar su icono y posición.
Si mueres antes de recuperar el botín, se pierde lo que quedaba en la tumba anterior.
La nueva tumba solo contiene lo que llevabas en la última muerte, aunque ya hubieras
recuperado una parte de los objetos anteriores.

Los marcadores se conservan **al guardar la partida**, junto con el jugador, dentro de
`map_markers`. Cada entrada tiene un id, el `entity_id` del planeta, coordenadas UV del mapa,
icono y nombre; la última muerte lleva además `kind: "last_death"`. Usar UV evita que el origen
flotante mueva las marcas. El caché del mapa del terreno no contiene datos personales y se puede
rehornear sin perderlas.

`MapMarkers` (`scripts/world/map_markers.gd`) mantiene y serializa los datos. `WorldMapUI`
los dibuja y resuelve la selección; `MapMarkerEditor` presenta la ficha. Los iconos SVG
están en `textures/icons/map/`. Cargar una partida sustituye la lista completa; las partidas
anteriores sin esta clave y las partidas nuevas empiezan sin marcadores.

La prueba incluye paso por JSON, planetas distintos, edición y cancelación, zoom y arrastre,
origen flotante y guardado/carga real del jugador:

```sh
godot --headless --path . res://tests/ui/test_map_markers.tscn
```

Con render real, añadir `-- --capture` guarda una vista de los iconos y la ficha en
`build/ui/map_markers.png`, y vistas de la ficha y del selector de iconos en 720p y 1440p
en esa misma carpeta.
