# SFXForge

Sonidos de juego sintetizados desde recetas en JSON, sin muestras externas. Parte del kit.

- `sfx_forge.py`: lee las recetas y genera los `.wav` (varias variantes por sonido) y un `.cfg` con cómo se tocan en el juego.
- `sfx_banco.gd` (`SfxBanco`): lee ese `.cfg` en Godot y toca los eventos.
- `probador.tscn`: escena para escuchar todos los eventos (F6 en el editor).

```
pip install numpy scipy
python kit/sfx/sfx_forge.py herramientas/sonidos_karth.json            # todo
python kit/sfx/sfx_forge.py herramientas/sonidos_karth.json --solo monedas golpe_enjambre
python kit/sfx/sfx_forge.py herramientas/sonidos_karth.json --solo     # solo el .cfg
```

Cada sonido se genera igual cada vez (la semilla sale del nombre), así que regenerar no cambia lo que ya te gustaba. Para otra versión, pon `"semilla": 123` en la receta.

## Recetas

```json
{
  "ajustes": {"salida": "../sounds", "cfg": "../datos/sonidos.cfg", "ruta_res": "res://sounds/",
              "juego": {"bus": "Efectos"}},
  "plantillas": {"impacto_seco": { ... }},
  "sonidos": {
    "golpe_enjambre": {
      "hereda": "impacto_seco",
      "dur": 0.4, "variantes": 4, "azar": 0.08,
      "capas": [ {"tipo": "ruido", ...}, {"tipo": "burbujas", ...} ],
      "fx": {"distorsion": 0.2, "sala": {"tam": 0.4, "mezcla": 0.1}},
      "vol": 0.85,
      "juego": {"vol_db": -4, "tono": [0.95, 1.05], "voces": 6, "espera": 0.02, "alcance": 12}
    },
    "golpe": {"igual_a": "golpe_colonos"}
  }
}
```

- `hereda`: parte de una plantilla u otro sonido y cambia lo que escribas (las listas, como `capas`, se reemplazan completas).
- `igual_a`: alias, mismo audio que otro evento (puede tener su propio `juego`).
- `dur`: segundos de síntesis (la sala alarga la cola). `variantes`: cuántos `.wav`. `azar`: cuánto cambia cada variante (frecuencias, caídas).
- `vol`: pico del archivo (0–1). El volumen en el juego se ajusta en `juego.vol_db`.

### Capas

Todas aceptan `gan` (volumen relativo), `t0` (cuándo empieza, en segundos), `t0_azar` y `prob` (probabilidad de aparecer en cada variante).

| tipo | para qué | campos |
| --- | --- | --- |
| `ruido` | golpes, soplidos, siseos, rugidos | `color` (blanco, rosa, marron), `filtro`, `env` |
| `tono` | cuerpo grave, zumbidos, barridos | `f`, `f_fin`, `curva` (exp, lin), `onda` (seno, tri, sierra), `armonicos` [[razón, amp]], `vibrato` [hz, cents], `fm` {razon, indice, indice_fin}, `filtro`, `env` |
| `metal` | metal, monedas, campanas | `f`, `parciales` [[razón, amp]], `caida`, `caida_agudos` (cuánto más rápido caen los agudos), `batido`, `golpe` (chasquido inicial), `a` |
| `cristal` | cristal, resonancia | igual que `metal`, con parciales y caídas de cristal por defecto |
| `crujido` | quitina, hueso, grava, chispas | `densidad` (granos por segundo), `tam_grano`, `filtro`, `env` |
| `burbujas` | líquido, carne, ácido | `densidad`, `f` [min, max], `sube` (>1 sube, <1 baja), `dur_grano`, `env` |

- `filtro`: `{"tipo": "pb" | "pa" | "banda", "f": 800, "f_fin": 200, "q": 1.5}` (`f_fin` hace un barrido).
- `env`: `{"a": ataque, "mantener": s, "d": caída, "forma": "exp" | "lin", "trem": [hz, profundidad]}`.

### fx (sobre la mezcla)

`distorsion` (0–1), `sala` {`tam`, `mezcla`, `brillo`}, `eco` {`ret`, `fb`, `veces`}, `pasa_bajos` (12000 por defecto), `pasa_altos` (35), `al_reves`.

### juego (va al .cfg)

| campo | qué hace |
| --- | --- |
| `vol_db` | volumen en el juego |
| `tono` | [min, max] del cambio de tono al azar en cada toque |
| `voces` | cuántos pueden sonar a la vez; el siguiente corta al más viejo |
| `espera` | segundos mínimos entre dos toques del mismo evento |
| `alcance` | casillas a las que todavía se oye |
| `bus` | bus de audio |

## En Godot

```gdscript
var sfx := SfxBanco.new()
add_child(sfx)
sfx.cargar("res://datos/sonidos.cfg")
sfx.raiz_3d = mi_mundo_3d      # opcional: dónde se cuelgan los sonidos 3D
sfx.oido = mi_oido             # opcional: desde dónde se mide el alcance

sfx.tocar("monedas")
sfx.tocar_en_3d("golpe_enjambre", punto)
sfx.tocar_lejos("muerte_colonos", distancia_en_casillas)
```

Si un nombre no existe se le quita el último `_sufijo` y se prueba otra vez (`herido_fisura` → `herido`). Si tampoco es evento pero hay un archivo suelto (`carpeta_suelta`, por defecto `res://sounds/%s.wav`), suena ese.
