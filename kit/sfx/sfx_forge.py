"""SFXForge: sonidos de juego sintetizados a partir de recetas en JSON.

Parte del kit de herramientas (reutilizable entre juegos). No usa muestras
externas: cada sonido se arma con capas (ruido filtrado, tonos, metal,
cristal, crujidos, burbujas), se le da espacio (sala, eco) y se exporta en
varias variantes para que no suene repetido.

Uso:
    python kit/sfx/sfx_forge.py herramientas/sonidos_karth.json
    python kit/sfx/sfx_forge.py herramientas/sonidos_karth.json --solo disparo_colonos
    python kit/sfx/sfx_forge.py herramientas/sonidos_karth.json --lista

Las rutas de "salida" y "cfg" del JSON son relativas a la carpeta del JSON
(o absolutas). El formato completo está en kit/sfx/LEEME.md.
Requiere numpy y scipy (pip install numpy scipy).
"""
import argparse
import copy
import json
import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100


# ---------------------------------------------------------------- utilidades
def _n(d):
    return max(1, int(round(d * SR)))


def envolvente(n, e, rng=None, azar=0.0):
    """Ataque lineal, sostén y caída (exponencial o lineal). Trémolo opcional."""
    e = e or {}
    a = float(e.get("a", 0.002))
    m = float(e.get("mantener", 0.0))
    d = float(e.get("d", 0.2))
    if rng is not None and azar > 0:
        d *= max(0.3, 1.0 + rng.normal(0, azar))
    x = np.arange(n) / SR
    env = np.clip(x / max(a, 1e-4), 0.0, 1.0)
    tc = np.clip(x - a - m, 0.0, None)
    if e.get("forma", "exp") == "lin":
        env *= np.clip(1.0 - tc / max(d, 1e-4), 0.0, 1.0)
    else:
        env *= np.exp(-tc / max(d, 1e-4) * 3.0)   # d = tiempo hasta ~-26 dB
    trem = e.get("trem")
    if trem:
        hz, prof = float(trem[0]), float(trem[1])
        env *= 1.0 - prof * 0.5 * (1.0 + np.sin(2 * np.pi * hz * x))
    return env


def curva(f0, f1, n, forma="exp"):
    if f1 is None or f1 == f0:
        return np.full(n, float(f0))
    u = np.linspace(0.0, 1.0, n)
    if forma == "lin":
        return f0 + (f1 - f0) * u
    return f0 * (f1 / f0) ** u


def ruido(n, color, rng):
    w = rng.standard_normal(n)
    if color == "blanco":
        return w
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1] if n > 1 else 1.0
    spec /= np.sqrt(f) if color == "rosa" else f
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-9)


def _sos(tipo, f, q=0.707):
    f = float(np.clip(f, 20.0, SR * 0.45))
    if tipo == "banda":
        ancho = f / max(q, 0.1)
        lo = max(20.0, f - ancho / 2)
        hi = min(SR * 0.45, f + ancho / 2)
        return signal.butter(2, [lo, hi], btype="bandpass", fs=SR, output="sos")
    bt = {"pb": "lowpass", "pa": "highpass"}[tipo]
    return signal.butter(2, f, btype=bt, fs=SR, output="sos")


def filtrar(x, fl, rng=None, azar=0.0):
    """Filtro fijo o con barrido (f -> f_fin), procesado por bloques."""
    if not fl:
        return x
    tipo = fl.get("tipo", "pb")
    f0 = float(fl["f"])
    f1 = fl.get("f_fin")
    q = float(fl.get("q", 0.707))
    if rng is not None and azar > 0:
        k = 1.0 + rng.normal(0, azar)
        f0 *= k
        f1 = None if f1 is None else float(f1) * k
    if f1 is None:
        y = signal.sosfilt(_sos(tipo, f0, q), x)
    else:
        bloque = 128
        fs = curva(f0, float(f1), len(x), fl.get("curva", "exp"))
        y = np.zeros_like(x)
        zi = None
        for i in range(0, len(x), bloque):
            sos = _sos(tipo, fs[i], q)
            if zi is None:
                zi = np.zeros((sos.shape[0], 2))
            y[i:i + bloque], zi = signal.sosfilt(sos, x[i:i + bloque], zi=zi)
    if fl.get("orden", 2) >= 4:   # pasar dos veces = pendiente más dura
        y = filtrar(y, dict(fl, orden=2))
    return y


def oscilador(frec, onda, rng):
    fase = 2 * np.pi * np.cumsum(frec) / SR + rng.uniform(0, 2 * np.pi)
    if onda == "seno":
        return np.sin(fase)
    if onda == "tri":
        return 2 / np.pi * np.arcsin(np.sin(fase))
    # sierra sin aliasing exagerado: suma de armónicos limitada
    y = np.zeros_like(fase)
    kmax = int(min(40, SR * 0.4 / max(1.0, float(np.max(frec)))))
    for k in range(1, max(2, kmax)):
        y += np.sin(k * fase) / k * (1 if onda == "sierra" else (k % 2))
    return y * 0.6


# ---------------------------------------------------------------- capas
def capa_ruido(c, n, rng, az):
    x = ruido(n, c.get("color", "blanco"), rng)
    return filtrar(x, c.get("filtro"), rng, az) * envolvente(n, c.get("env"), rng, az)


def capa_tono(c, n, rng, az):
    k = 1.0 + (rng.normal(0, az) if az else 0.0)
    f0 = float(c.get("f", 220)) * k
    f1 = c.get("f_fin")
    f1 = None if f1 is None else float(f1) * k
    frec = curva(f0, f1, n, c.get("curva", "exp"))
    vib = c.get("vibrato")
    if vib:
        x = np.arange(n) / SR
        frec = frec * 2 ** (float(vib[1]) / 1200 * np.sin(2 * np.pi * float(vib[0]) * x))
    fm = c.get("fm")
    if fm:
        ind = curva(float(fm.get("indice", 2.0)) + 1e-6, float(fm.get("indice_fin", fm.get("indice", 2.0))) + 1e-6, n)
        mod = np.sin(2 * np.pi * np.cumsum(frec * float(fm.get("razon", 1.0))) / SR)
        frec = frec * (1.0 + ind * mod * 0.1)
    y = np.zeros(n)
    for r, a in c.get("armonicos", [[1, 1]]):
        y += float(a) * oscilador(frec * float(r), c.get("onda", "seno"), rng)
    y = filtrar(y, c.get("filtro"), rng, az)
    return y * envolvente(n, c.get("env"), rng, az)


def capa_metal(c, n, rng, az):
    """Parciales inarmónicos que caen más rápido cuanto más agudos (metal, cristal)."""
    k = 1.0 + (rng.normal(0, az) if az else 0.0)
    base = float(c.get("f", 500)) * k
    caida = float(c.get("caida", 0.3)) * (1.0 + (rng.normal(0, az) if az else 0.0))
    rapidez = float(c.get("caida_agudos", 0.6))
    batido = float(c.get("batido", 0.0))
    parciales = c.get("parciales", [[1, 1], [2.76, 0.6], [5.4, 0.4], [8.93, 0.25]])
    x = np.arange(n) / SR
    y = np.zeros(n)
    for i, (r, a) in enumerate(parciales):
        f = base * float(r) * (1.0 + rng.normal(0, 0.004))
        if f > SR * 0.45:
            continue
        tau = caida * (rapidez ** i)
        p = np.sin(2 * np.pi * f * x + rng.uniform(0, 6.28))
        if batido:
            p += np.sin(2 * np.pi * (f + batido * (i + 1)) * x)
            p *= 0.5
        y += float(a) * p * np.exp(-x / max(tau, 1e-3) * 3.0)
    ataque = float(c.get("a", 0.0008))
    y *= np.clip(x / max(ataque, 1e-4), 0, 1)
    golpe = float(c.get("golpe", 0.3))   # chasquido de ruido al inicio
    if golpe > 0:
        g = ruido(n, "blanco", rng) * np.exp(-x / 0.004)
        y += golpe * filtrar(g, {"tipo": "pa", "f": base * 2})
    return filtrar(y, c.get("filtro"), rng, az)


def capa_crujido(c, n, rng, az):
    """Granos cortos al azar: quitina, hueso, grava, chispas eléctricas."""
    dens = float(c.get("densidad", 200))
    tam = float(c.get("tam_grano", 0.002))
    y = np.zeros(n)
    env = envolvente(n, c.get("env"), rng, az)
    cuantos = int(dens * n / SR)
    ng = _n(tam) * 4
    gx = np.arange(ng) / SR
    for _ in range(cuantos):
        i = int(rng.integers(0, n))
        if rng.random() > env[i] + 0.02:
            continue
        g = rng.standard_normal(ng) * np.exp(-gx / tam) * rng.uniform(0.3, 1.0)
        fin = min(n, i + ng)
        y[i:fin] += g[:fin - i]
    return filtrar(y, c.get("filtro"), rng, az) * np.maximum(env, 0.0)


def capa_burbujas(c, n, rng, az):
    """Gotas que suben o bajan de tono: líquido, carne, ácido."""
    dens = float(c.get("densidad", 25))
    lo, hi = c.get("f", [300, 900])
    sube = float(c.get("sube", 1.8))
    dur = float(c.get("dur_grano", 0.03))
    env = envolvente(n, c.get("env"), rng, az)
    y = np.zeros(n)
    ng = _n(dur)
    gx = np.arange(ng) / SR
    for _ in range(int(dens * n / SR)):
        i = int(rng.integers(0, n))
        if rng.random() > env[i] + 0.02:
            continue
        f0 = np.exp(rng.uniform(np.log(lo), np.log(hi)))
        fr = f0 * sube ** (gx / dur)
        g = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.sin(np.pi * gx / dur) ** 2
        fin = min(n, i + ng)
        y[i:fin] += g[:fin - i] * rng.uniform(0.3, 1.0)
    return filtrar(y, c.get("filtro"), rng, az)


CAPAS = {
    "ruido": capa_ruido,
    "tono": capa_tono,
    "metal": capa_metal,
    "cristal": capa_metal,
    "crujido": capa_crujido,
    "burbujas": capa_burbujas,
}


def _cristal_por_defecto(c):
    if c.get("tipo") == "cristal":
        c.setdefault("parciales", [[1, 1], [2.32, 0.7], [4.25, 0.45], [6.63, 0.3], [9.38, 0.18]])
        c.setdefault("caida", 1.2)
        c.setdefault("caida_agudos", 0.8)
        c.setdefault("batido", 1.3)
        c.setdefault("golpe", 0.12)
    return c


# ---------------------------------------------------------------- efectos
def sala(x, tam=0.6, mezcla=0.2, brillo=4000.0, rng=None):
    """Reverb por convolución con una respuesta sintética (ruido que se apaga y se oscurece)."""
    rng = rng or np.random.default_rng(1)
    n = _n(tam * 1.5)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / max(tam, 0.05) * 3.0)
    mitad = n // 2
    ir[:mitad] = filtrar(ir[:mitad], {"tipo": "pb", "f": brillo})
    ir[mitad:] = filtrar(ir[mitad:], {"tipo": "pb", "f": brillo * 0.4})
    ir[: _n(0.008)] *= np.linspace(0, 1, _n(0.008))   # pre-retardo suave
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    mojado = signal.fftconvolve(np.concatenate([x, np.zeros(n)]), ir)[: len(x) + n]
    seco = np.concatenate([x, np.zeros(n)])
    return seco * (1 - mezcla) + mojado * mezcla * 3.0


def eco(x, ret=0.12, fb=0.35, veces=3):
    d = _n(ret)
    y = np.concatenate([x, np.zeros(d * veces)])
    for k in range(1, veces + 1):
        y[d * k: d * k + len(x)] += filtrar(x, {"tipo": "pb", "f": 6000 / k}) * fb ** k
    return y


def aplicar_fx(y, fx, rng):
    fx = fx or {}
    if fx.get("distorsion"):
        dr = 1.0 + 12.0 * float(fx["distorsion"])
        y = np.tanh(y / (np.max(np.abs(y)) + 1e-9) * dr) / np.tanh(dr)
    y = filtrar(y, {"tipo": "pb", "f": fx.get("pasa_bajos", 12000)})
    if fx.get("eco"):
        e = fx["eco"]
        y = eco(y, e.get("ret", 0.12), e.get("fb", 0.35), e.get("veces", 3))
    if fx.get("sala"):
        s = fx["sala"]
        y = sala(y, s.get("tam", 0.6), s.get("mezcla", 0.2), s.get("brillo", 4000), rng)
    y = filtrar(y, {"tipo": "pa", "f": fx.get("pasa_altos", 35)})
    if fx.get("al_reves"):
        y = y[::-1].copy()
    return y


def recortar_cola(y, umbral_db=-50.0):
    lim = np.max(np.abs(y)) * 10 ** (umbral_db / 20)
    fuertes = np.nonzero(np.abs(y) > lim)[0]
    if len(fuertes) == 0:
        return y
    fin = min(len(y), fuertes[-1] + _n(0.02))
    y = y[:fin]
    f = min(len(y), _n(0.015))
    y[-f:] *= np.linspace(1, 0, f)
    return y


# ---------------------------------------------------------------- recetas
def mezclar(base, extra):
    out = copy.deepcopy(base)
    for k, v in extra.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = mezclar(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def resolver(nombre, sonidos, plantillas, visto=None):
    visto = visto or set()
    r = sonidos.get(nombre) or plantillas.get(nombre)
    if r is None:
        raise KeyError("No existe la receta o plantilla '%s'" % nombre)
    padre = r.get("hereda")
    if padre:
        if padre in visto:
            raise ValueError("Herencia circular en '%s'" % nombre)
        visto.add(nombre)
        base = resolver(padre, sonidos, plantillas, visto)
        return mezclar(base, {k: v for k, v in r.items() if k != "hereda"})
    return copy.deepcopy(r)


def sintetizar(receta, semilla):
    rng = np.random.default_rng(semilla)
    az = float(receta.get("azar", 0.06))
    dur = float(receta.get("dur", 0.6))
    n = _n(dur)
    y = np.zeros(n)
    for c in receta.get("capas", []):
        c = _cristal_por_defecto(dict(c))
        if rng.random() > float(c.get("prob", 1.0)):
            continue
        ini = _n(float(c.get("t0", 0.0)) + (abs(rng.normal(0, float(c.get("t0_azar", 0.0))))))
        largo = n - ini
        if largo <= 0:
            continue
        cap = CAPAS[c.get("tipo", "ruido")](c, largo, rng, az)
        cap = cap / (np.max(np.abs(cap)) + 1e-9) * float(c.get("gan", 1.0))
        y[ini:] += cap
    y = aplicar_fx(y, receta.get("fx"), rng)
    y = recortar_cola(y)
    pico = float(receta.get("vol", 0.85))
    return y / (np.max(np.abs(y)) + 1e-9) * pico


def guardar_wav(ruta, y):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    data = (np.clip(y, -1, 1) * 32767).astype(np.int16)
    with wave.open(ruta, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def _valor_cfg(v):
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(_valor_cfg(x) for x in v) + "]"
    if isinstance(v, float):
        return repr(round(v, 4))
    return str(v)


JUEGO_DEFECTO = {"vol_db": 0.0, "tono": [0.96, 1.04], "voces": 4, "espera": 0.03, "alcance": 12.0, "bus": "Efectos"}


def main(argv=None):
    ap = argparse.ArgumentParser(description="SFXForge: sintetiza sonidos desde recetas JSON")
    ap.add_argument("recetas")
    ap.add_argument("--solo", nargs="*", help="generar solo estos sonidos")
    ap.add_argument("--lista", action="store_true", help="mostrar los sonidos y salir")
    args = ap.parse_args(argv)

    with open(args.recetas, encoding="utf-8") as f:
        datos = json.load(f)
    base_dir = os.path.dirname(os.path.abspath(args.recetas))
    aj = datos.get("ajustes", {})
    salida = os.path.normpath(os.path.join(base_dir, aj.get("salida", "sounds")))
    cfg = aj.get("cfg")
    cfg = os.path.normpath(os.path.join(base_dir, cfg)) if cfg else None
    prefijo_res = aj.get("ruta_res", "res://sounds/")
    plantillas = datos.get("plantillas", {})
    sonidos = datos.get("sonidos", {})
    juego_def = dict(JUEGO_DEFECTO, **aj.get("juego", {}))

    if args.lista:
        for k in sonidos:
            print(k)
        return 0

    entradas = {}
    for nombre in sonidos:
        r = resolver(nombre, sonidos, plantillas)
        juego = dict(juego_def, **r.get("juego", {}))
        if "igual_a" in r:   # alias: mismo audio que otro evento, otros ajustes de juego
            entradas[nombre] = {"igual_a": r["igual_a"], "juego": juego}
            continue
        nvar = int(r.get("variantes", 3))
        archivos = []
        for i in range(nvar):
            archivo = "%s_%d.wav" % (nombre, i + 1)
            archivos.append(prefijo_res + archivo)
            if args.solo is not None and nombre not in args.solo:
                continue
            semilla = int(r.get("semilla", sum(ord(ch) for ch in nombre) * 31)) + i * 7919
            guardar_wav(os.path.join(salida, archivo), sintetizar(r, semilla))
        entradas[nombre] = {"archivos": archivos, "juego": juego}
        if args.solo is None or nombre in args.solo:
            print("  %-26s %d variantes" % (nombre, nvar))

    if cfg:
        lineas = ["; Generado por kit/sfx/sfx_forge.py desde %s. No editar a mano:" % os.path.basename(args.recetas),
                  "; cambia la receta y vuelve a generar.", ""]
        for nombre, e in entradas.items():
            archivos = e.get("archivos")
            if archivos is None:
                destino = entradas.get(e["igual_a"])
                if destino is None or "archivos" not in destino:
                    raise KeyError("'%s' es igual_a '%s', que no existe" % (nombre, e["igual_a"]))
                archivos = destino["archivos"]
            lineas.append("[%s]" % nombre)
            lineas.append("archivos=%s" % _valor_cfg(archivos))
            for k, v in e["juego"].items():
                lineas.append("%s=%s" % (k, _valor_cfg(v)))
            lineas.append("")
        os.makedirs(os.path.dirname(cfg), exist_ok=True)
        with open(cfg, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lineas))
        print("cfg: %s (%d eventos)" % (cfg, len(entradas)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
