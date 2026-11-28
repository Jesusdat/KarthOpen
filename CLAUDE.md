# Karth Open — reglas del proyecto

RPG de mundo abierto 3D en tercera persona (estilo Skyrim / Elden Ring / Crimson Desert)
con el lore de Cenizas de Karth. Un jugador, sin red. Godot 4.7.2, Forward+, Jolt.

## Relación con Cenizas de Karth
- Es un proyecto **aparte**. El repo `Jesusdat/cenizas-de-karth` se usa solo como base y
  **nunca se modifica** desde aquí: se lee y se copia lo que sirva.
- Copiado de Karth: `kit/` (UIBuilder, SFX, FX), `datos/` (tablas .cfg), `addons/editor_datos`,
  `nucleo/datos_juego.gd`, `fonts/`, `sounds/`, `music/`, `icons/`, `modelos/terreno/`
  (props de PropForge), `herramientas/blender/` (PropForge) y `modelos/colono.glb`.
- Lo de Karth que era por casillas (golpes, formas, habilidades, talentos, mapa de zonas)
  se rehace para tiempo real en 3D; los datos se reutilizan.

## Cómo se trabaja
- Claude hace los cambios directo en el repo (commit y push); el usuario prueba en Godot.
- Todo en español: nombres de archivos, variables, comentarios y textos.
- Números de juego en `datos/*.cfg` (se leen con `DatosCfg`), no en el código.
  Los textos en .cfg van entre comillas (`bioma="llanura"`).
- Interfaz con UIBuilder (JSON en `ui/`), enlazada a `UIBuilder.estado`.
- Controles en `datos/controles.cfg` (autoload `Controles`), no en el Mapa de entrada.
- Capas de física: 1 mundo, 2 jugador, 3 criaturas. El combate usa `Golpe.aplicar_en_area`
  y `recibir_golpe(golpe) -> String` (ver `combate/golpe.gd`).
- Sonidos y efectos con el autoload `Efectos` (SfxBanco + FxBanco del kit, datos de Karth).
- Terreno propio (`mundo/terreno/terreno_karth.gd`), sin Terrain3D. El editor de terreno
  (pinceles, pintura, props) se construirá sobre él.

## Pruebas
- `godot --headless res://pruebas/prueba_paso1.tscn` (movimiento) y
  `godot --headless res://pruebas/prueba_paso2.tscn` (combate) — deben terminar en "TODO BIEN".
- Antes de subir: `godot --headless --import` sin errores y las pruebas en verde.
