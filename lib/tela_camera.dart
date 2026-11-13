import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cuidados.dart';
import 'main.dart';
import 'offline.dart';
import 'vidro.dart';

enum Estado { procurando, naoEPlanta, achou, carregando }

/// Câmera ao vivo: o modelo do celular olha os quadros e, quando tem certeza
/// de que é uma planta, tira a foto sozinho e abre o resultado.
class TelaCamera extends StatefulWidget {
  const TelaCamera({super.key});

  @override
  State<TelaCamera> createState() => _TelaCameraState();
}

class _TelaCameraState extends State<TelaCamera>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? camera;
  Estado estado = Estado.procurando;
  bool ocupado = false;
  DateTime ultimo = DateTime(0);
  String? candidato;
  int repeticoes = 0;
  late final pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    voz.falar(['Que planta é essa? Aponte a câmera para a planta.']);
    iniciar();
  }

  Future<void> iniciar() async {
    await carregarModelo();
    final cameras = await availableCameras();
    final traseira = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    // 720p: detalhe suficiente para o Pl@ntNet sem pesar no visor do celular.
    final c = CameraController(
      traseira,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await c.initialize();
    if (!mounted) return c.dispose();
    await focarCentro(c);
    setState(() => camera = c);
    retomar();
  }

  /// Foco e exposição automáticos no centro, onde fica o visor.
  Future<void> focarCentro(CameraController c) async {
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setFocusPoint(const Offset(0.5, 0.5));
      await c.setExposurePoint(const Offset(0.5, 0.5));
    } catch (_) {} // nem toda câmera aceita ponto de foco
  }

  void retomar() {
    candidato = null;
    repeticoes = 0;
    setState(() => estado = Estado.procurando);
    camera?.startImageStream(analisar);
  }

  /// Quadros seguidos parecendo planta e nítidos antes de tirar a foto.
  static const quadrosParaTravar = 3;

  /// Variância do Laplaciano abaixo disso = imagem tremida ou fora de foco.
  static const nitidezMinima = 60.0;

  Future<void> analisar(CameraImage quadro) async {
    if (ocupado || DateTime.now().difference(ultimo).inMilliseconds < 450) return;
    ocupado = true;
    ultimo = DateTime.now();
    try {
      final (pixels, nit) = await prepararQuadro(quadro);
      if (estado == Estado.carregando) return;
      final p = classificar(pixels);
      // Aqui o modelo do celular só decide "é planta?". Quem dá o nome é o Pl@ntNet.
      final ePlanta = p.nome != null && p.fundo < 0.35 && p.confianca >= 0.15;
      final nitida = nit >= nitidezMinima;
      final novo = ePlanta
          ? Estado.achou
          : p.fundo > 0.6
          ? Estado.naoEPlanta
          : Estado.procurando;
      if (novo != estado && mounted) setState(() => estado = novo);
      if (!ePlanta || !nitida) {
        repeticoes = 0;
        return;
      }
      repeticoes++;
      if (candidato == null || p.confianca > melhorConfianca) {
        candidato = p.nome;
        melhorConfianca = p.confianca;
      }
      if (repeticoes >= quadrosParaTravar) {
        travar(candidato);
        return; // travar() libera o ocupado quando terminar
      }
    } catch (_) {
      // quadro esquisito da câmera: ignora e espera o próximo
    }
    if (estado != Estado.carregando) ocupado = false;
  }

  double melhorConfianca = 0;

  /// Tira a foto e abre o resultado. Sem [cientifico] (disparo manual),
  /// o modelo do celular confere antes se é mesmo uma planta.
  Future<void> travar(String? cientifico) async {
    if (camera == null || estado == Estado.carregando) return;
    ocupado = true;
    setState(() => estado = Estado.carregando);
    voz.falar(['Deixa eu ver...']);
    if (camera!.value.isStreamingImages) await camera!.stopImageStream();
    await focarCentro(camera!);
    await Future.delayed(const Duration(milliseconds: 350)); // dá tempo do foco assentar
    final foto = File((await camera!.takePicture()).path);
    var confianca = melhorConfianca;
    if (cientifico == null) {
      final p = await classificarFoto(foto);
      if (p.nome == null || p.fundo > 0.5)
        return falhou('Isso não parece uma planta. Tente de novo.');
      cientifico = p.nome!;
      confianca = p.confianca;
    }
    Planta planta;
    try {
      final recorte = await recortarCentro(foto);
      planta = await identificarOnline([foto, recorte]).timeout(const Duration(seconds: 20));
    } on SemCerteza {
      return falhou(semCerteza);
    } catch (_) {
      // Sem internet: o modelo do celular só vale se estiver bem seguro.
      if (confianca < 0.5) return falhou(semCerteza);
      final genero = cientifico.split(' ').first;
      planta = montarPlanta(nomesPopulares[genero] ?? cientifico, cientifico, genero, '');
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TelaResultado(planta, foto)));
    ocupado = false;
    voz.falar(['Aponte para outra planta.']);
    retomar();
  }

  static const semCerteza = 'Não tenho certeza. Chegue mais perto da folha ou da flor.';

  void falhou(String frase) {
    voz.falar([frase]);
    ocupado = false;
    melhorConfianca = 0;
    retomar();
  }

  // Só em modo de teste: abre um resultado de exemplo sem precisar de planta.
  Future<void> abrirExemplo() async {
    const base = 'https://thumb.wikimedia.org/wikipedia/commons/thumb';
    final planta = Planta('Hibisco', 'Hibiscus rosa-sinensis', 3, 3, '')
      ..fotos = [
        '$base/3/36/Hibiscus_rosa-sinensis_blossom.jpg/960px-Hibiscus_rosa-sinensis_blossom.jpg',
        '$base/8/82/Hibiscus_rosa-sinensis_22.jpg/960px-Hibiscus_rosa-sinensis_22.jpg',
      ];
    await camera?.stopImageStream();
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TelaResultado(planta, null)));
    retomar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      camera?.dispose();
      setState(() => camera = null);
    } else if (s == AppLifecycleState.resumed && camera == null) {
      iniciar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    camera?.dispose();
    pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (cor, icone) = switch (estado) {
      Estado.procurando => (Colors.white, Icons.center_focus_strong_rounded),
      Estado.naoEPlanta => (const Color(0xFFCBD5E1), Icons.block_rounded),
      Estado.achou => (const Color(0xFF4ADE80), Icons.local_florist_rounded),
      Estado.carregando => (const Color(0xFF4ADE80), Icons.local_florist_rounded),
    };
    final c = camera;
    return Scaffold(
      body: DecoratedBox(
        decoration: fundoEscuro,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && c.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize!.height,
                  height: c.value.previewSize!.width,
                  child: CameraPreview(c),
                ),
              ),
            // Escurece as bordas para destacar o visor.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.95,
                  colors: [Colors.transparent, Color(0x99000000)],
                ),
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: Tween(
                  begin: 0.97,
                  end: 1.03,
                ).animate(CurvedAnimation(parent: pulso, curve: Curves.easeInOut)),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: cor),
                  duration: const Duration(milliseconds: 350),
                  builder: (_, c, _) =>
                      CustomPaint(size: const Size.square(270), painter: _Cantoneiras(c!)),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onLongPress: kDebugMode ? abrirExemplo : null,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.all(10),
                    decoration: cartaoBranco(22),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5), // emerald-50
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: const Text('🌻', style: TextStyle(fontSize: 32)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Aponte para a planta',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.6,
                                  height: 1.1,
                                  color: textoForte,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 34),
                  child: disparador(icone),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Disparador grande estilo iPhone: anel branco e miolo verde sólido.
  Widget disparador(IconData icone) => GestureDetector(
    onTap: () => travar(candidato),
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: verdeOk,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: estado == Estado.carregando
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(strokeWidth: 5, color: Colors.white),
              )
            : Icon(icone, size: 64, color: Colors.white),
      ),
    ),
  );
}

class _Cantoneiras extends CustomPainter {
  final Color cor;
  _Cantoneiras(this.cor);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);
    const l = 46.0, r = 26.0;
    final w = s.width, h = s.height;
    for (final (x, y, sx, sy) in [
      (0.0, 0.0, 1, 1),
      (w, 0.0, -1, 1),
      (0.0, h, 1, -1),
      (w, h, -1, -1),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + sy * l)
          ..lineTo(x, y + sy * r)
          ..arcToPoint(Offset(x + sx * r, y), radius: const Radius.circular(r), clockwise: sx == sy)
          ..lineTo(x + sx * l, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Cantoneiras old) => old.cor != cor;
}
