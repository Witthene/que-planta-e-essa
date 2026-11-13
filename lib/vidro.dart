import 'dart:ui';

import 'package:flutter/material.dart';

/// Superfície de vidro fosco (glassmorphism). Os padrões equivalem a
/// `bg-white/10 backdrop-blur-xl border border-white/20`.
class Vidro extends StatelessWidget {
  final Widget child;
  final BorderRadius raio;
  final bool circulo;
  final EdgeInsetsGeometry padding;
  final Color cor;
  final double blur;
  final Color borda;
  final List<BoxShadow> sombra;
  final VoidCallback? aoTocar;

  const Vidro({
    super.key,
    required this.child,
    this.raio = const BorderRadius.all(Radius.circular(28)),
    this.circulo = false,
    this.padding = EdgeInsets.zero,
    this.cor = const Color(0x1AFFFFFF),
    this.blur = 12,
    this.borda = const Color(0x33FFFFFF),
    this.sombra = const [],
    this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final forma = circulo
        ? const BoxDecoration(shape: BoxShape.circle)
        : BoxDecoration(borderRadius: raio);
    final painel = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        padding: padding,
        decoration: forma.copyWith(
          color: cor,
          border: Border.all(color: borda, width: 1),
          // Reflexo suave de luz vindo de cima.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.alphaBlend(const Color(0x14FFFFFF), cor), cor],
            stops: const [0, 0.6],
          ),
        ),
        child: child,
      ),
    );
    Widget w = DecoratedBox(
      decoration: forma.copyWith(boxShadow: sombra),
      child: circulo ? ClipOval(child: painel) : ClipRRect(borderRadius: raio, child: painel),
    );
    if (aoTocar != null) {
      w = GestureDetector(
        onTap: aoTocar,
        child: _Apertavel(child: w),
      );
    }
    return w;
  }
}

/// Encolhe um pouquinho ao apertar, como os botões do iOS.
class _Apertavel extends StatefulWidget {
  final Widget child;
  const _Apertavel({required this.child});

  @override
  State<_Apertavel> createState() => _ApertavelState();
}

class _ApertavelState extends State<_Apertavel> {
  bool apertado = false;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => apertado = true),
    onPointerUp: (_) => setState(() => apertado = false),
    onPointerCancel: (_) => setState(() => apertado = false),
    child: AnimatedScale(
      scale: apertado ? 0.93 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

/// Fundo global: `bg-gradient-to-b from-neutral-950 via-zinc-900 to-emerald-950/60`.
const fundoEscuro = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A0A0A), Color(0xFF18181B), Color(0xFF0B2A21)],
  ),
);

const ciano = Color(0xFF22D3EE);
const ambar = Color(0xFFFBBF24);
const esmeralda = Color(0xFF34D399);
const esmeraldaEscura = Color(0xFF047857);

// Paleta clara de alto contraste (Senior-Friendly).
const fundoClaro = Color(0xFFF5F5F4); // stone-100
const textoForte = Color(0xFF0F172A); // slate-900
const bordaClara = Color(0xFFE2E8F0); // slate-200
const azulForte = Color(0xFF2563EB);
const laranjaSol = Color(0xFFF59E0B);
const verdeOk = Color(0xFF16A34A);
const vermelho = Color(0xFFDC2626);

/// Card branco sólido: `bg-white border border-slate-200 shadow-md`.
BoxDecoration cartaoBranco([double raio = 24]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(raio),
  border: Border.all(color: bordaClara),
  boxShadow: const [
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 2)),
  ],
);
