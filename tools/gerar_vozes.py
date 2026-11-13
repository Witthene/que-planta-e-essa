"""Grava as falas do app com a voz da Yui (Fish Audio) em assets/vozes.

Cada frase vira v_<hash>.mp3, com o mesmo hash FNV-1a que lib/voz.dart calcula,
então o app acha o áudio pelo próprio texto. Frases já gravadas são puladas.

Uso: <python do venv da Yui> tools/gerar_vozes.py
"""
import os
import re
import sys
from pathlib import Path

import requests
from dotenv import dotenv_values

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "assets" / "vozes"
ENV = dotenv_values(Path.home() / "Projects" / "yui" / ".env")

AGUA = ["pouca água", "água de vez em quando", "bastante água"]
SOL = ["sombra", "um pouco de sol", "muito sol"]
FIXAS = [
    "Que planta é essa? Aponte a câmera para a planta.",
    "Achei! Deixa eu ver...",
    "Deixa eu ver...",
    "Isso não parece uma planta. Tente de novo.",
    "Aponte para outra planta.",
    "Cuidado: essa planta é venenosa. Não coma e lave as mãos.",
    "Não tenho certeza. Chegue mais perto da folha ou da flor.",
    "Uma curiosidade:",
]


def chave(texto):
    h = 0x811C9DC5
    for b in texto.strip().lower().encode("utf-8"):
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return f"v_{h:08x}"


def frases():
    cuidados = (RAIZ / "lib" / "cuidados.dart").read_text(encoding="utf-8")
    bloco = cuidados.split("nomesPopulares")[1].split("};")[0]
    nomes = sorted(set(re.findall(r":\s*'([^']+)'", bloco)))
    yield from FIXAS
    for a in AGUA:
        for s in SOL:
            yield f"Ela gosta de {a} e de {s}."
    nomes += ["cacto", "suculenta", "orquídea", "bromélia", "palmeira", "capim", "samambaia"]
    for n in sorted(set(nomes)):
        yield f"Essa planta se chama {n[0].upper() + n[1:]}."


def main():
    SAIDA.mkdir(parents=True, exist_ok=True)
    headers = {"Authorization": f"Bearer {ENV['FISH_API_KEY']}", "Content-Type": "application/json"}
    if ENV.get("FISH_MODEL"):
        headers["model"] = ENV["FISH_MODEL"]
    lista = list(dict.fromkeys(frases()))
    feitas = 0
    for i, texto in enumerate(lista, 1):
        arq = SAIDA / f"{chave(texto)}.mp3"
        if arq.exists():
            continue
        corpo = {"text": texto, "reference_id": ENV["FISH_VOICE_ID"], "format": "mp3",
                 "normalize": True, "latency": "normal"}
        r = requests.post("https://api.fish.audio/v1/tts", json=corpo, headers=headers, timeout=90)
        if r.status_code != 200:
            sys.exit(f"Falhou em '{texto}': {r.status_code} {r.text[:200]}")
        arq.write_bytes(r.content)
        feitas += 1
        print(f"[{i}/{len(lista)}] {texto}", flush=True)
    print(f"Pronto: {feitas} novas, {len(lista)} no total.")


if __name__ == "__main__":
    main()
