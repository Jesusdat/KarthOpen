# Modelos en Blender para Karth

Los personajes de la vista 3D (y los sprites que hornea SpriteBaker) pueden salir de un archivo de
Blender. El juego lee el `.glb` que exportas a la carpeta `modelos/`.

Esta carpeta tiene `.gdignore`: Godot no la mira, así que aquí puedes guardar tus `.blend` sin problema.

| Archivo | Para qué |
|---|---|
| `plantilla_colono.blend` | El colono actual, ya con todo lo que el juego espera. Ábrelo, guárdalo con otro nombre y trabaja encima. Hecho con Blender 5.3: ábrelo con esa versión o una más nueva. |
| `json_a_blend.py` | Convierte un modelo de piezas (`.json`) en un `.blend` como la plantilla. Sirve para sacar una plantilla del Nidal o de cualquier otro. |
| `colono_piezas.json` | El colono de piezas del que salió la plantilla. |
| `volumen_automatico.py` | La «trampa» del volumen: sombras en los huecos y degradado, y exporta. Ver abajo. |

## El ciclo de trabajo

1. Abre tu `.blend` (empieza con una copia de `plantilla_colono.blend`).
2. Cambia la forma, pinta, ajusta las animaciones.
3. **File → Export → glTF 2.0 (.glb)** a `modelos/<nombre>.glb` (por ejemplo `modelos/colono.glb`).
   En las opciones: *Include → Custom Properties* activado, *Animation → Animation mode: NLA Tracks*.
4. Vuelve a Godot (reimporta solo), corre el juego (ya arranca en 3D). Para los sprites 2D, abre `hornear_sprites.bat`.

## La trampa del volumen automático

`volumen_automatico.py` hace que un modelo simple se vea con volumen sin pintar texturas: oscurece
los huecos (axilas, entre las piernas, bajo el casco) y agrega un degradado de los pies a la cabeza.
Lo guarda en cada vértice (atributo de color `volumen`) y exporta el `.glb`; el juego lo multiplica
sobre los colores del modelo en todos los estilos y al hornear sprites.

1. Abre tu `.blend` (guardado) → pestaña **Scripting** → **Open** → `volumen_automatico.py`.
2. Revisa `EXPORTAR_A` al principio del script (por defecto `modelos/colono.glb`) y presiona **Run Script**.
3. Si quieres más o menos efecto, cambia `FUERZA_HUECOS`, `DEGRADADO` o `ALCANCE` y vuelve a correrlo.
   Para retocar a mano: modo **Vertex Paint** sobre el atributo `volumen`.

Córrelo cada vez que cambies la forma del modelo (las animaciones no le afectan).

## Lo que el juego espera del modelo

- **Tamaño y orientación:** tamaño real (1 casilla = 1.9 m; un humano de ~1.8 m ocupa una casilla).
  De frente en la vista *Front* (tecla 1 del teclado numérico) y con los pies en Z = 0.
- **Acciones** (los nombres importan):
  - `quieto` y `caminar`: ciclos. En `caminar`, el último cuadro debe ser igual al primero.
  - `golpe` y `apuntar`: cuenta **la pose del último cuadro** (el juego mezcla solo hacia ella).
    `golpe` es el ataque básico; `apuntar` es disparar o usar una habilidad.
  - Cada acción va en su propia pista del editor NLA (botón *Push Down* / *Stash* en el Action Editor).
- **Equipo:** cada pieza de equipo es un objeto aparte con la propiedad personalizada
  `grupo` = `armadura`, `casco`, `botas` o `arma` (también vale que el nombre empiece así: `casco_visor`).
  El juego las muestra solo si el jugador tiene algo puesto en esa ranura.
- **Color del jugador:** los materiales cuyo nombre empieza con `armadura` (`armadura`, `armadura_oscura`…)
  toman el color que eligió el jugador. Píntalos en grises: blanco = color pleno, gris = más oscuro.
- **Texturas:** si pintas una textura, se ve pixelada (sin suavizar) y a plena luz sale con el color exacto
  que pintaste. Usa los colores de `paleta_karth.gpl`.
- **Huesos:** los nombres son libres; lo que el juego usa son las acciones. La plantilla trae
  `cuerpo`, `torso`, `cabeza`, `brazo_i/d`, `antebrazo_i/d`, `pierna_i/d`, `espinilla_i/d`.

## Dos formas de armar el cuerpo

- **Partes pegadas a huesos** (como la plantilla): cada parte es un objeto con *Parent → Bone*.
  Es lo más fácil; no hay que pintar pesos.
- **Una sola malla que se dobla** (*Armature Deform* con pesos): también funciona. El contorno de esas
  mallas sale un poco menos parejo en las aristas duras.

## Qué clase usa qué modelo

- Jugadores: la tabla `CLASES` en `vista3d/modelo_3d.gd` (hoy `soldado` → `colono`).
- Monstruos: el que tenga `sprite="<nombre>_bake"` usa `modelos/<nombre>.glb`; si no existe, `modelos/<nombre>.json`.

## Sacar una plantilla de otro modelo

```
blender --background --python json_a_blend.py -- ../../modelos/nidal.json plantilla_nidal.blend
```
