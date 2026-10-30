# Nivel y atributos

El personaje sube de nivel con lo que hace en el mundo (`Progression`, un nodo hijo del jugador).
Cada nivel da un punto que se reparte en la pantalla de personaje (**C**) entre seis atributos.
Todos los números están en `data/progression/balance.tres` (`ProgressionBalance`) y se pueden
cambiar desde el inspector sin tocar código.

## Experiencia

| Acción | XP | Dónde |
|---|---|---|
| Matar | la de la presa (ver abajo) | `HealthComponent._credit_kill`; los animales pequeños sin vida propia, en `AmbientAnimal.take_damage` |
| Talar un árbol | 15, de ×0,5 a ×2 según la madera que da (unos 12 es lo normal) | `TreeFelling._fell` |
| Romper una roca | 2 por piedra | `RockFragment.hit`, cuando suelta las piedras |
| Cavar | 1 por golpe | `PlayerController._on_voxel_mined` |
| Fabricar | 4 + 1,5 por ingrediente, por vez; la primera vez, el triple | `CraftingPanel._craft` → `Progression.reward_craft` |
| Despellejar | 10 (un ave, 4) | `SurvivalActions._on_butchered` |
| Pescar | 12 | `PlayerFishing._land_catch` |
| Construir | 1 por material gastado | `BuildingSystem` al cobrar un bloque; `SiteBuilder` por pieza puesta de un plano |
| Parar un golpe | 3 | `PlayerCombat._on_guard_parried` |

Fundir en el horno y cocinar en la hoguera no dan XP, a propósito: ni asar ni lo que se cuece junto
a ella en la ventana de fabricar (la tisana de milenrama).

Matar da `vida × 0,25 + armadura natural (las tres sumadas)`, ×1,6 si es una fiera que caza (la que
come carne: `feed_profile()`). Una cabra, unos 15; un lobo, 44; un oso, 133; un mamut, 263. Una
especie puede fijar la suya con `HealthComponent.xp_reward`. La muerte se le cuenta a quien hirió por
última vez si fue hace menos de 90 s (`HealthComponent.KILL_CREDIT_TIME`): vale también lo que muere
desangrado o de una flecha.

**Lo repetido rinde menos.** Cada motivo con límite (`repeat_cap`) rinde
`1 / (1 + reciente / límite)`, donde «reciente» es lo ganado por él que se va olvidando con una vida
media de 5 minutos. Talar 8 árboles seguidos (120 XP) deja el siguiente a la mitad. Así poner y
quitar bloques o fabricar en serie no sube de nivel. Matar, despellejar, pescar y recuperar la XP de
la bolsa no tienen límite.

| Motivo | Límite |
|---|---|
| Talar | 120 |
| Fabricar, construir | 80 |
| Picar piedra | 60 |
| Cavar | 20 |
| Parar | 15 |

Para quien la da: `Progression.reward(actor, motivo, unidades)` y `Progression.reward_kill(killer,
victim)` no hacen nada si `actor` no lleva `progression`, así que se pueden llamar desde cualquier
sistema sin mirar quién actúa.

## Niveles

Pasar del nivel *n* al siguiente pide `80 · n^1,5`: 80 al 2, 226 al 3, 894 al 6 y 2530 al 11. No hay
tope. Cada nivel da un punto. Al subir sale un aviso sobre la barra rápida y la barra de XP destella.

## Atributos

| Atributo | Por punto |
|---|---|
| **Vitalidad** | +5 de vida máxima (las partes del cuerpo crecen con ella: `BodyDamage.rescale`) |
| **Aguante** | +4 de aguante máximo y +2 % de recuperación |
| **Fuerza** | +3 % de daño cuerpo a cuerpo y con la lanza arrojada, de desgaste de guardia y de potencia al talar y picar |
| **Destreza** | +3 % de daño con arco y tirachinas, +2 % de rapidez al tensar y −3 % de aguante gastado con la cuerda tensa (hasta un 30 %) |
| **Dureza** | +0,5 de armadura natural contra tajo, contundente y perforante; +1 de guardia (lo que aguanta sin tambalearse, 24 de base); −2 % de sangrado (hasta la mitad) |
| **Temple** | −2 % de hambre y sed (hasta la mitad); la franja en que se está a gusto se ensancha 0,3 °C por cada lado |

Pasados 15 puntos, cada punto de un atributo rinde la mitad. La armadura natural de la dureza va por
la misma fórmula que la del equipo (`Armor.mitigate`) y la ficha la suma a la del equipo. El temple
no cambia los grados que se sienten: cambia a partir de cuántos se pasa frío o calor.

Lo aplica `Progression._apply` sobre lo que el jugador tiene en su escena (lo toma en `setup`): la
vida y el aguante máximos, la armadura natural del `HealthComponent`, `BodyDamage.bleed_scale` y
`SurvivalNeeds.upkeep_scale` / `hardiness`. `PlayerCombat` pide la fuerza, la destreza y la guardia
en cada golpe (`strength_mult`, `ranged_mult`, `draw_speed_mult`, `hold_drain_mult`, `poise_bonus`).
Lo que sube la vida o el aguante máximos también se suma a lo que se tiene en ese momento.

## En pantalla

- **Pantalla de personaje (C)**: arriba de la columna de atributos, el nivel, la XP y su barra, los
  puntos por repartir y los seis atributos con su **+**. Lo que se pone sale en verde (`3 → 4`) y no
  cuenta hasta **Confirmar**; **Deshacer** o cerrar la pantalla lo deja como estaba. Pasando el ratón
  por un atributo se ve lo que da. La columna se desplaza si no cabe.
- **Barra rápida**: bajo la barra, de engaste a engaste, una barra de bronce sólida (`XpStrip`) con
  la XP del nivel, en el sitio de la trenza que tenía antes la consola. Se aviva un momento al ganar
  XP y destella entera al subir de nivel.

## Morir

Al morir se pierde la XP del nivel en curso (`Progression.forfeit`), nunca niveles ni puntos. Se
queda en la bolsa de lo que se llevaba (`DeathLoot.xp`), que sale aunque no hubiera objetos. Al abrir
la bolsa (**E**) vuelve entera (`take_xp` → `recover`). Si se muere otra vez antes, la bolsa
anterior se pierde con su XP, como los objetos.

## Guardado

`"progression"` en los datos del jugador: nivel, XP, puntos, atributos y lo que ya se ha fabricado
alguna vez. Se carga antes de `PlayerCombat.on_restored`. Una partida anterior a esto empieza en el
nivel 1. La bolsa guarda su `"xp"`.

## Consola

| Comando | Qué hace |
|---|---|
| `xp` | Nivel, XP, puntos por repartir y atributos |
| `xp add <n>` | Da XP (sin límite de lo repetido) |
| `xp level <n>` | Fija el nivel, con los puntos que le tocan menos los ya puestos |
| `xp attr <nombre> <n>` | Fija un atributo sin gastar puntos: `vitality`, `endurance`, `strength`, `dexterity`, `toughness`, `fortitude` |
| `xp respec` | Devuelve todos los puntos para repartirlos otra vez |

`tests/player/test_progression.tscn` comprueba la curva, el límite de lo repetido, cada atributo, el
rendimiento pasados 15 puntos, la XP de matar (también desangrado) y de fabricar, la bolsa con XP y
el guardado:

```
godot --headless --path . res://tests/player/test_progression.tscn
```
