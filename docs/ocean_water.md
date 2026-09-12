# Agua: espectro, espuma y óptica

## Composición subacuática y atmósfera

La atmósfera continúa en **POST_TRANSPARENT**. El agua se integra dentro de ese
mismo shader: no hay quad, buffers de transporte a resolución de pantalla, pase
de resolución ni copia del color. La profundidad de la escena se conserva.

`UnderwaterRenderPass` calcula el campo de altura y normal en **dos niveles**, cada uno
de 256×256 sobre el mismo plano tangente centrado bajo la cámara:

| Nivel | Extensión | A 2.5 m de profundidad |
|---|---|---|
| Lejano | `clamp(12 + 3·prof + 2·amplitud, 12, 96)` m | 27.5 m → 0.215 m/téxel |
| Cercano | `clamp(3 + 1.2·prof + 0.5·amplitud, 3, 24)` m | 6 m → 0.047 m/téxel |

**Una sola extensión no puede servir a los dos casos**, y conviene no volver a intentarlo:

- El radio de la ventana de Snell es `1.135 · profundidad`. A dos metros son 2.3 m de
  superficie, que con el nivel lejano son una docena de téxeles: el borde sale liso y la
  ventana se lee como una burbuja deformándose. Empeora cuanto **menos** profundidad hay,
  y por eso al alejarse y bajar el efecto sí convence (a 20 m son 36 téxeles, a 40 m son 60).
- Fuera del campo la normal cae a la esfera analítica, que es un espejo perfecto. Estrechar
  la extensión para arreglar la ventana deja el techo sin ondular a media distancia.

Medido: con los mapas de normales del material y `normal_slope_limit` a 0.16, forzar la
extensión a 6 m convierte el borde liso en almenado, con lóbulos y gotas sueltas. Subir la
frecuencia del ruido y casi triplicar el límite de pendiente (0.45) **no** lo consigue, así
que el límite es la resolución del campo, no el espectro ni los mapas de detalle.

El mismo shader de cómputo resuelve los dos niveles: la extensión llega por **push
constant**, porque el buffer de parámetros es común a los dos despachos, y cada uno escribe
su propia imagen. En el píxel, `uw_surface_at` y `uw_surface_normal` muestrean el nivel
cercano dentro de su caja y funden al lejano en el borde (`smoothstep(0.40, 0.5)`); solo la
banda de fusión paga los dos filtrados cúbicos. Coste medido: **+0.05 ms** a 2560×1440
(0.93 → 0.99 mirando arriba, 0.44 → 0.48 al horizonte) y **+1 MiB por vista**. La
diferencia entre mar plano y mar real en el techo lejano se conserva: 0.043 / 0.026 / 0.014
a 4 / 12 / 25 m, frente a 0.046 / 0.028 / 0.014 con un solo nivel. Cada texel invierte el
mismo espectro Gerstner que usa la superficie, incluida la costa y el temporal.
El compositor busca la salida del rayo consultando esa textura, en vez de
recalcular docenas de veces el espectro completo por píxel. Los campos de altura y
detalle ocupan **2 MiB por vista**, independientemente de la resolución. Ya no hay
caché de normales geométricas aparte: desde que el detalle óptico se evalúa por
píxel, los dos niveles guardan exactamente la misma normal analítica, así que el
par RGBA16F sobraba y se retiró (**-1 MiB por vista**). Fuera del agua se
omite su actualización. Los compartimentos secos se clasifican una vez por
vista en CPU, antes de despachar.

La clasificación del near plane conserva el mismo plano de flotación que el
material de superficie. Un objeto sumergido bloquea la atmósfera; un rayo que
sale del agua integra aire desde la salida. El cielo se proyecta sobre esa
intersección siguiendo la normal de las olas. La proyección es una aproximación
artística continua: `cos(theta_air) = cos(theta_water)^(1.333²)`. Conserva la
desviación de ángulos pequeños y se extiende hasta el horizonte, sin el corte
del cono de Snell de la versión anterior. No es refracción dieléctrica exacta.

Su visibilidad decae con la distancia real cámara–superficie mediante
`exp(-exit_t / surface_projection_distance)`, además de la extinción del medio.
El valor inicial es 18 metros. La energía que pierde la proyección pasa a la
luz reflejada del agua. Al alejarse, la respuesta completa de la superficie
(cielo y reflejo) se mezcla con la integral del agua hasta el fondo o el alcance
óptico. La mezcla empieza al 45 % de `roof_end` y termina en `roof_end`, que es
el menor entre el alcance óptico y el 80 % de la semiextensión del campo lejano.
Así termina antes del borde del campo. Desvanecer solo el cielo dejaba el reflejo
encendido hasta perder la intersección y producía una línea visible.
La contribución del fondo se conserva por separado durante la mezcla; sin
geometría se usa solo la luz dispersada del agua, sin filtrar el Sky rasterizado.
No se usa una máscara circular ni la mezcla angular amplia descartada antes.

El material exterior, el cristal y el compositor calculan el corte de flotación
en coordenadas relativas: primero cámara menos punto de superficie, después
el pequeño desplazamiento del near plane. Así no se pierden centímetros al
sumarlos a coordenadas de decenas de kilómetros. La prueba GPU del corte compara
el raster sin atmósfera con la clasificación del compositor: 0 píxeles discrepantes
en cuatro posiciones de cámara, frente a 596 con la reconstrucción mundial anterior.

La luz reflejada del techo se resuelve **marchando el rayo reflejado** con la misma
integral de tres muestras que usa el medio, arrancando en la superficie y hacia abajo.
La profundidad de cada muestra la marca el propio rayo reflejado, no la de la cámara.

Antes era una forma cerrada, `uw_depth_color(cam_depth)` por un acumulado sobre
`tir_reflection_depth`. Esa forma **no dependía de la normal**: la paleta y la luz
descendente se leían a la profundidad de la cámara, y el único término direccional
estaba ya saturado a 60 m. Por eso todo lo que caía fuera de la ventana de Snell era un
degradado liso que el oleaje no podía deformar a ninguna distancia, y por eso ningún
parámetro del nodo `Underwater` cambiaba esa mitad de la pantalla. Con el rayo marchado,
a ángulo rasante la dirección reflejada es hipersensible a la normal, que es justo donde
antes no pasaba nada: la diferencia entre mar plano y mar real en la mitad superior del
fotograma pasa de 0 a **0.046 a 4 m, 0.028 a 12 m y 0.014 a 25 m**.

Dos intentos previos de oscurecer ese techo se revirtieron, y conviene no repetirlos:
mover **la luz descendente** a la profundidad reflejada cuenta la misma columna dos veces
(con 50 m el canal rojo cae a 0.009, el techo se va a negro y se despega de los píxeles
cuyo rayo no llega a la superficie); y mover solo **la paleta** parece inofensivo a poca
profundidad pero `reflection_depth` llevaba `cam_depth` dentro, así que el oscurecimiento
se componía con la profundidad: 40 % a cuatro metros, 2.4× a veinticinco.

**No se puede juzgar el techo con una sola profundidad ni con un solo encuadre.** El
barrido mínimo es 4/12/25/40 m mirando al horizonte, que es donde ocupa media pantalla y
donde está la frontera contra los píxeles que no alcanzan la superficie.

El fondo que el raster dejó detrás del agua es el `Sky` —espacio, estrellas y disco
solar— tomado en el píxel **sin** refractar, así que se atenúa según cuánto se haya
doblado el rayo. Sin eso el sol se dibuja sobre el techo reflejado, fuera de la
ventana. En reflexión total ya lo anulaba la transmitancia casi nula.

El modo de depuración 7 muestra la elevación del rayo de la proyección continua.

## Ondulación del techo: por píxel, no horneada

El detalle óptico **no se hornea en la caché**. Se evaluaba allí, y ése era el motivo
real de que la ventana de Snell se viera como una esfera lisa: 256 téxeles repartidos
sobre decenas de metros filtran a cero todo lo que baje del palmo, y ésa es justo la
escala que rompe el borde en fragmentos. Medido con la sonda, apagar los mapas de
detalle y triplicarlos daban la misma imagen (gradiente 0.00139 frente a 0.00147): el
detalle horneado aportaba un 6% de la estructura del techo. La amplitud de la ola
tampoco cambiaba nada (0.00137 a 0.00141 entre 0 y 6 m).

Ahora `uw_detail_normal` muestrea los dos mapas del material del océano en el punto
de salida del rayo, con la huella del píxel como filtro, y el caché solo guarda la ola
analítica. La huella se divide por el coseno de incidencia: a ras de superficie el
píxel se proyecta en una elipse larguísima y filtrarla como si fuese redonda estiraba
el borde crítico en filamentos en vez de romperlo en trozos.

Dos mandos propios, que no toca el mar exterior:

- `surface_ripple_scale` (1.0) multiplica `normal_scale1/2`. Por debajo de 1 el techo
  queda más picado que el mar visto desde arriba.
- `surface_ripple_strength` (4.0) escala la pendiente **y su tope**. Sin lo segundo,
  `normal_slope_limit` (0.16, del material exterior, 9 grados) deja la faceta demasiado
  plana para cruzar el ángulo crítico salvo justo en el borde, y la ventana sale entera
  con los bordes deshilachados en vez de abrirse en ventanas sueltas por todo el techo.

La fuerza **no** tira de la dirección refractada: `ripple_slope` se divide por ella. La
fuerza decide qué facetas abren al aire y `underside_refraction` cuánto se tuerce el
cielo que se ve por ellas. Acopladas, subir el picado mandaba los rayos fuera de
pantalla, donde el fondo reproyectado no tiene datos, y aparecían manchas que se
movían con el oleaje.

## El borde crítico tiene que existir

La transición entre transmisión y reflexión iba de coseno 0.40 a 0.88, una rampa que
cubre toda la bóveda. Sin un borde definido las ondas no tienen nada que romper, y por
eso el techo salía como un degradado continuo. Ahora se centra en el coseno crítico
real (0.662 para n=1.333) con una anchura que fija `surface_window_sharpness` (0.8):
0 reproduce la rampa ancha anterior y 1 es el corte físico. Medido, el borde cae 0.184
con 0.8 frente a 0.122 con 0, y sólo el 0.03% de los píxeles cruza el umbral de
curvatura: es un arco fino, no una rejilla.

El efecto conjunto sobre la estructura del techo, con la sonda en el encuadre de la
referencia (gradiente medio del semiplano superior):

| profundidad | antes | después |
| --- | --- | --- |
| 1.5 m | 0.00147 | 0.00871 |
| 3 m | 0.00141 | 0.01482 |
| 8 m | 0.00105 | 0.00689 |
| 20 m | 0.00030 | 0.00115 |

El contraste sube un 39% a 1.5 m y un 26% a 3 m. Coste medido a 2560×1440: **+0.04 ms**.

El campo lejano pasa de 12 a **48 m** de extensión mínima. El techo se apagaba al 80%
del campo, o sea a unos 17 m, y eso dejaba una costura recta a media pantalla. Con el
detalle fuera del caché su resolución ya no decide el detalle, sólo la precisión de la
altura con la que se marcha el rayo, así que puede cubrir mucho más lejos con los
mismos téxeles. El nivel cercano sube de 3 a 9 m por el mismo motivo.

Si faltan los mapas se conserva la normal analítica, sin inclinación artificial. La
normal de salida usa filtrado cúbico para que la caché no dibuje sus celdas en el
borde del cielo. La dirección del rayo reflejado y la atenuación del Sky rasterizado
siguen usando la normal geométrica: reflejar con la normal detallada se midió y no
cambia nada (0.00144 frente a 0.00143), porque la rampa de color por profundidad es
demasiado lenta para que el desvío del rayo reflejado se note.

`Underwater.underside_refraction` vale ahora **4.5**: multiplica por tres la
perturbación de las ondulaciones respecto a 1.5. La proyección general alcanza su
intensidad completa en 1.5; por encima solo aumenta la deformación del cielo y las
nubes, conservando los pesos de color y el degradado de distancia. Antes el control
se saturaba en 1.5 y el resto de su rango no tenía efecto. Cero lo desactiva y el
inspector permite ajustarlo hasta 8. No añade lecturas de textura ni pases.

No reconstruir esa normal restando alturas de téxeles vecinos: en un planeta de
30 km las alturas radiales pierden milímetros de precisión. Dividir esa diferencia
por unos centímetros amplifica el error y dibuja una cuadrícula cerca de la cámara,
incluso con agua plana y sin texturas. Guardar la normal ya calculada evita ese
problema sin evaluar más olas ni añadir despachos o pases de pantalla completa.

La dirección visual se contrasta con la superficie de
[Safe Shallows de Subnautica](https://mrwallpaper.com/images/hd/safe-shallows-subnautica-skbrfzkcppcqunpb.jpg)
y la [captura del bosque de algas publicada por Panic Button](https://panicbuttongames.com/wp-content/uploads/2019/09/Subnautica_02_InContent_800x500.png).
En esas referencias, la superficie alterna zonas oscuras y luz, y el agua distante
pierde contraste. La proyección anterior dejaba pasar casi todo el cielo salvo en
ángulos extremos. `surface_reflection_strength` (1.0) mezcla la respuesta Schlick
con una transición de interfaz rugosa, evaluada sobre la normal óptica filtrada:
`T = mix(0.04, 1, smoothstep(0.40, 0.88, cos_local))`. El cenit conserva su transmisión,
las ondulaciones cambian las aperturas de luz y la cola de transmisión evita un
cono recortado. La mezcla completa sigue fundiéndose con la distancia real.
La paleta del volumen pasa a `245661` / `0f303f` / `030c16`, con mayor absorción y
la exposición del cielo ajustada a 0.95. Se elimina la compresión de luminancia
anterior a la absorción: la radiancia conserva su rango HDR hasta el mapeo tonal
del renderer, evitando igualar los claros luminosos con el agua reflejada.
Esto no incorpora reflejos de terreno u objetos:
la radiancia reflejada sigue siendo la aproximación direccional del medio.

### Aspecto del medio

La niebla ya no converge a una paleta azul elegida según la distancia del rayo.
Se separan absorción y dispersión: `sigma_t = absorption * absorption_scale +
scattering_coefficients`. La transmitancia es `exp(-sigma_t * distancia)`.
Tres muestras del trayecto integran la luz dispersada con pesos Beer–Lambert;
la iluminación de cada muestra se atenúa también desde la superficie hasta su
profundidad real. La dispersión se anula al desaparecer las partículas o la
longitud de agua. De noche disminuye la fuente de luz.

Los controles de `Underwater` son:

- `absorption_scale` (0.4): cuánto absorbe el agua respecto a los coeficientes
  heredados del material. Conserva más contraste y color en el primer plano.
- `surface_projection_distance` (18 m): alcance de la proyección del cielo sobre
  el techo; a esa distancia queda el 37 % antes de la extinción del medio.
  No cambia el plano de flotación ni el tratamiento de objetos sumergidos.
- `scattering_coefficients` (0.015, 0.022, 0.020): partículas suspendidas;
  determina turbidez y extinción adicional, de forma separada de la absorción.
- `fog_density`: escala ambos coeficientes del medio.
- `fog_color`, `deep_fog_color`, `abyss_fog_color`: color de la luz dispersada
  según profundidad real. Los valores de partida son azul verdoso oscuro,
  azul profundo y casi negro; `PlanetLoader` propaga la misma paleta.
- `surface_reflection_strength` (1.0): peso de la interfaz rugosa; cero conserva
  la refracción y usa únicamente el Fresnel geométrico de Schlick.
- `surface_ripple_scale` (1.0), `surface_ripple_strength` (4.0) y
  `surface_window_sharpness` (0.8): tamaño, fuerza y definición del borde de la
  ventana. Son los tres mandos del aspecto del techo.
- `surface_exposure` (0.95) y `surface_saturation` (0.65): respuesta del cielo
  transmitido, con compresión suave de altas luces para evitar el azul quemado.
  No se aplican al color de objetos que están dentro del agua.

## Haces de luz: la fuente es la superficie

Los haces usan los mismos coeficientes que el medio y su energía escala con la
dispersión y la longitud atravesada, sin halo aditivo constante. Si falta la textura
de cáusticas no se inventa una blanca que ilumine toda la pantalla.

Estaban bien construidos —el modo de depuración 8 los aísla y convergen donde deben—
pero no se veían, por tres cosas medidas con la sonda:

1. **El número de muestras estaba capado a 6** dentro del shader, mientras
   `scenes/maps/sun.tscn` pedía 24. El ajuste no hacía nada. Tope ahora en 32.
2. **`godray_pattern_scale` valía 0.005 en esa escena** (0.01 por defecto): el patrón se
   repetía cada 200 m, o sea una sola celda de 33 m llenando el encuadre. Medido, era el
   peor punto de la curva de contraste (46%). A 0.15 sube a 62% y el haz tiene forma.
3. **Un factor `0.12` arbitrario** los dejaba en un 3% de la luz que dispersa el medio.
   Fuera; `godray_intensity` queda recalibrada, y **1.0 equivale a 8.3 de las de antes**.

Y lo que pedía el encargo: el patrón ya no flota por su cuenta. `godray_surface_focus`
(4) consulta el mismo caché que dibuja la ventana de Snell en el punto por donde entró
la luz, y atenúa según lo encarada al sol que esté esa faceta. Con la longitud de onda
del oleaje, eso convierte las celdas redondas del patrón en cuchillas paralelas a las
crestas. Está normalizado contra el mar EN CALMA: una faceta tan encarada como lo estaría
un mar plano vale 1 y solo las que se apartan oscurecen. Sin esa referencia, subir el
enfoque apagaba los haces enteros en vez de tallarlos, porque `pow()` de un coseno menor
que uno solo sabe bajar (energía 0.0068 sin normalizar frente a 0.0119 con ella).

### El parpadeo del techo NO son los haces

Queja repetida: "los godrays parpadean". Medido, **con los haces apagados el parpadeo es
MAYOR** (desviación pico 0.204 frente a 0.186). No estaban en el sitio correcto: el parpadeo
vive en el borde de la ventana de Snell y sólo se veía mirando arriba, que es donde también
se miran los haces.

El instrumento que lo resolvió es un **mapa de desviación típica temporal por píxel**, guardado
como imagen. Con `surface_ripple_strength` a 0 el mapa son bandas anchas y suaves —la ventana
barriendo con el oleaje, que es correcto—; con la ondulación puesta es moteado de píxel. La
FORMA lo dijo en un vistazo después de que cuatro métricas escalares no dijeran nada.

La causa es del propio trabajo de la ventana: un corte crítico estrecho (`half_width` 0.064 en
coseno) más ondulación fina por píxel hace que cada píxel conmute en binario entre cielo y
reflejo. Un interfaz rugoso de verdad no tiene un ángulo crítico nítido, así que el corte se
ensancha ahora con la inclinación que la ondulación puede imprimir, un tercio del tope de
pendiente:

| coeficiente | contraste | estructura | moteado |
| --- | --- | --- | --- |
| 0 | 0.190 | 0.0149 | 0.00533 |
| **0.3** | **0.146** | **0.0134** | **0.00270** |
| 1.0 (tope entero) | 0.076 | — | — |

La mitad de moteado por un 10% de estructura. Con el tope entero el corte se borra y la
ventana desaparece. El mando para bajarlo más es `surface_ripple_strength`.

**Lo que NO funcionó:** estimar la rugosidad por Toksvig, o sea el acortamiento de la normal
al promediar el mip. Con estos mapas (bumps suaves) la media apenas se acorta y la señal es
casi cero. No repetirlo.

### El enfoque ata los haces a la VELOCIDAD de la ola, y por eso queda a 0

Un haz sólo parpadea cuando algo se desliza contra otra cosa a distinta velocidad. Con
`godray_surface_focus` encendido, las cuchillas las dibujaba la ola (~10 m/s a 60 m de
longitud) y el patrón de la textura se movía a la suya: ese deslizamiento relativo ES el
parpadeo. Subir la deriva a 10-20 m/s lo quitaba —porque iguala la velocidad de la ola— pero
entonces todo viaja a velocidad de ola.

La salida: **las cuchillas no las tiene que dibujar la ola**. A `godray_pattern_scale` 0.15
(celdas de ~1.1 m) la textura sola ya da haces nítidos, y entonces `godray_pattern_speed` es
libre. Por eso el valor de serie del enfoque es **0**. El mando sigue ahí: sube el contraste
un 10% y ancla los haces a las crestas, a cambio de fijar su velocidad a la del oleaje.

Cuando se usa, la modulación lleva suelo (`mix(0.35, 1.0, pow(...))`): sin él `pow()` apagaba
cada haz entero al pasar la ola, con un 35% de profundidad de modulación frente al 14% con
suelo. Ojo al medir esto con `debug_scale` alto: a 25 la imagen satura y la profundidad sale
falseada a un 6%.

### Las muestras van a paso fijo, no a fracción de la distancia

Quedaba un modulador que no respondía a NINGÚN ajuste del patrón: las 24 muestras se
colocaban como fracción de `distance`, que sale del choque del rayo con la superficie
ondulada. Al pasar la ola, `exit_t` se movía un 20% y las muestras se deslizaban todas a la
vez, así que el haz cambiaba de brillo sin que cambiase la luz. Ahora el paso es fijo en
metros (`godray_max_distance / godray_samples`), las posiciones son absolutas sobre el rayo y
sólo entra o sale la última, con peso fraccionario para que tampoco salte. Medido: de 1.10 a
0.80 ciclos/s con la deriva a 0.25.



`pow(aligned, focus)` llevaba la faceta a cero cada vez que la ola pasaba por su punto de
entrada, así que cada haz se encendía y se apagaba **entero**. Ahora la modulación tiene
suelo: `mix(0.35, 1.0, pow(...))`. La ola atenúa el haz, no lo apaga.

Medido contando cuántas veces por segundo un píxel cruza su propio brillo medio, y con qué
profundidad (con `debug_scale` bajo: a 25 la imagen satura y la profundidad sale falseada a
un 6%):

| config | ciclos/s | profundidad |
| --- | --- | --- |
| enfoque 24, sin suelo | 1.23 | **35%** |
| escala 0.06 (celda 2.8 m) | 0.89 | 15% |
| **de serie: escala 0.15, deriva 1, enfoque 4, con suelo** | 1.18 | **14%** |

El ritmo apenas cambia; lo que baja 2.5 veces es la profundidad, y es lo que separa "respira"
de "parpadea". Bajar el ritmo con celdas más grandes (escala 0.06) sí funciona, pero deshace
los haces en un borrón: a ese tamaño una sola celda llena el encuadre. Lo mismo con
`godray_sharpness` por debajo de 6.

### Los haces usan EL MISMO campo que las cáusticas del fondo

Idea del usuario, y es la correcta: las cáusticas del suelo se mueven bien, así que los haces
deben seguirlas. Ahora comparten campo — mismo triplanar en espacio planeta, misma
`caustics_scale` y el mismo scroll — así que un haz cae sobre su mancha del suelo y, sobre
todo, hereda su movimiento.

Lo que había era otra cosa: **dos capas multiplicadas** sobre un plano perpendicular a la luz,
con escala y velocidad propias. Un haz sólo existe donde las dos coinciden, así que cualquier
diferencia de velocidad entre ellas aparece y desaparece **sin desplazarse**. Ése era el
parpadeo, y por eso ningún ajuste de `godray_pattern_speed` lo arreglaba: cambiaba la
velocidad de una capa, no la diferencia.

Los dos mandos siguen, ahora como multiplicadores:

- `godray_pattern_scale` (0.3) multiplica escala **y** scroll a la vez, así que cambia el
  tamaño de celda sin tocar la velocidad en metros por segundo.
- `godray_pattern_speed` (1.0) es un sesgo sobre la velocidad de las cáusticas; 1.0 es
  exactamente su mismo movimiento.

### Mover la cámara acelera los haces, y eso es parallax correcto

El campo está anclado al mundo, así que nadando lo atraviesas. Medido: **un metro de cámara
mueve el patrón lo que 2.8 s de deriva**, o sea unas ocho veces más rápido a velocidad de
nado (3 m/s) que su deriva propia (0.2 m/s). No es un fallo — es lo que tiene que pasar con
un campo anclado al mundo — pero se percibe como que los haces se aceleran al moverte.

`godray_camera_damping` (0.5) los ancla parcialmente a la cámara. Es un truco artístico
declarado como tal, no una corrección:

| amortiguado | 0.1 m de cámara equivale a |
| --- | --- |
| 0.0 (físicamente correcto) | 0.28 s de deriva |
| 0.5 | ~0.15 s |
| 1.0 | 0.01 s, pegados a la vista |

Sólo toca el movimiento: el aspecto en un fotograma quieto es idéntico en los cuatro casos
(energía, contraste y estructura no cambian ni un dígito).

**Lo que NO funcionó:** difuminar el haz con la distancia recorrida (mip por `light_path`),
con la idea de que lo nítido quedase pegado a la superficie y el fondo del tubo fuese suave.
La razón cámara/tiempo se quedó plana en 8.0 / 8.1 / 7.7 con coeficientes 0.2 / 0.6 / 1.5:
difuminar no cambia CUÁNTO se desplaza el patrón. Retirado.

### Los haces tienen que VIAJAR, no pulsar

La coordenada del patrón salía del punto donde el rayo de luz corta la **esfera media**, que
es fijo para cada píxel, y la textura corría a `godray_pattern_speed` en unidades de textura:
con los valores en uso, milímetros por segundo. O sea, el haz se quedaba clavado en pantalla
y lo único que cambiaba era su brillo, según la ola pasaba por su punto de entrada. Eso se ve
como un parpadeo antinatural, no como haces que se mueven.

Medido buscando el corrimiento (dx,dy) que mejor alinea dos fotogramas: el mejor era el (0,0)
con un **0% de mejora**, o sea cambio en el sitio. Ojo con esta medida, que solo vale para
descartar: los haces convergen en un punto de fuga, así que su movimiento en pantalla es
radial y ninguna traslación uniforme puede encajarlo. Sirve para probar que NO se mueven,
no para medir cuánto.

Ahora el patrón se advecta con el oleaje: `godray_pattern_speed` son **metros por segundo**
(4 de serie) en la dirección del viento, y las dos capas de la textura derivan en sentidos
opuestos, así que al viajar además se deshacen. Si aun así parpadea, `godray_surface_focus`
a 0 deja solo el patrón viajero.

**El enfoque manda en la VELOCIDAD, no solo en el contraste.** Los haces heredan la del
oleaje, y una ola de 60 m viaja a unos 10 m/s: con enfoque 24 barrían la pantalla 16 veces
más rápido que sin enfoque, y eso se lee como que van a saltos aunque el movimiento sea
perfectamente continuo (medido: la diferencia a dos fotogramas es exactamente el doble que
a uno, razón 2.00, o sea desplazamiento limpio y no parpadeo). Y el exponente alto casi no
compra contraste:

| enfoque | contraste | velocidad/fotograma | energía |
| --- | --- | --- | --- |
| 0 | 49.8% | 0.00052 | 0.063 |
| 4 | 47.0% | 0.00196 | 0.052 |
| 8 | 48.3% | 0.00375 | 0.044 |
| 12 | 51.7% | 0.00546 | 0.039 |
| 24 | 61.9% | 0.00819 | 0.031 |

De 0 a 12 el contraste es plano y la velocidad crece lineal. Por eso el valor de serie es
**4**: conserva el anclaje a la superficie (casi cuatro veces más movimiento de ola que sin
enfoque, así que los haces se ven vivir sobre ella), deja los haces más brillantes que con
24 y barre cuatro veces más despacio.

| encuadre | pico | contraste |
| --- | --- | --- |
| 6 m, 40° | 0.083 | 55% |
| 12 m, 55° | 0.148 | 62% |
| 20 m, 65° | 0.181 | 68% |

**Coste sin medir.** El banco (`tests/water/benchmark_underwater.gd`) no ataba la textura
de cáusticas, así que el bloque de haces estaba capado y nunca entró en ninguna medición
histórica. Puesta la textura y `sun_direction`, sigue sin dispararse: encendido y apagado
dan el mismo tiempo y los fotogramas difieren en 0.00001. La sonda sí los dibuja con esa
misma configuración, así que el coste de los 24 pasos es **desconocido, no cero**. Está
anotado en el propio banco. Las cáusticas de geometría usan proyección triplanar con tres
consultas sobre la posición real del receptor en coordenadas del planeta. Sus
ejes no dependen de la cámara. El patrón modula el color del material, requiere
profundidad de geometría y luz diurna, y conserva su animación temporal.

`caustics_depth_fade` vale **0.18**. El 0.7 anterior apaga el patrón en 1.4 m de
longitud característica: medido sobre un receptor gris, la ganancia era de +0.65 %
a 3 m, +0.05 % a 8 m y exactamente 0 a 16 m, es decir, invisible en todo el rango
en el que se bucea. Con 0.18 son +7.4 %, +3.0 % y +0.67 %, con picos muy superiores
en los filamentos. La superficie usa 0.22 en su propia fórmula.

`caustics_intensity`, `caustics_depth_fade` y `caustics_near_fade` son ahora exports
de `Underwater` y de `PlanetLoader`, y ya **no** se copian del material del agua: allí
`caustics_intensity` se suma al fondo y aquí multiplica el color del receptor, así
que el mismo número no significa lo mismo. Del material se siguen heredando la
textura, la escala y la velocidad, que son el patrón y deben coincidir.
Los antiguos `distance_depth_*` y `sun_glow_*` quedan para compatibilidad del
tratamiento local de ventanas vistas desde compartimentos secos. Los cristales
vistos buceando reciben el medio del compositor una sola vez.

La refracción se aplica a atmósfera y nubes; no reconstruye geometría fuera de
pantalla ni refracta el cielo rasterizado previo (estrellas/disco solar). La
reflexión interna aproxima la radiancia del agua, sin reflejar geometría real.
El campo de altura filtra el detalle menor que un texel y vuelve gradualmente a
la esfera fuera de su alcance. Es una aproximación de tiempo real.

### Validación y regeneración

El adaptador del espectro y el layout de parámetros se generan desde los
includes compartidos. Tras editarlos o cambiar declaraciones en
`underwater.gdshader`:

```powershell
python tools/water/build_underwater_shared.py
python tools/water/build_underwater_shared.py --check
python tools/water/test_underwater_compositor.py --godot C:/godot46/godot.windows.editor.x86_64.exe
python tools/water/test_underwater_compositor.py --godot C:/godot46/godot.windows.editor.x86_64.exe --benchmark
```

La prueba crea un proyecto temporal sin terreno ni autoloads del juego. Comprueba
cielo, absorción, contraste de primer plano, crecimiento gradual de dispersión,
textura ausente, cristal, nubes, normales, flotación, redimensionado y cabinas.
También comprueba refracción animada con cámara fija y cáusticas sobre el mismo
punto del mundo al trasladar y girar la cámara, aislando la absorción del trayecto.
También comprueba que los valores **por defecto** de las cáusticas iluminen un
receptor a ocho metros: las demás comprobaciones usan valores elegidos para hacer
observable el mecanismo, y con ellos el efecto pasaba estando apagado en el juego.
Los PNG quedan en el directorio de usuario de Godot `Underwater GPU Regression`.
La proyección continua se comprueba también más allá del antiguo cono crítico y
con un barrido de distancia a 4/12/25/40 m, aislando la extinción del medio.
Otra regresión compara una superficie lejana con la misma vista sin intersección
dentro del presupuesto: ambas convergen al mismo color con y sin geometría detrás.
Tras la mezcla completa, el benchmark aislado a 1440p dio 1.49 ms mirando arriba
y 0.80 ms al horizonte, sin pases ni texturas adicionales.
La prueba de detalle comprueba además que animar las normales de un mar plano
deforma un cielo variable, pero deja estable un fondo uniforme: no debe dibujar
parches de opacidad o color. Con la separación de normales, el benchmark aislado
a 1440p dio 1.56 ms mirando arriba y 0.83 ms al horizonte.

La regresión de precisión usa agua plana a 20 cm y 2 m de profundidad, en una
posición oblicua sobre un planeta de radio 29950 m. Los saltos locales del canal
de reflexión (modo 6) pasan de 0.1216 / 0.0314 a 0.0078 / 0.0078 al conservar
la normal analítica; el límite de la prueba es 0.02. Las 32 comprobaciones pasan.
Con este cambio, la mediana del fotograma aislado a 1440p con detalle es 1.52 ms
mirando arriba y 0.82 ms al horizonte; no es una medición de FPS del juego completo.

Tres comprobaciones adicionales cubren el control de refracción: cero anula el
movimiento óptico, el nuevo valor por defecto supera el doble de la deformación
anterior y subir hasta 8 sigue aumentándola. Se mide la dirección de salida (modo
7), sin que un cambio de brillo pueda satisfacer la prueba. Pasan 35 comprobaciones.

La respuesta oblicua añade dos comprobaciones: la transmisión cenital se conserva
y la lateral disminuye sin llegar a un corte opaco. El barrido 4/12/25/40 m mide
ahora transmisión directamente (modo 6), porque con el aspecto más oscuro la
radiancia distante puede caer por debajo del umbral de salida temprana de atmósfera.
Pasan 37 comprobaciones. Medianas aisladas a 1440p: 1.51 ms arriba y 0.80 ms al
horizonte, con los dos mapas de detalle; no son FPS del juego completo.

La prueba de cielo uniforme ahora aísla la refracción desactivando la reflexión
por facetas. Al activarla, un cielo uniforme y un medio acuático de radiancia
distinta deben variar su mezcla con la inclinación de las ondulaciones: una nueva
prueba comprueba ese comportamiento. Pasan 38 comprobaciones con el perfil de
ondas amplias. Medianas aisladas a 1440p: 1.47 ms arriba y 0.78 ms al horizonte.

Con los dos campos y los mapas de detalle, a 2560×1440 la proyección continua dio
1.46 ms mirando arriba y 0.91 ms al horizonte, frente a 1.01 y 0.48 ms con el cono
de transmisión anterior. El incremento de unos 0.45 ms corresponde a resolver
atmósfera en más píxeles; no se han añadido pases ni texturas. Son medianas de
fotograma de la escena aislada, no tiempos medidos en el juego completo.

Modos de depuración de `Underwater.debug_mode`: 1 clasificación de píxel, 2 columna
de agua, 3 normal del techo, 4 búsqueda de salida, 5 ganancia de cáusticas (escalada
por `debug_scale`), 6 mezcla de superficie (rojo reflejo, verde cielo
transmitido, azul sin corte), 7 elevación de salida del rayo. El 5 y el 7 son los que
distinguen «el efecto está mal cableado» de «el efecto está bien y vale casi cero».

**Los píxeles secos se pintan de magenta** en cualquier modo de depuración. `uw_trace`
sale en `if (!w.wet) return w;` mucho antes del bloque de depuración, así que sin esa
marca un modo de depuración que no cambia nada es ambiguo: puede significar «el efecto
no hace nada» o «la cámara no está en el agua», que son dos problemas en dos ficheros
distintos. Si al activar un modo la zona en duda sale magenta, no la dibuja este
compositor sino `water_shader.gdshader` (el agua vista desde fuera), y ningún parámetro
del nodo `Underwater` la va a tocar. Es el primer corte a hacer, antes de mirar nada más.

Comparación en RTX 4080 SUPER, Vulkan, 2560×1440, 24 fotogramas de calentamiento
y 90 muestras por vista: la versión descartada de tres pases adicionales tardó
11.73 ms mirando arriba y 8.94 ms al horizonte; la versión integrada con el nuevo
medio dio 0.87 ms y 0.39 ms respectivamente. Son medianas del fotograma de esa
escena aislada, no tiempos del juego completo ni una promesa de FPS. La escena
vacía favorece el descarte de atmósfera cuando el agua no deja ver aire.
El benchmark incluye además vistas `water_detail` con los dos mapas de normales
procedurales del océano para medir el coste de esa ruta frente a `water`.
Con detalle y filtrado cúbico, la medición dio 0.92 ms mirando arriba y 0.42 ms
al horizonte, en la misma escena aislada a 2560×1440. Marchar el rayo reflejado en vez
de la forma cerrada añade unos **0.05 ms**: 0.93 ms mirando arriba y 0.44 ms al horizonte.

Reiniciar la escena al evaluar cambios en los valores por defecto exportados:
Godot puede conservar los valores de las instancias durante la recarga de scripts.

El núcleo de paquetes mezclados y el material anterior se han sustituido.
`water_shader.gdshader` orquesta tres módulos independientes:

- `ocean_spectrum.gdshaderinc`: doce modos coherentes de mar de fondo, mar cruzado
  y oleaje de viento, con longitudes inconmensurables y dispersión gravitatoria.
- `ocean_foam.gdshaderinc`: nacimiento en crestas comprimidas, espuma residual,
  contacto con obstáculos y estelas de barcos.
- `ocean_optics.gdshaderinc`: reconstrucción de profundidad, refracción y SSR.

`ocean_spectrum.gd` replica en CPU el desplazamiento, sus derivadas y la velocidad
orbital. `gerstner_waves.gdshaderinc` se conserva como adaptador de las interfaces
del planeta: exposición al temporal, campo costero, LOD y consultas inversas.
La flotación y el corte submarino utilizan este mismo espectro. Se mantienen las
conexiones del quadtree, los compartimentos secos, el clima y las estelas.

## Geometría

Las olas ya no se promedian entre ocho grupos vecinos. Los modos comparten una
fase continua en coordenadas del planeta. El arrastre horizontal estrecha la
cresta y su presupuesto de contracción está acotado para evitar pliegues. Un
perfil con segundo y tercer armónico produce crestas elevadas y senos anchos.
Las normales derivan de esa geometría, incluida la curvatura de la esfera.

Controles de forma: `wave_amplitude`, `wave_base_length`, `wave_steepness`,
`wave_speed`, `wave_direction`, `wave_pole` y `spectrum_spread`.
`wave_speed=1` usa `omega=sqrt(9.81*k)`; la familia costera mantiene su velocidad
independiente. La amplitud es una escala de los modos, no una altura máxima.
El radio actual es 29950 m; el material tiene amplitud base 2.5 m y longitud 60 m.
El clima produce A=1/L=30 en calma y A=11.5/L=132 en temporal. El temporal
usa pendiente 0.94, velocidad 1.5 y cantidad de espuma 8.4. Acortar la longitud
anterior de 300 m aumenta el relieve de las crestas sin depender de franjas
adicionales de espuma. La iluminación del evento baja a sol 0.35 y ambiente 0.65;
el controlador aplica estos factores según la cobertura local de nubes.

La familia costera usa amplitud 1.1 m, longitud 32 m y pendiente 0.3. En temporal
resultan 2.64 m, 38.4 m y 0.42, antes de la atenuación local y el límite de altura.
`shore_shoal_max=1.35` permite crecer al entrar en poca profundidad.
`shore_handover=0.45` entrega antes el control al campo costero y
`shore_chop=0.28` reduce las olas pequeñas cruzadas. Son ajustes de escala y
mezcla: la familia costera sigue sin simular una rompiente que vuelque sobre sí misma.

## Espuma

La señal de nacimiento procede de la contracción tangencial del espectro,
evaluada por píxel y normalizada por su energía local. Así el umbral no depende
del presupuesto absoluto de contracción ni de la orientación del viento sobre
la esfera. Una puerta de actividad basada en pendiente impide que esa
normalización genere espuma en ondas insignificantes o con amplitud cero.
El campo costero añade su señal geométrica sin alterar el desplazamiento.

Se consultan seis instantes del mismo punto material durante `foam_lifetime`
(5 segundos por defecto). La deposición reciente forma la cresta y la suma
ponderada del historial deja restos que se abren y disuelven. Es un historial
analítico finito, no una simulación de fluido ni una textura con memoria.

`foam_crest_threshold` mide compresión normalizada (por defecto 0.55 en el shader).
El material conserva el ajuste del usuario: umbral 0.1 y suavidad 0.1.
Los valores del antiguo cálculo de compresión absoluta no son equivalentes.
`foam_crest_softness` controla la transición. `foam_crest_amount` recibe
el multiplicador climático y aumenta la masa depositada mediante una curva
logarítmica: cambia cobertura y densidad, no solo la opacidad de una máscara
ya activada. `foam_trail_strength` regula los restos (0.38 en el material) y
`foam_scale` (1.2) el tamaño del patrón.

`foam_edge_breakup` (0.65 en el material) varía el umbral local a tres escalas
para romper el contorno de activación de la cresta. Esto permite entrantes y
prolongaciones sin recortar toda la textura contra la misma línea de compresión.
La densidad de la textura también erosiona ese contorno; el umbral queda siempre
por encima de cero. El valor 0 desactiva esta irregularidad adicional. El ruido
se filtra con la huella del píxel y evoluciona lentamente en coordenadas materiales.

La altura del mismo perfil de doce ondas que desplaza la superficie refuerza
la deposición en la zona superior. `foam_crest_width` (0.65) regula la amplitud
de esa zona. El refuerzo modifica únicamente la densidad de la textura existente:
no rellena sus huecos ni dibuja una segunda franja opaca. Se ha retirado la máscara
de pendiente cero, que convertía las ondulaciones pequeñas en cintas sinuosas.
El borde y los restos reciben menos deposición para dar contraste a la cresta.

El patrón usa `textures/planet/water/foam_density.png`, una máscara de espuma
generada con ImageGen; se ha retirado por completo la evaluación Voronoi.
Dos escalas de la textura aportan acumulaciones grandes, bordes deshilachados y
detalle interno. Los niveles de gris controlan la densidad sin convertirla en
contornos binarios. La espuma vieja pierde antes sus zonas menos densas.

La proyección triplanar mezcla parches interiores con giros y desplazamientos
distintos; no necesita que los bordes de la imagen coincidan. Las transiciones
entre parches tienen derivada continua. La textura se importa sin pérdida, como
datos lineales y con mipmaps. Se usan gradientes explícitos para que los giros
no creen saltos de filtrado ([textureGrad en Godot](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shader_functions.html)).
Costa y estelas comparten el patrón. La óptica del agua y la geometría no cambian.
El origen y el prompt completo figuran en `foam_density_asset.md`.

## Apariencia y diagnóstico

La refracción aplica Snell con IOR 1.333 y valida la profundidad y la altura de
la muestra seleccionada. El desplazamiento de pantalla se limita con
`refraction_max_offset`; la absorción usa la longitud del segmento dentro del
agua, no la diferencia de profundidad de cámara. El reflejo usa
Fresnel dieléctrico, cielo procedural y SSR cuando hay geometría visible válida.
La espuma recibe iluminación difusa; el brillo directo usa GGX. Las normales
finas tienen pendiente acotada para no ocultar el volumen de las olas.

El inspector de `OceanSystem` expone `water_debug_mode`: 0 aspecto final,
1 normales geométricas, 2 cobertura de espuma, 3 compresión, 4 altura y
5 peso del refuerzo de la cresta (antes de aplicar textura y cantidad).
La vista 2 permite distinguir espuma real de brillos blancos. Los controles
obsoletos del material se han retirado, incluidos `packet_size`, `packet_spread`,
`surface_alpha`, `refraction_alpha_floor` y el segundo brillo solar.
