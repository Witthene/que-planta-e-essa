import 'dart:math';

import 'package:flutter/material.dart';

// Paleta do app.
const amarelo = Color(0xFFF9B826);
const mel = Color(0xFFE8890C);
const folha = Color(0xFF2F6B3A);
const terra = Color(0xFF5B3A1E);
const creme = Color(0xFFFFF8E7);

/// Girassol desenhado à mão (pétalas em volta de um miolo pontilhado).
class Girassol extends StatelessWidget {
  final double tamanho;
  const Girassol({super.key, this.tamanho = 200});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(tamanho), painter: _GirassolPainter());
}

class _GirassolPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    void petalas(int n, double giro, Color cor) {
      final p = Paint()..color = cor;
      for (var i = 0; i < n; i++) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(2 * pi * i / n + giro);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, -r * 0.62), width: r * 0.34, height: r * 0.72),
          p,
        );
        canvas.restore();
      }
    }

    petalas(16, pi / 16, mel);
    petalas(16, 0, amarelo);
    canvas.drawCircle(c, r * 0.4, Paint()..color = terra);
    final ponto = Paint()..color = const Color(0xFF3B2412);
    for (var i = 0; i < 60; i++) {
      final d = r * 0.36 * sqrt(i / 60);
      final a = i * 2.39996; // ângulo de ouro, como no miolo de verdade
      canvas.drawCircle(c + Offset(cos(a) * d, sin(a) * d), r * 0.025, ponto);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const papel = Color(0xFFFAF6EE);
const tinta = Color(0xFF2A2118);
const azul = Color(0xFF2F8FE0);
const perigo = Color(0xFFE5483B);
