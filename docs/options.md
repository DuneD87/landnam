# Opciones del juego

Pantalla de opciones (`scripts/ui/menu/options_screen.gd`) con cinco pestañas: Pantalla, Gráficos,
Audio, Controles y Juego (el idioma, ver [localization.md](localization.md); cuánta sangre y si se
cercenan miembros, ver [combat.md](combat.md); y el tamaño de la barra rápida, ver [ui.md](ui.md)). Se abre con el botón *Options* del menú principal,
que en partida hace de menú de pausa (Escape). Los cambios se ven al momento; *Aceptar* o Escape los guardan en
`user://settings.cfg` y *Cancelar* vuelve a como estaba todo al abrir. Un cambio de ventana pide
confirmación y se deshace solo a los 10 s. Si cambia el tamaño de la vista, la pantalla se rehace a su nueva escala.

## Dónde vive cada cosa

- `scripts/autoload/settings.gd` (autoload `Settings`, clase `SettingsManager`): valores, presets,
  guardado y aplicación. Los valores son estáticos: el planeta los lee al cargar con
  `SettingsManager.value()` sin depender del autoload, y en el editor devuelven los de por defecto.
- Lo que se aplica en caliente (escala de render, AA, sombras, entorno, atmósfera, partículas, fauna,
  audio, teclas, ratón) lo hace el propio autoload. Luces y `WorldEnvironment` los recoge al entrar
  en el árbol (`node_added`) y guarda sus valores de escena en metadatos para escalar sobre ellos.
- Lo que solo vale al cargar el planeta está en `RESTART_KEYS` y la pantalla avisa de que hace falta
  reiniciar: detalle del terreno (`secondary_lod_distance`), normalmaps y material del terreno, densidad y
  distancia de la hierba, bandas de bosque lejano y sombras de vegetación.

## Resolución

En ventana se elige el tamaño de la ventana (`display/resolution`). A pantalla completa, la
resolución (`display/fullscreen_resolution`): la nativa o una de las alturas de
`OptionsScreen.FULLSCREEN_HEIGHTS` que caben por debajo de la del monitor, con el ancho de la
proporción del monitor (en uno 4K: 1280×720, 1600×900, 1920×1080, 2560×1440 y 3200×1800). Cada modo
recuerda la suya.

Godot 4 no cambia el modo de vídeo del monitor, ni con la pantalla completa exclusiva. Por debajo de
la nativa, `SettingsManager._apply_render_size` pone la ventana raíz en `CONTENT_SCALE_MODE_VIEWPORT`
con ese `content_scale_size`: todo, también la interfaz, se dibuja a esa resolución y se estira a la
pantalla, como lo estiraría el monitor. Con `CONTENT_SCALE_ASPECT_EXPAND`, si la proporción no coincide
(una resolución guardada con otro monitor) se alarga por un lado en vez de deformarse. La escala de
render de Gráficos se aplica encima y solo al 3D.

Así, la vista (`get_visible_rect()`) mide lo que la resolución y no lo que la ventana. La interfaz ya
se escala por la altura de la vista. El giro de cámara usa `screen_relative`: `relative` viene en
píxeles de la vista y a menos resolución la cámara giraría más despacio. Lo que arrastra la interfaz
(mapa, menú radial) sigue con `relative`, que va en sus mismas unidades.

## V-Sync y tope de fotogramas

Por defecto, V-Sync activado y tope de 120 fps.

En Linux con Wayland y NVIDIA, el juego **incrustado en el editor** (la pestaña Juego) se congela
de vez en cuando, y el editor con él. Los dos van por XWayland, con la ventana del juego dentro de
la del editor, y XWayland deja de devolver las imágenes de la cadena de presentación:

- El juego se queda en `fence_wait` de Vulkan, con la GPU parada y sin errores en el log.
- El editor se queda en la espera de sincronización (`drm_syncobj`), sin responder ni a la pausa,
  y vuelve en cuanto se mata el juego.

V-Sync y el tope lo hacen menos frecuente, pero no lo evitan. Lo evita lanzar el juego en su propia
ventana: Configuración del editor → Ejecutar → Colocación de ventana → Modo de incrustación del juego
= Desactivado. El cambio se aplica al reiniciar el editor.

## Presets

Alto es el valor por defecto. La calidad de la atmósfera usa Media en Alto y resolución completa
en Ultra; ver [atmosphere_performance.md](atmosphere_performance.md). Como referencia anterior a
la reducción del aire y los rayos, medido con
`tests/lighting/lighting_capture.tscn --perf`, a mediodía y con el tiempo despejado:

| Vista  | Alto (GPU) | Bajo (GPU) |
|--------|-----------:|-----------:|
| forest | 5,6 ms     | 2,6 ms     |
| shore  | 4,6 ms     | 2,4 ms     |

La calidad de **Material del terreno** es independiente de la geometría y las normales lejanas:
baja desactiva detalle cercano, parallax y antitiling; media conserva antitiling y desactiva detalle
y parallax; alta conserva los valores del planeta. Los presets Bajo/Medio/Alto/Ultra usan,
respectivamente, material Bajo/Medio/Alto/Alto. Se aplica antes del primer mallado y requiere reiniciar.

La **Calidad de las sombras** fija el filtro del sol y, un escalón del motor por debajo, el de las
luces locales (`POSITIONAL_SHADOW_FILTER`): en Alto, el sol va en *Soft High* y las antorchas en
*Soft Medium*. Lo que cuesta de una luz local no es dibujar su mapa de sombra sino leerlo en cada
píxel que alcanza, y en una base con varias antorchas cada píxel lo paga por cada una. Con cuatro
antorchas de pared en PCSS (`light_size` 1) y 12 m de alcance, el pase opaco subía a 7,7 ms de los
16 ms de GPU de la partida (4K al 65 %, MSAA 2x). Por eso la antorcha de pared
(`torch_placed.tscn`) no usa PCSS (`light_size` 0, `shadow_blur` 1,5), alcanza 8 m y su sombra se
apaga entre 8 y 12 m de la cámara (`distance_fade_shadow` + `distance_fade_length`). La de mano
conserva la suya: es una sola luz.

## Añadir un ajuste

1. Clave en `PRESETS` (si depende de la calidad, con sus cuatro valores) o en `DEFAULTS`.
2. Si se aplica en caliente, un caso en `SettingsManager._apply()`; si se lee al cargar, añadir la
   clave a `RESTART_KEYS` y leerla con `SettingsManager.value()` o un accesor.
3. Una fila en la página correspondiente de `OptionsScreen` (`_choice_control`, `_toggle_control` o
   `_slider_control`). Su nombre, su explicación y sus opciones son claves de
   `localization/translations.csv` (`OPT_*`, ver [localization.md](localization.md)).
4. Comprobarlo en `tests/ui/options_screen_preview.tscn -- --capture`.

## Lo que no se puede tocar

- **`lod_distance` del terreno**: la vegetación calcula con él los relevos entre bandas del
  instancer. El ajuste de detalle escala `secondary_lod_distance`, que solo alcanza a los LOD
  lejanos.
- **Subdivisión de la malla del océano**: con menos de 32 la malla se hunde bajo la costa entre
  vértice y vértice y el mar desaparece (con 16 no se ve nada; con 24 se retira de la orilla). Por
  eso no hay opción de calidad del agua.
- `anisotropic_filtering_level` solo se lee al arrancar el motor: no está en el menú.
