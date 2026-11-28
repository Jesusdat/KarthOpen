# Karth Open

Karth en mundo abierto 3D: tercera persona, combate de acción y exploración libre,
con el lore, los datos y las herramientas de Cenizas de Karth. Godot 4.7.2.

## Abrir y probar
1. Abre la carpeta en Godot 4.7.2 (la primera vez importa los recursos; tarda un poco).
2. F5 abre `mundo/prueba.tscn`.

| Control | Acción |
|---|---|
| WASD / stick izquierdo | Moverse (relativo a la cámara) |
| Ratón / stick derecho | Girar la cámara |
| Shift | Correr (gasta estamina) |
| Espacio | Saltar |
| Ctrl o C | Esquivar (sin dirección = paso atrás) |
| Clic izquierdo | Ataque ligero (hasta 3 en combo) |
| Mantener clic izquierdo | Ataque pesado (aturde más) |
| Clic derecho | Bloquear (cobra estamina; si se acaba, te rompen la guardia) |
| Q / clic de la rueda | Fijar al enemigo (otra vez = soltar) |
| Rueda | Acercar / alejar la cámara |
| Esc | Soltar el ratón (clic para volver) |

## Dónde está cada cosa
- `datos/movimiento.cfg` — velocidades, salto, esquiva, estamina y cámara.
- `datos/terreno.cfg` — semilla, tamaño y relieve del terreno de prueba; props por bioma.
- `datos/controles.cfg` — teclas y botones.
- `datos/combate.cfg` — daño, tiempos y costos de los ataques, bloqueo, fijar y la "sensación" (pausa al golpear, sacudida).
- `datos/criaturas.cfg` — criaturas en 3D (vida, aguante, velocidad, visión) y sus ataques.
- `mundo/terreno/` — terreno propio por bloques (malla + colisión) y su shader.
- `mundo/dispersor_props.gd` — reparte árboles y rocas de PropForge sobre el terreno.
- `jugador/` — jugador en tercera persona y cámara orbital.
- `combate/golpe.gd` — cómo se reparten los golpes (lo usan jugador y criaturas).
- `criaturas/` — criatura con IA, guarida que las repone y el modelo de piezas de Karth (`modelos/*.json`).
- `nucleo/efectos.gd` — sonidos, efectos, números de daño, pausa al golpear.
- `ui/` — HUD (vida y estamina), barra del enemigo y aviso de "Has caído".

En el editor, los nodos **Terreno** y **Props** tienen la casilla *Regenerar* para
rehacerlos después de cambiar `datos/terreno.cfg`.

## Plan
1. ✅ Base: terreno, jugador en tercera persona, cámara, estamina, HUD.
2. ✅ Combate cuerpo a cuerpo (ligero, pesado, bloqueo, fijar objetivo) contra Nidales 3D.
3. Clases, habilidades y objetos desde los .cfg de Karth; mochila con UIBuilder.
4. Editor de terreno propio (subir, bajar, aplanar, pintar, colocar props) y la primera región.
5. Misiones, NPC, elección de bando, Sincronía con la IA, guardado.
