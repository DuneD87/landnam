# Motor: Godot 4.6 con Voxel Tools parcheado

El juego funciona con el Godot 4.6 de Voxel Tools 1.6 sin tocar, pero varios repartos de trabajo por
fotograma (colisión del terreno en trozos, retirada de vegetación, instancer sin descargas de la GPU) solo
existen en el módulo parcheado. Sin él, `PlanetLoader._apply_streaming_budgets` y `Planet._init` no
encuentran las propiedades y no tocan nada.

- Módulo: fork `git@github.com:DuneD87/godot_voxel.git`, rama `mejoras-landnam` (sobre `v1.6`).
  Qué lleva y por qué: `landnam/README.md` y `git log v1.6..mejoras-landnam`.
- Cambios en el propio Godot: parches en `landnam/patches/godot/` del fork (hoy, uno de Jolt).

## Compilar

Con el módulo clonado en `~/godot-build/godot_voxel`:

    ~/godot-build/godot_voxel/landnam/build.sh            # editor
    ~/godot-build/godot_voxel/landnam/build.sh template_release template_debug

Clona Godot 4.6-stable en `~/godot-build/godot` si no está, aplica los parches, enlaza el módulo y
compila. El editor sale en `~/godot-build/godot/bin/godot.linuxbsd.editor.x86_64`; la primera vez son
unos 15 min con 10 hilos, luego solo lo que cambie. Las plantillas de exportación hay que compilarlas
igual para que el juego exportado lleve los mismos cambios.
