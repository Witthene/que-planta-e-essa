import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Fala frases com os áudios gravados (voz da Yui, em assets/vozes). Frase que
/// não foi gravada (nome de planta, curiosidade) é gerada na hora pelo Fish
/// Audio e guardada no celular; a voz do aparelho só entra se o Fish falhar.
class Voz {
  final _player = AudioPlayer();
  final tts = FlutterTts();
  Set<String>? _gravadas;
  int _vez = 0;

  /// Mesmo hash FNV-1a do tools/gerar_vozes.py.
  static String chave(String texto) {
    var h = 0x811C9DC5;
    for (final b in utf8.encode(texto.trim().toLowerCase())) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return 'v_${h.toRadixString(16).padLeft(8, '0')}';
  }

  Future<Set<String>> _lista() async => _gravadas ??= {
    for (final a in (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets())
      if (a.startsWith('assets/vozes/')) a.split('/').last.replaceAll('.mp3', ''),
  };

  /// Frase sem gravação vai direto pra voz do aparelho.
  Future<File?> _gerar(String texto) async => null;

  /// Começa a gerar as frases antes de precisar delas, para não ter espera.
  Future<void> preparar(List<String> frases) async {
    final gravadas = await _lista();
    for (final f in frases.where((f) => f.trim().isNotEmpty)) {
      if (!gravadas.contains(chave(f))) _gerar(f);
    }
  }

  /// Fala as frases em sequência; uma chamada nova interrompe a anterior.
  Future<void> falar(List<String> frases) async {
    final vez = ++_vez;
    await parar(manterVez: true);
    final gravadas = await _lista();
    final lista = frases.where((f) => f.trim().isNotEmpty).toList();
    // Dispara todas as gerações juntas; toca na ordem conforme ficam prontas.
    final audios = [
      for (final f in lista) gravadas.contains(chave(f)) ? null : _gerar(f),
    ];
    for (var i = 0; i < lista.length; i++) {
      if (vez != _vez) return;
      final k = chave(lista[i]);
      if (audios[i] == null) {
        await _player.play(AssetSource('vozes/$k.mp3'));
        await _player.onPlayerComplete.first;
        continue;
      }
      final arq = await audios[i];
      if (vez != _vez) return;
      if (arq != null) {
        await _player.play(DeviceFileSource(arq.path));
        await _player.onPlayerComplete.first;
      } else {
        await tts.awaitSpeakCompletion(true);
        await tts.speak(lista[i]);
      }
    }
  }

  Future<void> parar({bool manterVez = false}) async {
    if (!manterVez) _vez++;
    await _player.stop();
    await tts.stop();
  }
}
