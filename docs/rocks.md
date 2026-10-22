# Rocas del planeta

Las rocas grandes, las piedras sueltas que se recogen, los afloramientos de mena y los bloques de
hielo (`scenes/planet/planet_items/rocks/*.tscn`) se generan con `ProceduralRock`
(`scripts/planet/procedural_rock.gd`) y, salvo el hielo, se pintan con
`shaders/planet_rock.gdshader`. Sustituyen a `Rock3D` del addon `Tree3D`, que era una icoesfera
estirada con bultos de ruido muy suaves: salía un óvalo, y con la mitad bajo tierra.

## Forma

`ProceduralRock` es un `Node3D` con la misma interfaz que tenía `Rock3D` (`get_rock_instance()`,
`material_rock`), así que `Planet._build_rock_packed_scene` la hornea igual en una escena con solo
la malla y su colisión convexa. La malla se hace al pedirla y la comparten las escenas con los mismos
parámetros; en el editor se rehace al tocar cualquier parámetro (`@tool`).

1. **Icoesfera** de `subdivisions` (2 = 162 vértices para las piedras sueltas, 4 = 2562 para las
   grandes), estirada por `size` (± `size_variance` con la semilla) y con bultos de ruido
   (`lump_amount`, `lump_frequency`).
2. **Cortes** (`facet_count`, `facet_depth`, `facet_variance`, `facet_upward`): planos repartidos
   alrededor que se comen una fracción de lo que la roca sobresale en su dirección. Lo que queda fuera
   se lleva al plano por su rayo desde el centro, así que salen caras planas y aristas sin pliegues y
   la roca sigue estrellada desde su centro, que es lo que supone `RockFracture`. Son lo que hace que
   se lea como roca.
3. **Estratos** (`strata_layers`, `strata_inset`, `strata_terrace`, `strata_tilt`): capas a lo alto
   que entran o salen un poco y se aplanan en repisas. El estrato de arriba se aplana entero.
4. **Grietas** (`crack_depth`, `crack_frequency`): surcos donde un ruido cruza el cero.
5. **Base**: la fracción `sink` de la altura queda bajo y = 0, porque el instancer planta la escena
   por su origen.

La malla lleva en `COLOR.r` la oclusión de las cavidades (cuánto se hunde cada vértice respecto a sus
vecinos) y en `COLOR.g` si la cara es de fuera, curtida. Genera sus LOD (`ImporterMesh.generate_lods`)
a partir de 3 subdivisiones. Hacer una roca grande cuesta ~22 ms y una piedra suelta ~2 ms, una vez
por juego de parámetros al cargar la vegetación.

| Escena | Forma | Material |
|---|---|---|
| `rock_04` | losa baja | `rock_stone` |
| `rock_05` | bloque en estratos | `rock_stone` |
| `rock_06` | bloque de aristas marcadas | `rock_stone` |
| `rock_07` | menhir inclinado | `rock_stone` |
| `small_rock_01` | piedra suelta, la que se recoge | `rock_pebble` |
| `outcrop_flint_*` | bolos de sílex | `outcrop_flint` |
| `outcrop_copper_*` | roca parda, una en estratos | `outcrop_copper` |
| `outcrop_obsidian_*` | muchas caras, cortes hondos | `outcrop_obsidian` |
| `ice_block_01` | bloque de caras planas | el suyo, `opaque_planet_material` |

## Material

Los materiales están en `data/resources/rocks/` y los comparten todas las escenas de un tipo.

- **Triplanar en los ejes de la roca y en metros** (`texture_scale`, repeticiones por metro, con la
  escala de la instancia). No estira como el UV esférico de antes y cada roca lleva su dibujo pegado.
- **Calibrado como el terreno.** Las rocas usan la textura de las laderas (`bumpy_worn_ground`) con
  su mismo factor de `slope_albedo` (× 0,55, tinte 1,05/1/0,92). Antes usaban `sandy_rocks1`, una
  grava clara sin calibrar (albedo lineal medio 0,39 frente a 0,20 de la ladera y ~0,07 de la
  hierba).
- **Sin translucencia, rim ni especular.** Las dos primeras eran del follaje y aclaraban la roca a
  contraluz y en el contorno. Con `SPECULAR > 0`, la cara al sol sale quemada a blanco (a los
  afloramientos de antes, con `specular` 0,4-0,75, les pasaba lo mismo); el `light()` planetario no
  calcula especular y el juego no tiene reflejos, así que no se pierde nada.
- **Un solo color por tipo de roca.** El sílex es la misma piedra que las rocas grandes, más oscura,
  más fría y con algo menos de musgo; el tono es lo que lo distingue. Probamos una textura propia con
  nódulos negros sobre blanco (se leía como piel de vaca) y otra con corteza clara y sílex oscuro en
  las caras de rotura: las dos chocaban con el resto.
- **Envejecido** (`macro_variation`, `macro_size`, `streak_strength`, `streak_size`): manchas grandes
  de brillo y tono, para que la roca no sea de un color parejo, y chorreones del agua oscureciendo
  las caras de lado.
- **Tierra al pie** (`base_color`, `base_height` en metros, `base_strength`) y **musgo** en lo que mira
  arriba (`moss_amount`, con la textura y el factor de la pradera, para que case con la hierba),
  solo en la cara curtida.
- **Nieve** del clima frío, como `opaque_planet_material` (`climate_snow_amount`).

Al picar una roca, `RockFracture` conserva el `COLOR` en los trozos y deja las caras del corte con
`CUT_COLOR`: limpias, sin tierra ni musgo. Cada trozo guarda en el meta `rock_offset` dónde estaba
dentro de la roca entera, y `RockFracture.mesh_instance` se lo pasa al shader (`instance uniform`),
así que la textura no salta al cambiar la roca por sus trozos.

## Revisión

- `tests/world/test_procedural_rocks.tscn` (headless): cada escena da su malla plantada por la base,
  estrellada y con `COLOR`; los trozos conservan el color, las caras del corte salen limpias y saben
  dónde estaban.
- `tests/world/rock_review.tscn` (con ventana): las rocas a su escala de juego sobre la pradera y la
  roca de ladera del terreno, a mediodía y con el sol bajo. `-- --capture=<carpeta>` saca las fotos y
  se cierra; `-- --old=<carpeta>` pone detrás, para comparar, escenas de otra carpeta con el mismo
  nombre (por ejemplo las de antes, sacadas de git).
