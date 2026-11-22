# UIBuilder v2

Interfaces para Godot 4 escritas en JSON y enlazadas al estado del juego.
Probado en Godot 4.7.2.

## Instalación

1. Copia la carpeta `kit/ui/` dentro del proyecto (queda `res://kit/ui/`).
2. Proyecto → Configuración del proyecto → Globales (Autoload): agrega
   `res://kit/ui/ui_builder.gd` con el nombre **UIBuilder**.
3. Para ver la demo: escena nueva con un `Node2D`, ponle
   `kit/ui/ejemplos/prueba_ui.gd` y ejecútala (I = mochila, E = equipo, T = tienda, J = diario, O = opciones, Esc = cerrar).

## Uso desde el juego

```gdscript
UIBuilder.cargar_tema("res://ui/tema.json")
UIBuilder.cargar_plantillas("res://ui/plantillas.json")

# 1) El juego escribe en el estado. La interfaz se actualiza sola.
UIBuilder.estado.poner("jugador.vida", 70)
UIBuilder.estado.sumar("jugador.creditos", -40)
UIBuilder.estado.fusionar("jugador", {"vida": 70, "energia": 20})

# 2) Cada interfaz tiene su propia señal.
var hud := UIBuilder.abrir("res://ui/hud.json")
var tienda := UIBuilder.alternar("res://ui/tienda.json")   # abre o cierra (teclas)
if tienda:
    tienda.accion.connect(func(nombre, datos): print(nombre, datos))

# 3) Diálogo que espera la respuesta (-1 si se cerró con Esc).
var r := await UIBuilder.preguntar("Herrero", "¿Mejorar por 50?", ["Sí", "No"])
```

Si modificas un Array que ya está guardado (por ejemplo con `append`), avisa:
`UIBuilder.estado.avisar("inventario.objetos")`.

## Enlaces en el JSON

| Escribes | Significa |
|---|---|
| `"valor": "@jugador.vida"` | el valor de esa ruta del estado |
| `"visible": "@!tienda.cerrada"` | ese valor, negado |
| `"texto": "Créditos: {jugador.creditos}"` | texto con valores intercalados |

## Componentes

Todos aceptan: `id`, `tamano` `[ancho, alto]`, `tooltip`, `visible`, `expandir`, `expandir_v`.

| tipo | propiedades |
|---|---|
| `panel` | `titulo`, `separacion`, hijos |
| `vertical`, `horizontal` | `separacion`, `alinear` (inicio, centro, final), hijos |
| `rejilla` | `columnas`, `separacion`, hijos |
| `lista` (con scroll) | `ancho`, `alto`, `separacion`, hijos |
| `texto` | `texto`, `estilo` (normal, titulo, tenue), `color`, `tam`, `alinear` (izq, centro, der), `ajustar` |
| `boton` | `texto`, `accion`, `datos`, `deshabilitado` |
| `barra` | `valor`, `max`, `color`, `texto`, `mostrar_porcentaje` |
| `imagen` | `textura` |
| `ranura` | `objeto` (enlace, p. ej. `"@equipo.casco"`) o bien `icono`, `cantidad`, `rareza`; `tam`, `silueta` (imagen tenue cuando está vacía), `accion`, `datos`, arrastre |
| `ranuras` | `objetos` (enlace a una lista), `columnas`, `filas` o `cantidad` (puede ir enlazada: `"@mochila.capacidad"`), `tam_ranura`, `accion`, arrastre |
| `dialogo` | `titulo`, `texto`, `ancho`, `opciones`, `accion`, hijos |
| `espacio` | (rellena el hueco) |
| `pestanas` | `paginas` (lista de `{"titulo", "hijos"}`), `seleccion`, `ancho`, `alto`, `accion` |
| `deslizador` | `valor`, `min`, `max`, `paso`, `mostrar_valor`, `accion`, `accion_al_soltar` (la acción solo al soltar, no mientras se arrastra) |
| `casilla` | `texto`, `valor`, `accion` |
| `campo` (texto) | `texto`, `pista`, `ancho`, `max_largo`, `secreto`, `limpiar_al_enviar`, `accion` (al pulsar Enter), `accion_al_escribir` (con cada letra) |

**hijos** quiere decir: `"hijos": [ ... ]` y/o repetir por datos:

```json
{"tipo": "lista", "repetir": "@tienda.objetos", "elemento":
    {"tipo": "boton", "texto": "{item.nombre}", "accion": "comprar", "datos": {"id": "@item.id"}}}
```

Dentro de `elemento` existen `item` e `indice`. Con `"como": "mision"` cambias el nombre de `item`.

`color` acepta `"#rrggbb"` o el nombre de un color del tema (`"acento"`, `"vida"`...).
`"accion": "ui:cerrar"` cierra la interfaz sin pasar por el juego.
Cada objeto de `ranuras` es `null` (vacía) o `{"icono", "cantidad", "nombre", "descripcion", "rareza"}`;
su acción llega con `{"indice", "boton": "izq"/"der", "objeto"}`.

Solo en la raíz de la interfaz:

| propiedad | valores |
|---|---|
| `capa` | `hud` (no se cierra con Esc), `ventana` (por defecto), `modal` (bloquea lo de atrás) |
| `posicion` | centro, arriba, abajo, izq, der, arriba_izq, arriba_der, abajo_izq, abajo_der, completo |
| `margen` | separación del borde de la pantalla |
| `cerrar_con_esc` | `false` para que Esc no la cierre |
| `movible` | `true` para moverla arrastrando su fondo, título o textos (solo ventanas) |

Una ventana movible no se sale de la pantalla y recuerda su posición al cerrarla y
volver a abrirla (mientras el juego siga abierto).

## Arrastrar objetos entre ranuras

**arrastre** quiere decir estas propiedades de `ranura` y `ranuras`:

| propiedad | significado |
|---|---|
| `arrastrable` | `true`: los objetos de aquí se pueden arrastrar |
| `al_soltar` | nombre de la acción que se emite cuando sueltan un objeto aquí |
| `acepta` | solo recibe objetos con esos campos, p. ej. `{"clase": "casco"}` |
| `grupo` | solo se arrastra entre ranuras del mismo grupo (por defecto, todas) |
| `intercambio` | `false` si soltar aquí no devuelve nada al origen (un yunque, una casilla de venta): así no se exige que lo de aquí quepa allá |

```json
{"tipo": "ranuras", "objetos": "@inventario.objetos", "arrastrable": true, "al_soltar": "mover"}
{"tipo": "ranura", "objeto": "@equipo.casco", "arrastrable": true, "al_soltar": "mover",
    "acepta": {"clase": "casco"}}
```

El kit no mueve nada por su cuenta: avisa y el juego decide. La acción llega a la vista
donde se soltó, con `desde`, `desde_indice`, `hasta`, `hasta_indice`, `objeto` y
`objeto_destino`. Para el caso normal basta una línea:

```gdscript
func _on_inventario(nombre: String, d: Dictionary) -> void:
    if nombre == "mover":
        UIBuilder.estado.intercambiar(d.desde, d.desde_indice, d.hasta, d.hasta_indice)
```

`intercambiar` mueve el objeto si el destino está vacío y los intercambia si está ocupado.
En un juego en red, en vez de esa línea se le pide el movimiento al servidor.
Funciona entre ventanas distintas (mochila → equipo). El clic de una ranura (`accion`)
cuenta al soltar el botón, así que arrastrar un objeto no lo "usa".

## Controles que escriben en el estado

En `deslizador`, `casilla`, `campo` y `pestanas` (`seleccion`), si el valor es un enlace
(`"@opciones.musica"`), el control lee ese dato y además lo escribe cuando el jugador lo cambia.
No hace falta código para guardar el volumen o el nombre: el juego solo lee el estado.

```json
{"tipo": "deslizador", "valor": "@opciones.musica", "mostrar_valor": true}
{"tipo": "casilla", "texto": "Pantalla completa", "valor": "@opciones.pantalla_completa", "accion": "pantalla_completa"}
{"tipo": "campo", "texto": "@jugador.nombre", "pista": "Tu nombre", "max_largo": 16}
{"tipo": "pestanas", "seleccion": "@ui.pestana_diario", "paginas": [
    {"titulo": "Misiones", "hijos": [ ... ]},
    {"titulo": "Personaje", "hijos": [ ... ]}
]}
```

Si además tiene `accion`, también avisa al juego (con `{"valor": ...}`, o `{"texto": ...}`
en el campo al pulsar Enter, o `{"indice", "titulo"}` al cambiar de pestaña). Úsalo para
lo que deba pasar al momento, como cambiar a pantalla completa.

## Notificaciones

```gdscript
UIBuilder.notificar("Casco de colono", {"titulo": "Objeto obtenido", "icono": "res://...", "rareza": "poco_comun"})
UIBuilder.notificar("+30 de vida", {"color": "vida", "duracion": 1.5})
```

Aparecen en una esquina (`UIBuilder.esquina_avisos`, por defecto `"arriba_der"`), como
máximo 5 a la vez (`max_avisos`), y desaparecen solas. No bloquean clics.

## Tooltip de objetos

Al pasar el ratón sobre un objeto en `ranura` o `ranuras` aparece un tooltip con sus datos:
`nombre` (del color de su rareza), `rareza`, `tipo`, `stats` (`{"Daño": 18, "Defensa": "+3"}`;
lo que empieza con `+` sale en verde y con `-` en rojo), `descripcion` y `pie`.
Para dibujarlo a tu manera en un juego concreto:

```gdscript
UIBuilder.tooltip_objeto = func(objeto: Dictionary) -> Control:
    var l := Label.new()
    l.text = objeto.nombre
    return l
```

## Menú de clic derecho

```gdscript
UIBuilder.menu([
    {"titulo": "Rifle de plasma", "color": Color(0.4, 0.65, 1)},
    {"texto": "Equipar", "accion": func(): jugador.equipar("rifle")},
    {"texto": "Desechar", "accion": func(): pedir_confirmacion(), "cierra": false},
    {"texto": "Vender", "accion": func(): pass, "desactivada": true},
])
```

Aparece junto al ratón y se cierra con un clic fuera, con Esc o al elegir una opción.
`{"texto": "..."}` sin `accion` es una línea de texto (para preguntas como "¿Seguro?").
Para confirmar, una opción con `"cierra": false` puede llamar otra vez a `UIBuilder.menu(...)`.

## Adaptar el kit al estilo de cada juego

```gdscript
# Los estilos del juego (paneles, botones, fuentes) mandan sobre los del kit.
UIBuilder.tema_base = MiTema.get_theme()
UIBuilder.aplicar_tema({"colores": {"acento": Color.ORANGE}, "fuente_titulo": load("res://fonts/titulo.ttf")})
# Si el tema del juego cambia (por ejemplo, de bando): UIBuilder.refrescar_tema()

# Marcas propias en las casillas (+N, favorito...). "marcas" se vacía en cada repintado.
UIBuilder.decorar_ranura = func(ranura: Control, marcas: Control, objeto: Dictionary):
    if objeto.get("favorito", false):
        var l := Label.new(); l.text = "★"; marcas.add_child(l)

# Animación al abrir ventanas y sonido de clic (sin ellas: un desvanecido corto y nada).
UIBuilder.al_abrir = func(contenido: Control, vista: UIVista): mi_animacion(contenido)
UIBuilder.al_clic = func(): reproducir("clic")
```

## Plantillas

```json
{"ventana": {
    "parametros": {"titulo": "", "hijos": []},
    "cuerpo": {"tipo": "panel", "hijos": [
        {"tipo": "texto", "texto": "$titulo", "estilo": "titulo"},
        "$hijos"
    ]}
}}
```

Se usa con `{"usar": "ventana", "titulo": "Mochila", "hijos": [...]}`. Lo que no sea
parámetro (`id`, `posicion`...) se aplica al componente raíz de la plantilla.

## Componentes propios del juego

```gdscript
UIBuilder.registrar_componente("minimapa", func(spec, ctx):
    var m := Minimapa.new()
    ctx.enlazar(m, spec, "zoom", func(v): m.zoom = float(v))
    return m
, {"zoom": "numero*"})
```

## Tema

```json
{"colores": {"fondo": "#221814", "acento": "#ff6a1a", "vida": "#c0392b"},
 "rarezas": {"mitico": "#ff3366"},
 "radio": 4, "grosor_borde": 2, "tam_fuente": 16, "fuente": "res://fuentes/mi_fuente.ttf"}
```

Colores base: fondo, borde, texto, texto_tenue, acento, boton, boton_hover, ranura,
barra_fondo, velo, error. `aplicar_tema()` y `cargar_tema()` cambian también lo que ya está en pantalla.

## Clics y teclado

- Los clics sobre una interfaz no llegan a `_unhandled_input()` del juego.
- Si el juego lee clics en `_input()` o con `Input.is_action_just_pressed()`, pregunta antes:
  `if UIBuilder.raton_sobre_ui(): return`
- Esc cierra la ventana de arriba. Si tu menú de pausa también usa Esc dentro de `_input()`,
  pregunta antes: `if UIBuilder.hay_ventanas(): return`
- `UIBuilder.hay_modal()` dice si hay un diálogo modal abierto (para pausar el movimiento).
- Mientras el jugador escribe en un `campo`, las teclas no llegan a `_unhandled_input()`.
  Si el juego mueve al personaje con `Input.is_action_pressed()`, pregunta antes:
  `if UIBuilder.escribiendo(): return`
- En un campo, Esc o un clic fuera dejan de escribir (Esc no cierra la ventana esa vez).

## Errores y recarga

- Un JSON con errores no se construye: aparece un panel rojo con cada error y su ubicación,
  y lo mismo sale en la consola.
- Mientras el juego corre desde el editor, al guardar un JSON (interfaz, plantillas o tema)
  la pantalla se actualiza sola en medio segundo. En el juego exportado esto se apaga.
