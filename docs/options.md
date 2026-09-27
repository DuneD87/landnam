# Opciones del juego

Pantalla de opciones (`scripts/ui/menu/options_screen.gd`) con cuatro pestañas: Pantalla, Gráficos,
Audio y Controles. Se abre con el botón *Options* del menú principal, que en partida hace de menú de
pausa (Escape). Los cambios se ven al momento; *Aceptar* o Escape los guardan en
`user://settings.cfg` y *Cancelar* vuelve a como estaba todo al abrir. Un cambio de ventana pide
confirmación y se deshace solo a los 10 s.

## Dónde vive cada cosa

- `scripts/autoload/settings.gd` (autoload `Settings`, clase `SettingsManager`): valores, presets,
  guardado y aplicación. Los valores son estáticos: el planeta los lee al cargar con
  `SettingsManager.value()` sin depender del autoload, y en el editor devuelven los de por defecto.
- Lo que se aplica en caliente (escala de render, AA, sombras, entorno, atmósfera, partículas, fauna,
  audio, teclas, ratón) lo hace el propio autoload. Luces y `WorldEnvironment` los recoge al entrar
  en el árbol (`node_added`) y guarda sus valores de escena en metadatos para escalar sobre ellos.
- Lo que solo vale al cargar el planeta está en `RESTART_KEYS` y la pantalla avisa de que hace falta
  reiniciar: detalle del terreno (`secondary_lod_distance`), normalmaps del terreno, densidad y
  distancia de la hierba, bandas de bosque lejano y sombras de vegetación.

## Presets

Alto es exactamente el juego antes de las opciones y es el valor por defecto. Medido con
`tests/lighting/lighting_capture.tscn --perf`, a mediodía y con el tiempo despejado:

| Vista  | Alto (GPU) | Bajo (GPU) |
|--------|-----------:|-----------:|
| forest | 5,6 ms     | 2,6 ms     |
| shore  | 4,6 ms     | 2,4 ms     |

## Añadir un ajuste

1. Clave en `PRESETS` (si depende de la calidad, con sus cuatro valores) o en `DEFAULTS`.
2. Si se aplica en caliente, un caso en `SettingsManager._apply()`; si se lee al cargar, añadir la
   clave a `RESTART_KEYS` y leerla con `SettingsManager.value()` o un accesor.
3. Una fila en la página correspondiente de `OptionsScreen` (`_choice_control`, `_toggle_control` o
   `_slider_control`).
4. Comprobarlo en `tests/ui/options_screen_preview.tscn -- --capture`.

## Lo que no se puede tocar

- **`lod_distance` del terreno**: la vegetación calcula con él los relevos entre bandas del
  instancer. El ajuste de detalle escala `secondary_lod_distance`, que solo alcanza a los LOD
  lejanos.
- **Subdivisión de la malla del océano**: con menos de 32 la malla se hunde bajo la costa entre
  vértice y vértice y el mar desaparece (con 16 no se ve nada; con 24 se retira de la orilla). Por
  eso no hay opción de calidad del agua.
- `anisotropic_filtering_level` solo se lee al arrancar el motor: no está en el menú.
