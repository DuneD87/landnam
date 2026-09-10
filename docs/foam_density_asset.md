# Máscara de espuma

Recurso: `textures/planet/water/foam_density.png`.
Creada con la herramienta integrada ImageGen el 10 de septiembre de 2026.
La salida recibida mide 1254 × 1254 píxeles y se copió sin editar a este proyecto.
Es una máscara generada, no una
fotografía capturada de espuma real. El shader usa su canal rojo como dato lineal.

## Prompt exacto

```text
Use case: photorealistic-natural. Asset type: production grayscale texture mask for ocean surface whitewater foam in a realistic Godot game. Generate one square 2048 by 2048 flat orthographic overhead texture, seamless tileable to all four edges. Pure monochrome. White/light gray is dense aerated sea foam; pure black is empty water (no water shading). Approximately 50 percent foam coverage, irregular clustered foam rafts of greatly varying size. Authentic photographic ocean foam breakup after a breaking wave: soft frothy dense masses opening into tiny specks, ragged eroded feathered edges, wispy disconnected streaks, finer milky particulate inside dense masses. Many scales of irregular voids and densities with no single hero feature. Larger voids should be tortuous dark channels between froth clusters, with small scattered holes; foam is a patchy mass with granular and shredded edges, NOT a network of thin lines surrounding equally sized cells. No large round bubbles, no Voronoi, no polygon cells, no spiderweb, no honeycomb, no cracked ice, no stylized outlines. Broad patches and empty regions distributed throughout the tile including all edges, no border or vignette. No horizon, no perspective, no crests/wave geometry, no lighting gradients, no shadows, no specular reflections, no sun, no blue or color, no text, no labels, no borders. The result must function directly as a linear grayscale density/coverage mask, not as a beauty photograph or normal map.
```

Aunque el prompt pide continuidad en los bordes, la implementación no depende
de ella: mezcla muestras del interior de la imagen con posiciones y giros variados.
