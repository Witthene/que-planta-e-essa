"""Desenha o ícone do app (girassol sobre fundo verde) em assets/icone/.

Gera icone.png (completo) e frente.png (só o girassol, para o ícone adaptativo).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 4096  # desenha grande e reduz, para bordas suaves
FINAL = 1024
SAIDA = Path(__file__).resolve().parent.parent / "assets" / "icone"


def degrade(tam, topo, base):
    img = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        img.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(topo, base)))
    return img.resize((tam, tam))


def petala(tam, cor_base, cor_ponta):
    """Pétala em gota, com degradê da base para a ponta."""
    w, h = int(tam / 2.9), tam
    mascara = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mascara)
    pontos = []
    for i in range(181):
        a = math.radians(i * 2)
        x = math.sin(a) * w / 2 * (1 - 0.35 * math.cos(a) ** 8)
        y = (1 - math.cos(a)) / 2 * h
        pontos.append((w / 2 + x * (0.45 + 0.55 * math.sin(a / 2)), y))
    d.polygon(pontos, fill=255)
    cor = degrade(h, cor_ponta, cor_base).resize((w, h))
    p = Image.new("RGBA", (w, h))
    p.paste(cor, (0, 0), mascara)
    # nervura central clarinha
    veia = Image.new("RGBA", (w, h))
    ImageDraw.Draw(veia).line([(w / 2, h * 0.15), (w / 2, h * 0.8)], fill=(255, 240, 170, 70), width=max(2, w // 28))
    veia.putalpha(Image.composite(veia.split()[3], Image.new("L", (w, h), 0), mascara))
    p.alpha_composite(veia)
    return p


def girassol(tam):
    img = Image.new("RGBA", (tam, tam))
    c = tam / 2
    for camada, (n, comp, giro, base, ponta) in enumerate([
        (20, 0.47, 0.5, (226, 128, 8), (245, 166, 20)),
        (20, 0.44, 0.0, (246, 168, 22), (255, 214, 64)),
    ]):
        p = petala(int(tam * comp), base, ponta)
        for i in range(n):
            ang = 360 / n * (i + giro)
            r = p.rotate(ang, expand=True, resample=Image.BICUBIC)
            # a ponta da pétala aponta para fora, a base fica no miolo
            rad = math.radians(ang)
            dist = tam * comp / 2 + tam * 0.06
            x = c - math.sin(rad) * dist - r.width / 2
            y = c - math.cos(rad) * dist - r.height / 2
            img.alpha_composite(r, (int(x), int(y)))
    d = ImageDraw.Draw(img)
    rm = tam * 0.2
    sombra = Image.new("RGBA", (tam, tam))
    ImageDraw.Draw(sombra).ellipse([c - rm * 1.08, c - rm * 1.0, c + rm * 1.08, c + rm * 1.16], fill=(90, 40, 0, 140))
    img.alpha_composite(sombra.filter(ImageFilter.GaussianBlur(tam * 0.012)))
    d.ellipse([c - rm, c - rm, c + rm, c + rm], fill=(92, 54, 22))
    # sementes em espiral de ouro, mais claras no centro
    for i in range(420):
        dd = rm * 0.93 * math.sqrt(i / 420)
        a = i * 2.39996
        x, y = c + math.cos(a) * dd, c + math.sin(a) * dd
        t = dd / rm
        cor = (int(150 - 90 * t), int(96 - 60 * t), int(30 - 20 * t))
        s = tam * 0.0075 * (0.6 + 0.6 * t)
        d.ellipse([x - s, y - s, x + s, y + s], fill=cor)
    # brilho suave no miolo
    brilho = Image.new("RGBA", (tam, tam))
    ImageDraw.Draw(brilho).ellipse([c - rm * 0.7, c - rm * 0.85, c + rm * 0.1, c - rm * 0.15], fill=(255, 220, 160, 50))
    img.alpha_composite(brilho.filter(ImageFilter.GaussianBlur(tam * 0.02)))
    return img


def main():
    SAIDA.mkdir(parents=True, exist_ok=True)
    flor = girassol(int(S * 0.78))
    # sombra da flor
    sombra = Image.new("RGBA", (S, S))
    alfa = flor.split()[3].point(lambda v: v * 0.35)
    preta = Image.new("RGBA", flor.size, (0, 40, 20, 255))
    preta.putalpha(alfa)
    off = (S - flor.width) // 2
    sombra.alpha_composite(preta, (off, off + S // 40))
    sombra = sombra.filter(ImageFilter.GaussianBlur(S // 60))

    frente = Image.new("RGBA", (S, S))
    frente.alpha_composite(sombra)
    frente.alpha_composite(flor, (off, off))

    fundo = degrade(S, (52, 211, 153), (4, 120, 87)).convert("RGBA")
    brilho = Image.new("RGBA", (S, S))
    ImageDraw.Draw(brilho).ellipse([-S * 0.3, -S * 0.5, S * 1.0, S * 0.45], fill=(255, 255, 255, 40))
    fundo.alpha_composite(brilho.filter(ImageFilter.GaussianBlur(S // 20)))
    completo = fundo.copy()
    completo.alpha_composite(frente)

    completo.resize((FINAL, FINAL), Image.LANCZOS).save(SAIDA / "icone.png")
    # ícone adaptativo: a flor menor, dentro da zona segura de 66%
    seguro = Image.new("RGBA", (S, S))
    peq = frente.resize((int(S * 0.68), int(S * 0.68)), Image.LANCZOS)
    seguro.alpha_composite(peq, ((S - peq.width) // 2, (S - peq.height) // 2))
    seguro.resize((FINAL, FINAL), Image.LANCZOS).save(SAIDA / "frente.png")
    print("ok")


if __name__ == "__main__":
    main()
