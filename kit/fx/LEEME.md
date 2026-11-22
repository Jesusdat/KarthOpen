# FXForge

Efectos visuales 3D definidos por datos (JSON), sin texturas ni escenas hechas a mano. Parte del kit.

- `fx_banco.gd` (`FxBanco`): lee el JSON y arma cada efecto con partículas, luces, anillos en el piso y destellos. También lanza proyectiles con cuerpo, cinta, estela y un efecto al llegar.
- `probador.tscn`: escena para ver los efectos (F6 en el editor). Al guardar el JSON se recarga sola.

## En Godot

```gdscript
var fx := FxBanco.new()
add_child(fx)
fx.raiz = mi_mundo_3d                 # donde se cuelgan los efectos
fx.cargar("res://datos/efectos.json")

fx.lanzar("golpe_enjambre", punto)
fx.lanzar("eco", punto, {"color": Color.CYAN})   # tiñe las capas con "tinte": true
fx.proyectil("disparo_colonos", desde, hasta)    # al llegar lanza su "impacto"
```

- Si un nombre no existe, se le quita el último `_sufijo` y se prueba otra vez (`golpe_fisura` → `golpe`).
- `max_vivos` (48 por defecto): si ya hay tantos efectos, el más viejo se borra.
- `densidad`: multiplica la cantidad de partículas (para calidad baja).
- `tam_particulas`: multiplica su tamaño.
- `apagado`: no arma nada (servidor sin pantalla).

## Formato

```json
{
  "plantillas": {
    "chispas_metal": {"tipo": "particulas", "forma": "chispa", "cantidad": 14, ...}
  },
  "efectos": {
    "golpe_colonos": {
      "altura": 0.5,
      "capas": [
        {"hereda": "chispas_metal", "cantidad": 20},
        {"tipo": "destello", "color": "#ffd28a", "tam": [0.55, 0.15], "dur": 0.08},
        {"tipo": "luz", "color": "#ffb347", "energia": 1.5, "alcance": 2.5, "dur": 0.15}
      ]
    },
    "herido_colonos": {"hereda": "golpe_colonos", "escala": 0.85},
    "golpe": {"igual_a": "golpe_colonos"}
  }
}
```

La escala es de una casilla = 1; un personaje mide como 1 de alto.

**Efecto:**

| campo | qué hace |
| --- | --- |
| `capas` | lista de capas |
| `altura` | qué tan arriba del piso sale |
| `escala` | lo agranda o achica todo |
| `hereda` | parte de otro efecto y cambia lo que escribas |
| `igual_a` | alias de otro efecto |
| `proyectil` | lo convierte en proyectil (ver abajo) |

Una capa con `"hereda": "<plantilla>"` parte de esa plantilla.

**Campos de toda capa:**

| campo | qué hace |
| --- | --- |
| `pos` | [x, y, z], desplazamiento dentro del efecto |
| `retraso` | segundos antes de empezar |
| `tinte` | `true` para que la tiña el color que le pase el juego |

### Capas

**`particulas`**

| campo | qué hace |
| --- | --- |
| `forma` | `mota` (punto de luz), `chispa` (estirada en su dirección), `gota` (líquido), `humo` (suave y opaco) o `esquirla` (prisma 3D que gira) |
| `cantidad`, `vida`, `vida_azar` | cuántas, cuántos segundos viven, cuánto varía la vida |
| `tam` | [al nacer, al morir]; `tam_medio` opcional; `tam_azar` |
| `color` | paradas de nacer a morir; al final se desvanece (`sin_fundido` lo evita; `fundido` dice desde cuándo) |
| `velocidad` | [min, max] |
| `direccion`, `dispersion` | hacia dónde salen y cuánto se abren (grados; 180 = a todos lados) |
| `gravedad` | negativa = caen |
| `sube` | aceleración hacia arriba, para motas que flotan |
| `amortiguar` | frenan con el tiempo |
| `remolino` | giran alrededor del centro |
| `hacia_centro` | se juntan |
| `giro` | grados por segundo |
| `emision` | `{"esfera": r}`, `{"anillo": r, "interior": 0–1, "alto": h}` o `{"caja": [x, y, z]}` |
| `brillo` | más de 1 alimenta el resplandor |
| `mezcla` | `suma` (luz) o `mezcla` (opaco) |
| `explosividad` | 1 = todas a la vez |

**Otras capas:**

| tipo | campos |
| --- | --- |
| `luz` | `color`, `energia`, `alcance`, `dur` (se apaga sola) |
| `anillo` | anillo en el piso que crece: `color`, `radio` [inicio, fin], `dur`, `grosor`, `brillo`, `mezcla` |
| `destello` | fogonazo que mira a la cámara: `color`, `tam` [inicio, fin], `dur`, `brillo` |

### Proyectiles

```json
"disparo_colonos": {
  "proyectil": {
    "velocidad": 22, "altura": 0.55, "arco": 0.0,
    "cuerpo": {"tam": 0.22, "color": "#cfefff", "brillo": 4},
    "cinta": {"largo": 0.9, "ancho": 0.15, "color": "#5fb8ff"},
    "estela": {"forma": "mota", "vida": 0.18, "tam": [0.13, 0.02], "color": ["#e6f7ff", "#5fb8ff"], "por_casilla": 12},
    "luz": {"color": "#6cc4ff", "energia": 1.5, "alcance": 2.5},
    "impacto": "impacto_disparo_colonos"
  }
}
```

| campo | qué hace |
| --- | --- |
| `velocidad` | casillas por segundo; `dur_min` y `dur_max` limitan cuánto tarda |
| `arco` | lo curva hacia arriba (0.12 = un globo de ácido) |
| `cinta` | tira brillante que lo sigue; por defecto toma el color de en medio de la estela; `false` la quita |
| `estela` | partículas que va soltando; `por_casilla` asegura que cubra el camino |
| `impacto` | efecto que sale al llegar |

Si se pide `proyectil()` con un efecto que no es proyectil, sale en el destino.
