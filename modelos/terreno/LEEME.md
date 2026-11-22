# Piezas 3D del terreno

Prueba del 2026-11-20 (`vista3d/piezas_terreno.gd`). La roca de las zonas con
**Bioma 3D** (campo de la zona en Godot, por ejemplo `ceniza` en Campos marchitos)
se dibuja con piezas que encajan con sus vecinas en lugar de cubos. **F7** cambia
entre piezas y cubos para comparar. La lógica no cambia: sigue siendo la cuadrícula.

## Piezas de roca

Van en `modelos/terreno/<bioma>/roca_<pieza>.glb`, con variantes `roca_<pieza>_2.glb`,
`roca_<pieza>_3.glb`... (cada casilla usa una según su lugar). Si falta un archivo, el juego
usa la pieza provisional (hecha en código).

PropForge las genera si la receta del bioma trae `"piezas"`, con el generador `terreno`
(roca natural) o `muros` (muros construidos):

    "piezas": {"generador": "terreno", "color": "ceniza", "variantes": 3, "escala": 1.0}
    "piezas": {"generador": "muros", "tipo": "labrada", "color": "colonia", "variantes": 3}

    blender --background --python propforge.py -- --karth <carpeta de Karth> --bioma colonia --solo-piezas

`terreno`: tipos `roca`, `lomas` y `picos`; un color por bioma (`ceniza`, `llanura`, `grietas`,
`colonia`, `mina`, `cumbre`, `progenie`, `antiguos`, `ruinas`, `gris`).
`muros`: tipos `labrada` (sillares con juntas y remate) y `empalizada` (troncos con punta);
colores `colonia`, `ruinas`, `arenisca`, `madera` y `quemada`. Su malla se llama
`propforge-cuartos-fijo-roca_<pieza>`: el juego no les cambia el alto de casilla a casilla, para
que las hiladas sigan de una pieza a otra. Colonia usa muros de piedra labrada. Campos, Llanuras y Grietas
ya las tienen. Si haces tus propias piezas en Blender, borra las de PropForge de ese bioma
(con sus `_2`, `_3`...) para que no se mezclen.

| Pieza | Cuándo sale | Cómo va sin girar |
| --- | --- | --- |
| `suelta` | roca sin vecinas | peñasco aislado |
| `punta` | 1 vecina | se une al norte |
| `recta` | 2 vecinas opuestas | va de norte a sur |
| `esquina` | 2 vecinas juntas | une norte y este |
| `te` | 3 vecinas | une norte, este y sur (abierta al oeste) |
| `relleno` | 4 vecinas | roca maciza |

Reglas para modelarlas en Blender:

- Cada pieza ocupa **1×1** (una casilla = 1 metro en Blender), con el **origen en el centro de la base** (y = 0 en el piso).
- **Norte = +Y en Blender** (que al exportar a glTF queda como -Z en Godot). Modela cada pieza "sin girar" como dice la tabla; el juego la gira.
- Los lados que se unen con otra roca deben llegar a la orilla de la casilla para que no queden huecos; los lados al aire pueden meterse hacia adentro.
- Alto de referencia: alrededor de 1 (los personajes miden cerca de 1). El juego varía el alto ±15 % por casilla.
- Exporta como **glTF Binary (.glb)** con un solo objeto (una malla). Se usa el color y la textura de su material.

## Objetos

Pieza **ObjetoKarth** de la escena de la zona (herramienta **Objeto** del editor de mapas), con su campo `modelo`. Van en
`modelos/terreno/<bioma>/obj_<modelo>.glb` o, para todos los biomas,
`modelos/terreno/objetos/<modelo>.glb`.

Provisionales que ya existen: `arbol_muerto`, `cerca`, `ruina`, `roca_grande`,
`carreta` y `craneo`. Cualquier otro nombre sale como un cubo morado hasta que
exista su .glb.

Todos tapan el paso (su casilla cuenta como roca) menos los de
`PiezasTerreno.NO_BLOQUEAN` (hoy solo `craneo`) y **los que empiezan con `deco_`**
(matorrales, hongos, piedritas: adorno que se puede pisar). Mismas reglas de origen y
tamaño que las piezas; el juego los gira al azar en cuartos de vuelta.

**Variantes**: `obj_<modelo>.glb`, `obj_<modelo>_2.glb`, `obj_<modelo>_3.glb`... (hasta 9).
Cada casilla usa siempre la misma variante (sale de su posición), así que un campo con
diez `arbol_muerto` no muestra diez árboles iguales.

## Modelos de PropForge

PropForge (el generador procedural del kit, con Blender) hace modelos para un bioma a
partir de la receta `modelos/terreno/<bioma>/propforge.json`:

    blender --background --python propforge.py -- --karth <carpeta de Karth> --bioma ceniza

Escribe aquí mismo los `obj_<modelo>[_N].glb` y los `hierba_N.glb`. Cada entrada de la
receta dice qué generador, tipo y color usar, cuántas variantes, la `escala` (metros de
PropForge → casillas) y, si hace falta, `params` para cambiar la forma (por ejemplo una
cerca de un solo tramo que mida una casilla). Tus modelos propios mandan: si pones tu
`obj_arbol_muerto.glb`, borra los `_2`, `_3`... de PropForge o quedarán mezclados.

Lo que el juego hace distinto con ellos (su malla lleva `propforge-` en el nombre):

- El color va en los vértices (con variación y sombra en la base) y el material en blanco.
- El alfa del color dice cuánto los mueve el **viento** (`vista3d/objeto.gdshader`):
  el tronco firme, las ramas y hojas se mecen.
- `propforge-libre-...` (árboles, rocas, matorrales) giran a cualquier ángulo y varían
  ±10 % de tamaño; `propforge-cuartos-...` (cercas, muros) solo en cuartos de vuelta para
  que queden alineados.

## Adornos de la capa de decoración

Los adornos que cada zona reparte sola (campo **Props** de la zona: piedras, hongo, cristal,
huesos) antes salían en la vista 3D como cubitos hechos del dibujo 2D. Ahora, si hay modelo,
se dibujan con él (`Vista3D.PROPS_A_MODELO`):

| Adorno | Modelo |
| --- | --- |
| `piedras` | `deco_piedras` |
| `hongo` | `deco_hongos` |
| `cristal` | `deco_cristales` |
| `huesos` | `deco_huesos` |

Se busca primero en la carpeta del bioma de la zona y luego en `modelos/terreno/objetos/`
(juego general para todas las zonas, receta `objetos/propforge.json`). Si no hay ninguno,
sigue en cubitos. `ceniza`, `grieta`, `runa` y `brasa` se quedan como están (van pegados al piso).

## Hierba

`modelos/terreno/<bioma>/hierba_1.glb`, `hierba_2.glb`... más `decoracion.json`:

    {"hierba": {"densidad": 0.9, "distancia": 26.0, "escala": [0.75, 1.25]}}

`densidad` = matas por casilla de suelo; `distancia` = casillas a las que desaparece.
Solo se ve (no cambia la lógica), siempre en el mismo lugar, en bloques de 16×16 casillas
que se ocultan solos. Se dibuja con `vista3d/hierba.gdshader` (por los dos lados, con viento).

## Relieve del piso

El piso de las zonas con bioma tiene lomas suaves y sube junto a la roca (talud). Solo se
ve: la lógica sigue siendo la cuadrícula plana. Se configura en el mismo `decoracion.json`:

    "relieve": {"lomas": 0.35, "tamano": 7.0, "borde": 0.2, "terrazas": 0.0,
                "bajo": [0.7, 0.68, 0.7], "alto": [1.3, 1.27, 1.22]}

| Campo | Qué hace |
| --- | --- |
| `lomas` | alto máximo de las lomas, en casillas (los personajes miden cerca de 1) |
| `tamano` | ancho típico de una loma, en casillas |
| `borde` | cuánto sube el piso pegado a la roca (varía ±40 % por la orilla) |
| `terrazas` | si es mayor que 0, las lomas suben en escalones de ese alto |
| `bajo` | tinte del piso en lo más bajo, `[r, g, b]` (1 = sin cambio; por ejemplo tierra oscura) |
| `alto` | tinte en lo más alto de las lomas (por ejemplo ceniza clara) |

Hoy: Campos (`ceniza`) dunas de ceniza, Llanuras (`llanura`) lomas anchas, Grietas
(`grietas`) terrazas. El piso nunca baja de 0; entre zonas y contra las zonas sin bioma
se mezcla por esquina de casilla, así que no quedan escalones. Como la luz va en bandas,
el relieve se marca en el color: cada bioma tiñe lo bajo y lo alto con `bajo` y `alto`
(mezclados igual que el alto entre zonas) y las pendientes se oscurecen un poco
(`TINTE_PENDIENTE` en `vista3d/vista_3d.gd`).

En la orilla entre dos zonas el piso de una entra en el de la otra en cuadritos sueltos
(como un tramado de pixel art), la mitad pegado a la orilla y cada vez menos hacia adentro
(`ancho_mezcla` en `vista3d/tiles.gdshader`). Personajes, hierba, adornos, rocas, objetos y marcas se apoyan
en el relieve. **F7** (piezas/cubos) también lo apaga para comparar.

## Cuando tapan al jugador

Las piezas de roca propias (.glb) y los objetos que tapan el paso (rocas grandes,
árboles, ruinas, cercas...) se traman igual que los muros cuando quedan entre la cámara y
el jugador, o se aplastan si el modo de muros es "aplastar". Los adornos (`deco_`) no.
Lo hace `vista3d/objeto.gdshader` con `recortable` y los globales `recorte_*`.

## Decorar una zona

El botón **Decorar** del panel **Zona 3D** (editor de mapas) reparte objetos del bioma con la
receta `"decorar"` de `decoracion.json`:

    "decorar": {"radio_grupo": 2.5, "objetos": [
        {"modelo": "columna", "por_100": 1.0, "grupos": true},
        {"modelo": "deco_piedras", "por_100": 1.4}
    ]}

`por_100` = cuántos por cada 100 casillas de suelo; `grupos` = en manchones de radio
`radio_grupo`. Ver `mapa/LEEME.md`.

## Puntos de oficio

Los puntos de minería, recolección y excavación (`oficios.gd`) se dibujan con su propio
modelo en vez del adorno de la casilla, desde la carpeta general `objetos/`:

| Oficio | Activo | Gastado |
|---|---|---|
| veta (colonos) | `obj_oficio_veta[_N].glb`: roca con mineral que brilla | `..._minada.glb` |
| nido (Progenie) | `obj_oficio_nido[_N].glb`: hongos gordos | `..._cosechado.glb` |
| ruina (Antiguos) | `obj_oficio_ruina[_N].glb`: monolito con runas | `..._excavado.glb` |

El gastado es la misma variante (misma semilla) y se queda en su casilla las 3 horas que
el punto tarda en volver en otro lugar; luego la casilla vuelve a ser adorno normal. El
servidor manda las casillas gastadas con 0 golpes en el mismo paquete de los puntos.
Cada golpe sacude el modelo y suelta chispas del color del oficio (lo ven todos los que
estén cerca: los golpes ya llegan en el paquete). Las superficies con emisión del .glb
(mineral, runas) brillan con `objeto.gdshader` (`emision`).

Si falta el modelo de un oficio, el punto se sigue viendo como el adorno de siempre.
