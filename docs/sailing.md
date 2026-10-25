# Velas y navegación

Los barcos se propulsan con el viento que reciben sus velas. Sin aparejo, con las velas
recogidas o directamente contra el viento, conservan inercia y responden a las corrientes,
pero no reciben empuje de vela.

## Fabricar e instalar

Con el martillo equipado, **B → Naval → Vela** abre el editor de la vela de pieles.
Se definen por separado el **ancho del paño**, su **alto** y la **altura del mástil**,
en metros y en pasos de 0,25 m. La vista 3D, la superficie y el coste se actualizan
al cambiar cada medida. Se puede orbitar arrastrando y acercar con la rueda, como
en las piezas del casco. El mástil se alarga si hace falta para dejar espacio bajo el paño.

**Construir con esta vela** lleva el aparejo elegido al martillo. El fantasma muestra
su tamaño y el coste; al colocarlo sobre un bloque de cubierta se pagan directamente
pieles, tendones, fibra vegetal y ramas. No requiere un objeto prefabricado ni banco
de trabajo. No se instala en paredes, techos ni sin soporte. El tamaño de celda del casco
no cambia las medidas de la vela; B vuelve al diseño activo y el giro en Y orienta su base.

El ancho admite 0,5–24 m, el alto 0,5–16 m y el mástil 1,5–24 m, dejando al menos 0,75 m
por encima del alto del paño. El diseño inicial es 4 × 3 m con mástil de 5,25 m.
El coste es una piel por cada 2 m², tendones según el contorno del paño y fibra y ramas
según el ancho y la altura del aparejo, redondeando hacia arriba. Un diseño de 4 × 3 m
requiere 6 pieles, 2 tendones, 8 fibras y 4 ramas; uno de 6 × 4 m con mástil de 7,25 m
requiere 12 pieles, 3 tendones, 11 fibras y 6 ramas.

Se pueden instalar varias velas; sus superficies y fuerzas se suman. El martillo permite
desmontar cada una y recuperar los materiales correspondientes a sus medidas.
Las partidas anteriores conservan sus barcos, que necesitan instalar velas para navegar.
Las velas ya colocadas conservan sus medidas originales de 4 × 3 m y mástil de 5,1 m.

## Controles desde cubierta

| Control por defecto | Acción |
|---|---|
| Flecha arriba | Izar: recogidas → ⅓ → ⅔ → completas |
| Flecha abajo | Recoger un nivel |
| Flechas izquierda / derecha | Gobernar a babor / estribor |
| Mantener R | Remar gastando aguante |

Los controles se reasignan en **Opciones → Controles → Navegación**. El despliegue completo
lleva dos segundos, también al recoger. El paño se hincha con viento favorable y flamea
al perderlo; la verga se orienta automáticamente. Caminar usa los controles habituales.
Inventario, mapas, menús, construcción, pesca, descanso y combate sueltan los mandos.
Las velas conservan su estado y continúan trabajando al dejar de controlar el barco.

El indicador de navegación aparece mientras se puede gobernar. La proa está arriba;
la flecha azul indica **hacia dónde sopla** el viento. Enseña su velocidad, la velocidad
del casco respecto al agua, la superficie instalada y el despliegue. También avisa de
calma, viento de proa, velas recogidas y remo.

El remo aplica hasta 1800 N y deja de empujar a 1,5 m/s respecto al agua. Gasta 9 puntos
de aguante por segundo. Los cascos ligeros tampoco pueden superar ese límite con
un solo impulso. Requiere un casco en el agua y se interrumpe al agotarse,
abrir una interfaz o abandonar cubierta. Los cascos pesados aceleran menos con el mismo remo.
El timón conserva un giro lento de maniobra incluso desde parado. Con arrancada
aumenta su respuesta, hasta un máximo de 25°/s. Al soltar las flechas, el giro se
amortigua. El rumbo se controla separado del balance y del cabeceo del oleaje,
con la misma respuesta para cascos ligeros y grandes.

## Viento y fuerzas

`PlanetLoader.get_wind_velocity(world_position)` devuelve m/s a través de `WindField`.
Usa la dirección ya configurada del planeta y `wind_speed_multiplier` del clima resuelto.
Este valor físico se puede definir por evento, separado de `wind_multiplier`, que
controla la vegetación y el audio. Si se omite, hereda `wind_multiplier`, también al
interpolar transiciones entre eventos. `clear` y `cloudy` usan **1,6** para poder navegar
con buen tiempo; su animación y sonido mantienen **0,6**. `wind` conserva **3,2**.
El JSON admite `weather_settings.wind_speed_mps` (8 m/s por defecto). La longitud de
`wind_direction` no define la velocidad: se normaliza antes de proyectarla sobre el
plano tangente al planeta. La proyección se desvanece donde la dirección es radial,
sin inventar una dirección alternativa ni aplicar fuerza vertical. El clima actual
es compartido por el planeta, como ocurre con sus efectos visuales.

`BoatSailing` resta la velocidad del casco al viento para obtener el viento aparente.
El empuje usa `½ × 1,225 × área desplegada × eficiencia del paño × viento aparente²`,
con un multiplicador de potencia de juego de **90**. La madera de construcción pesa
el 10 % de su equivalente macizo: 50 kg por m³ de bloque, representando tablas y
entramados. Cada material tiene su propia masa y solo la madera aporta empuje de
flotación. La piedra y otros materiales actúan como carga; su peso puede hundir el
barco si la madera no basta para sostenerlo. Ver [Masa de construcción](build_materials.md#masa-de-construcción).
Estos ajustes se aplican a barcos y velas ya construidos al iniciar el juego y cargar
la partida, sin cambiar su tamaño ni su coste. La aceleración debida a las velas está limitada
a **4 m/s²** para mantener una arrancada acotada. Este límite también se ajusta junto
con la potencia: con viento fuerte, subir solo el multiplicador no aumentaba el empuje
de los cascos que ya alcanzaban el límite anterior de 1,5 m/s².
La curva de rumbo es simétrica. Su zona muerta es de 45° alrededor de la
dirección de procedencia del viento, con entrada gradual hasta 60°. Permite avanzar
con viento lateral y hacer bordadas. Una pequeña componente lateral produce deriva.
La masa afecta a la aceleración del `RigidBody3D`; no multiplica el empuje disponible.

Las fuerzas actúan cuando el casco desplaza agua, incluso sin jugador. Se aplican al
centro del cuerpo; la escora por altura del mástil y la resistencia estructural del
aparejo quedan para una ampliación. El rozamiento sigue midiéndose respecto al agua;
en barcos, `boat_forward_drag` (0,08) reduce la resistencia longitudinal respecto a la
lateral. La flotación, el balance, los impactos, la inundación y las estelas siguen en
`DynamicGridBody`. Los barcos sustituyen el amortiguamiento lineal global del motor
por esta resistencia respecto al agua para no sumar un freno contra el mundo.

## Colocables, guardado y roturas

Cada vela lleva `SailTrait` (eficiencia del material). `SailDesign` calcula área, coste,
límites y colisión desde las dimensiones de cada instancia. `BoatSailing` descubre los aparejos al
cambiar los colocables mediante `GridBase.props_changed`; no recorre los bloques en
cada tick. La animación del paño usa `shaders/building/hide_sail.gdshader` y una malla
compartimentada de pieles; no hay simulación de tela en CPU.

Cada colocable puede guardar `state`. En las velas contiene `level` (0–3) y
`deployment` (0–1), además de `design` (ancho, alto y altura de mástil). La partida, los blueprints y las conversiones de estática a dinámica
conservan estos datos. Las copias tienen estado independiente. Si no existen, el
aparejo empieza recogido. Los blueprints y sus obras cobran los materiales del diseño;
sus fichas anteriores se recalculan. Cuando el casco se parte, cada vela se traslada con su bloque
de apoyo; al perder ese bloque se elimina del cálculo de empuje.

Las rejillas del casco y del aparejo comparten un único cuerpo físico y un mismo
identificador al guardar. Al cargar partidas antiguas se recupera esa unión si el
conversor había asignado identificadores distintos a rejillas conectadas con exactamente
la misma pose y planeta. Así, los mandos desde cualquier parte de cubierta gobiernan
también la vela y el casco no colisiona contra sus propios rellenos. La recuperación
conserva bloques, materiales y velas; los fragmentos separados mantienen cuerpos propios.

El origen está en `3182efdf` (12 de abril de 2026, arreglo del guardado de rejillas
dinámicas): la primera rejilla recibía `dyn.body_id = sid`, mientras las restantes
tomaban el id del cuerpo compartido, creado con el id de la rejilla apuntada. Convertir
apuntando a una rejilla secundaria dejaba dos ids para un mismo cuerpo. Al guardar se
escribían esos ids y, al cargar, se creaba un cuerpo por id en la misma pose. Los
rellenos navales usan rejillas alineadas separadas para conservar la edición de cada
pieza; por eso este caso aparece en un casco con cubierta y rellenos, aunque visualmente
sea un único barco. La vela se quedaba en un cuerpo y el jugador podía gobernar el otro.
La conversión actual usa el id común, el guardado lo obtiene del cuerpo real y la carga
mantiene ese id también en el propietario. La prueba de regresión convierte apuntando
a la segunda rejilla y gobierna desde la primera después de guardar y cargar.

## Comprobaciones y vista previa

```sh
godot --headless --path . res://tests/building/test_sailing.tscn
godot --headless --path . res://tests/building/test_boat_water.tscn
godot --headless --path . res://tests/building/test_boat_body_links.tscn
godot --path . res://tests/building/sailing_preview.tscn
```

La prueba cubre editor naval, dimensiones independientes, coste y reembolso, obras,
proyección planetaria, curva de rumbo, fuerza, animación,
despliegue gradual, partida, blueprint, conversión, separación del casco, desmontaje,
movimiento del cuerpo físico, controles, menús, remo y aguante.
La prueba de arrancada usa un casco de 120 m³ y 6 toneladas, una vela de 38,5 m² y
viento de 3,75 m/s: debe superar 2 m/s tras diez segundos de simulación.
La prueba con el evento `wind` usa un casco de 18 toneladas, la misma vela y unos
20 m/s de viento favorable: debe superar 15 m/s tras cinco segundos y mantener más de
17 m/s tras diez, sin sobrepasar la velocidad del viento de empopada.
El mismo casco con `clear` recibe unos 10 m/s y debe superar 7 m/s tras cinco segundos
y 8 m/s tras diez, con el aspecto y el oleaje de tiempo despejado.
La prueba de enlaces cubre conversión desde una rejilla secundaria, guardado y carga,
recuperación de partidas antiguas y controles desde una rejilla distinta a la de la vela.

En la vista aislada, las flechas despliegan, A/D cambia el viento, arrastrar orbita y la
rueda acerca. `-- --capture --background` guarda una captura en
`build/building/sailing/sailing.png`; `--headwind` y `--furled` permiten revisar
el paño flameando o recogido.
`--sail-editor` muestra el editor Naval → Vela y captura `editor.png`;
`--large-sail` muestra un aparejo de 6 × 4 m con mástil de 7,25 m y captura `large.png`.
