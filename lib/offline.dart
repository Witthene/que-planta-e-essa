import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

// Modelo AIY Plants do Google: ~2100 espécies, roda no próprio celular.
// A classe 2101 é "fundo", ou seja, não é planta.
Interpreter? _modelo;
List<String>? _nomes;

/// 224x224 RGB em bytes corridos: o tflite copia direto, sem montar listas.
typedef Pixels = Uint8List;

/// Resultado do modelo: nome científico (null se não for planta), confiança
/// na espécie e o quanto o quadro parece "fundo" (0 a 1).
typedef Palpite = ({String? nome, double confianca, double fundo});

Future<void> carregarModelo() async {
  _modelo ??= await Interpreter.fromAsset('assets/plantas.tflite');
  if (_nomes != null) return;
  final csv = await rootBundle.loadString('assets/plantas.csv');
  final nomes = List.filled(2102, '');
  for (final linha in csv.split('\n').skip(1)) {
    final partes = linha.split(',');
    if (partes.length >= 2) nomes[int.parse(partes[0])] = partes.sublist(1).join(',').trim();
  }
  _nomes = nomes;
}

Palpite classificar(Pixels entrada) {
  final saida = Uint8List(2102);
  _modelo!.run(entrada, saida);
  var melhor = 0;
  for (var i = 1; i < 2101; i++) {
    if (saida[i] > saida[melhor]) melhor = i;
  }
  final fundo = saida[2101] / 255;
  final confianca = saida[melhor] / 255;
  return (nome: fundo > confianca ? null : _nomes![melhor], confianca: confianca, fundo: fundo);
}

/// Classifica uma foto salva.
Future<Palpite> classificarFoto(File foto) async {
  await carregarModelo();
  final imagem = img.bakeOrientation(img.decodeImage(await foto.readAsBytes())!);
  final q = img.copyResizeCropSquare(imagem, size: 224);
  return classificar(q.getBytes(order: img.ChannelOrder.rgb));
}

/// Só os bytes do quadro, para mandar a outra thread sem copiar o objeto da câmera.
typedef Quadro = ({
  int largura,
  int altura,
  Uint8List y,
  Uint8List u,
  Uint8List v,
  int linhaY,
  int linhaUV,
  int passoUV,
});

Quadro copiarQuadro(CameraImage im) => (
  largura: im.width,
  altura: im.height,
  y: im.planes[0].bytes,
  u: im.planes[1].bytes,
  v: im.planes[2].bytes,
  linhaY: im.planes[0].bytesPerRow,
  linhaUV: im.planes[1].bytesPerRow,
  passoUV: im.planes[1].bytesPerPixel ?? 1,
);

/// Converte e mede a nitidez numa thread separada, para o visor não travar.
Future<(Pixels, double)> prepararQuadro(CameraImage im) {
  final q = copiarQuadro(im);
  return Isolate.run(() => (quadroParaPixels(q), nitidez(q)));
}

/// Recorta o centro de um quadro YUV da câmera em 224x224 RGB, já girado 90°.
Pixels quadroParaPixels(Quadro im) {
  final lado = min(im.largura, im.altura);
  final x0 = (im.largura - lado) ~/ 2, y0 = (im.altura - lado) ~/ 2;
  final saida = Uint8List(224 * 224 * 3);
  int c(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.toInt());
  var k = 0;
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final sx = x0 + y * lado ~/ 224;
      final sy = y0 + (223 - x) * lado ~/ 224;
      final luz = im.y[sy * im.linhaY + sx].toDouble();
      final uv = (sy >> 1) * im.linhaUV + (sx >> 1) * im.passoUV;
      final u = im.u[uv] - 128, v = im.v[uv] - 128;
      saida[k++] = c(luz + 1.402 * v);
      saida[k++] = c(luz - 0.344 * u - 0.714 * v);
      saida[k++] = c(luz + 1.772 * u);
    }
  }
  return saida;
}

/// Nitidez do centro do quadro (variância do Laplaciano no brilho).
/// Imagem tremida ou fora de foco dá valor baixo.
double nitidez(Quadro im) {
  final b = im.y, linha = im.linhaY;
  final lado = min(im.largura, im.altura) ~/ 2;
  final x0 = (im.largura - lado) ~/ 2, y0 = (im.altura - lado) ~/ 2;
  var soma = 0.0, soma2 = 0.0, n = 0;
  for (var y = y0 + 2; y < y0 + lado - 2; y += 3) {
    for (var x = x0 + 2; x < x0 + lado - 2; x += 3) {
      final i = y * linha + x;
      final l = (b[i - 2] + b[i + 2] + b[i - 2 * linha] + b[i + 2 * linha] - 4 * b[i]).toDouble();
      soma += l;
      soma2 += l * l;
      n++;
    }
  }
  final media = soma / n;
  return soma2 / n - media * media;
}

/// Gera um recorte do centro da foto (a área do visor), para mandar junto.
Future<File> recortarCentro(File foto) async {
  final bytes = await compute((List<int> dados) {
    final imagem = img.bakeOrientation(img.decodeImage(Uint8List.fromList(dados))!);
    final lado = (min(imagem.width, imagem.height) * 0.75).round();
    final recorte = img.copyCrop(
      imagem,
      x: (imagem.width - lado) ~/ 2,
      y: (imagem.height - lado) ~/ 2,
      width: lado,
      height: lado,
    );
    final menor = lado > 1280 ? img.copyResize(recorte, width: 1280) : recorte;
    return img.encodeJpg(menor, quality: 90);
  }, await foto.readAsBytes());
  final saida = File('${foto.path}_centro.jpg');
  await saida.writeAsBytes(bytes);
  return saida;
}
