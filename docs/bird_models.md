# Modelos de aves

Las cinco especies usan cuerpos continuos de secciones interpoladas, normales
suaves y colores de vértice. Cabeza, cuello y pecho forman una sola superficie;
los patrones del plumaje siguen esa superficie. El estilo mantiene volúmenes
redondeados y colores simplificados, con ojos discretos y picos propios de cada
especie. Las patas del bosque conservan el apoyo a ±0,045 m que usa el hábitat.

Las alas tienen siete plumas secundarias, ocho primarias y dos filas de siete
coberteras. Las plumas son curvas, con grosor, extremos redondeados y variación
de tono entre borde y centro. Se solapan para formar el ala; las colas tienen
ocho plumas. El plegado orienta el ala hacia atrás, junto al flanco, y reduce la
apertura del abanico. El vuelo conserva las frecuencias propias de cada especie.

## Especies y referencias

Guías consultadas para distinguir proporciones y patrones; los recursos del
juego son geometría original, sin fotografías ni texturas externas incorporadas.

| Especie | Diseño | Referencia |
| --- | --- | --- |
| Gorrión | Tonos cálidos, mejillas claras, babero oscuro, coronilla gris y barras claras en las alas. | [RSPB: House Sparrow](https://www.rspb.org.uk/birds-and-wildlife/house-sparrow) |
| Petirrojo | Pecho más lleno, cara y pecho naranjas, vientre crema y cabeza y dorso oliva. | [RSPB: Robin](https://www.rspb.org.uk/birds-and-wildlife/robin) |
| Herrerillo | Cuerpo más estrecho, pecho amarillo, coronilla azul, mejillas claras, antifaz y collar oscuros. | [RSPB: Blue Tit](https://www.rspb.org.uk/birds-and-wildlife/blue-tit) |
| Gaviota | Cuerpo alargado, cuello diferenciado, pico amarillo con marca rojiza y primarias oscuras con puntas claras. | [RSPB: Herring Gull](https://www.rspb.org.uk/birds-and-wildlife/herring-gull) |
| Pato | Cabeza verde, collar claro, pecho castaño, pico aplanado, franjas azules entre barras claras y cola curvada. | [RSPB: Mallard](https://www.rspb.org.uk/birds-and-wildlife/mallard) |

## Recursos y coste

`SimpleBirdModel` precarga diez recursos en `data/fauna/meshes/birds/`: cuerpo y
ala derecha de cada especie. El ala izquierda reutiliza la misma malla reflejada.
Se mantienen tres `MeshInstance3D` y un material compartido por ave; cada malla
tiene una sola superficie. No se añaden cuerpos físicos ni colisiones por pluma.

El modelo completo usa aproximadamente 25 mil triángulos en primer plano.
Los cuerpos tienen 5–6 LOD y las alas cuatro, con unos cientos de triángulos en
los niveles más lejanos. La selección de LOD la realiza Godot. La generación y
la simplificación se ejecutan únicamente con el horneador:

```sh
godot --headless --path . --script res://tools/fauna/bake_bird_meshes.gd
```

El parámetro opcional `-- --review` exporta también la geometría a `/tmp` para
inspección. Los colores se almacenan en espacio lineal, igual que en los modelos
anteriores, para el material compartido que utiliza colores de vértice.

## Galería y comprobaciones

Abrir `tests/fauna/bird_model_gallery.tscn`:

- **1–5:** seleccionar especie; **0:** ver todas a escala relativa.
- **Espacio:** alternar reposo y vuelo; **P:** pausar el aleteo.
- **H:** acercar la cabeza; **F:** vista de perfil.
- Arrastrar con el botón izquierdo gira la cámara; la rueda ajusta el zoom.

Las escenas anteriores `birds_preview.tscn` y `water_birds_preview.tscn`
conservan sus capturas y la revisión sobre una rama real.

```sh
godot --headless --path . --script res://tests/fauna/test_bird_models.gd
```

Las comprobaciones específicas validan recursos compartidos, geometría y
normales finitas, presupuesto de triángulos y LOD, simetría del aleteo, plegado
por encima del suelo y escala compatible con el apoyo de las patas.
