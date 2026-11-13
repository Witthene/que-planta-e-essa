import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'chave.dart';
import 'cuidados.dart';
import 'girassol.dart';
import 'tela_camera.dart';
import 'vidro.dart';
import 'voz.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  escolherVoz();
  runApp(const PlantinhaApp());
}

/// Escolhe a voz pt-BR mais natural do aparelho: as neurais do Google
/// (marcadas como "network") soam bem mais humanas que a voz padrão.
Future<void> escolherVoz() async {
  await voz.tts.setLanguage('pt-BR');
  await voz.tts.awaitSpeakCompletion(false);
  final vozes = [
    for (final v in (await voz.tts.getVoices as List? ?? []))
      if ('${v['locale']}'.toLowerCase().replaceAll('_', '-').startsWith('pt-br'))
        Map<String, String>.from((v as Map).map((k, v) => MapEntry('$k', '$v'))),
  ];
  if (vozes.isEmpty) return;
  int nota(Map<String, String> v) {
    final nome = v['name']!.toLowerCase();
    return (nome.contains('network') ? 4 : 0) +
        (v['quality'] == 'very high' || v['quality'] == '500' ? 2 : 0) +
        (nome.contains('local') ? 1 : 0);
  }

  vozes.sort((a, b) => nota(b).compareTo(nota(a)));
  debugPrint('VOZES: ${vozes.map((v) => v['name']).join(', ')}');
  await voz.tts.setVoice({'name': vozes.first['name']!, 'locale': vozes.first['locale']!});
  await voz.tts.setSpeechRate(0.47);
  await voz.tts.setPitch(1.05);
}

class PlantinhaApp extends StatelessWidget {
  const PlantinhaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Que Planta É Essa?',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: verdeOk),
      scaffoldBackgroundColor: fundoClaro,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
    ),
    home: const TelaCamera(),
  );
}

final voz = Voz();

class Planta {
  final String nome;
  final String nomeCientifico;
  final int agua; // 1 a 3
  final int sol; // 1 a 3
  final String frase;
  List<String> fotos = [];
  String curiosidade = '';

  Planta(this.nome, this.nomeCientifico, this.agua, this.sol, this.frase);

  bool get venenosa => frase.startsWith('Cuidado');
}

const fundo = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF3C4), creme, Color(0xFFE9F2DF)],
  ),
);

class TelaResultado extends StatefulWidget {
  final Planta planta;
  final File? fotoTirada;

  const TelaResultado(this.planta, this.fotoTirada, {super.key});

  @override
  State<TelaResultado> createState() => _TelaResultadoState();
}

class _TelaResultadoState extends State<TelaResultado> with SingleTickerProviderStateMixin {
  int pagina = 0;
  // Brilho pulsante das gotas quando a planta pede água.
  late final pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat(reverse: true);

  @override
  void dispose() {
    paginas.dispose();
    pulso.dispose();
    super.dispose();
  }

  Planta get planta => widget.planta;

  @override
  void initState() {
    super.initState();
    falar();
  }

  void falar() {
    const agua = ['', 'pouca água', 'água de vez em quando', 'bastante água'];
    const sol = ['', 'sombra', 'um pouco de sol', 'muito sol'];
    voz.falar([
      'Essa planta se chama ${planta.nome}.',
      'Ela gosta de ${agua[planta.agua]} e de ${sol[planta.sol]}.',
      planta.frase,
      if (planta.curiosidade.isNotEmpty) 'Uma curiosidade:',
      planta.curiosidade,
    ]);
  }

  final paginas = PageController();

  Widget imagem(int i, {int? largura}) {
    if (widget.fotoTirada != null) {
      if (i == 0) {
        return Image.file(widget.fotoTirada!, fit: BoxFit.cover, cacheWidth: largura ?? 1080);
      }
      i--;
    }
    return Image.network(
      planta.fotos[i],
      headers: const {'User-Agent': 'QuePlantaEEssa/1.0 (app Android)'},
      cacheWidth: largura,
      fit: BoxFit.cover,
      loadingBuilder: (_, filho, p) => p == null ? filho : const ColoredBox(color: bordaClara),
      errorBuilder: (_, _, _) => const ColoredBox(
        color: bordaClara,
        child: Center(child: Girassol(tamanho: 90)),
      ),
    );
  }

  static const textoAgua = ['', 'Pouca água', 'Água média', 'Muita água'];
  static const textoSol = ['', 'Sombra', 'Meia-sombra', 'Muito sol'];

  TextStyle forte(double tamanho, [Color cor = textoForte]) => GoogleFonts.plusJakartaSans(
    fontSize: tamanho,
    fontWeight: FontWeight.w800,
    color: cor,
    letterSpacing: -0.3,
  );

  /// Card branco com três ícones preenchidos e a legenda em negrito.
  Widget cuidado(IconData icone, int valor, Color cor, String legenda, {bool pulsar = false}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        decoration: cartaoBranco(),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: ScaleTransition(
                      scale: pulsar && i < valor
                          ? Tween(
                              begin: 1.0,
                              end: 1.1,
                            ).animate(CurvedAnimation(parent: pulso, curve: Curves.easeInOut))
                          : const AlwaysStoppedAnimation(1.0),
                      child: Icon(icone, size: 64, color: i < valor ? cor : bordaClara),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(legenda, style: forte(24)),
          ],
        ),
      );

  /// Selo de semáforo: verde se é segura, vermelho se é venenosa.
  Widget selo() => Container(
    width: 64,
    height: 64,
    decoration: BoxDecoration(
      color: planta.venenosa ? vermelho : verdeOk,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: (planta.venenosa ? vermelho : verdeOk).withValues(alpha: 0.35),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Icon(
      planta.venenosa ? Icons.warning_rounded : Icons.check_rounded,
      size: 40,
      color: Colors.white,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final total = planta.fotos.length + (widget.fotoTirada != null ? 1 : 0);
    final tela = MediaQuery.sizeOf(context).height;
    final altura = tela * 0.34;
    return Scaffold(
      backgroundColor: fundoClaro,
      body: Stack(
        children: [
          SizedBox(
            height: altura + 40,
            child: PageView.builder(
              controller: paginas,
              itemCount: total,
              onPageChanged: (p) => setState(() => pagina = p),
              itemBuilder: (_, i) => imagem(i),
            ),
          ),
          ListView(
            padding: EdgeInsets.only(top: altura - 20),
            children: [
              Container(
                constraints: BoxConstraints(minHeight: tela - altura + 20),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 170),
                decoration: const BoxDecoration(
                  color: fundoClaro,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (total > 1)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            total,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == pagina ? 26 : 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: i == pagina ? textoForte : const Color(0xFFCBD5E1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 14),
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      decoration: cartaoBranco(),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5), // emerald-50
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: const Text('🌺', style: TextStyle(fontSize: 36)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PLANTA IDENTIFICADA',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: const Color(0xFF94A3B8), // slate-400
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  planta.nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 29, // text-2xl com o aumento de 20%
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.6,
                                    height: 1.1,
                                    color: textoForte,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          selo(),
                        ],
                      ),
                    ),
                    if (total > 1) miniaturas(total),
                    cuidado(
                      Icons.water_drop_rounded,
                      planta.agua,
                      azulForte,
                      textoAgua[planta.agua],
                      pulsar: planta.agua >= 2,
                    ),
                    cuidado(Icons.wb_sunny_rounded, planta.sol, laranjaSol, textoSol[planta.sol]),
                    if (planta.venenosa)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: cartaoBranco().copyWith(
                          border: Border.all(color: vermelho, width: 3),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.dangerous_rounded, size: 60, color: vermelho),
                            const SizedBox(width: 12),
                            Text('Venenosa', style: forte(29, vermelho)),
                          ],
                        ),
                      ),
                    if (planta.curiosidade.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: cartaoBranco(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.lightbulb_rounded, size: 40, color: laranjaSol),
                                const SizedBox(width: 10),
                                Text('Você sabia?', style: forte(26)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              planta.curiosidade,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                color: textoForte,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: GestureDetector(
                onTap: voltar,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: cartaoBranco(32),
                  child: const Icon(Icons.arrow_back_rounded, size: 36, color: textoForte),
                ),
              ),
            ),
          ),
          // Barra inferior: "Ouvir" em destaque e a câmera ao lado.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: bordaClara)),
                boxShadow: [
                  BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: bloco(
                          verdeOk,
                          falar,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.volume_up_rounded, size: 58, color: Colors.white),
                              const SizedBox(width: 12),
                              Text('Ouvir', style: forte(32, Colors.white)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 104,
                        child: bloco(
                          azulForte,
                          voltar,
                          const Icon(Icons.photo_camera_rounded, size: 50, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fotos grandes da planta lado a lado; tocar numa mostra ela lá em cima.
  Widget miniaturas(int total) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    decoration: cartaoBranco(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fotos dessa planta', style: forte(24)),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: total,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => paginas.animateToPage(
                i,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: i == pagina ? verdeOk : bordaClara, width: 4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: imagem(i, largura: 300),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// Bloco sólido grande para tocar sem erro.
  Widget bloco(Color cor, VoidCallback acao, Widget conteudo) => Material(
    color: cor,
    borderRadius: BorderRadius.circular(26),
    elevation: 3,
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: acao,
      child: SizedBox(height: 100, child: Center(child: conteudo)),
    ),
  );
  void voltar() {
    voz.parar();
    Navigator.pop(context);
  }
}

Planta montarPlanta(String nome, String cientifico, String genero, String familia) {
  final c = cuidadosDe(genero, familia);
  return Planta(
    nome[0].toUpperCase() + nome.substring(1),
    cientifico,
    c[0],
    c[1],
    c[2] == 1 ? 'Cuidado: essa planta é venenosa. Não coma e lave as mãos.' : '',
  );
}

/// O Pl@ntNet respondeu, mas não tem segurança suficiente para dar um nome.
class SemCerteza implements Exception {}

/// Abaixo disso o Pl@ntNet costuma errar a espécie; aí o app sobe para o
/// gênero ou a família, e se nem assim tiver certeza pede outra foto.
const confiancaEspecie = 0.35;
const confiancaFamilia = 0.5;

/// Nome falado quando só dá para ter certeza da família.
const nomesFamilia = {
  'Cactaceae': 'cacto',
  'Crassulaceae': 'suculenta',
  'Orchidaceae': 'orquídea',
  'Bromeliaceae': 'bromélia',
  'Arecaceae': 'palmeira',
  'Poaceae': 'capim',
  'Polypodiaceae': 'samambaia',
  'Pteridaceae': 'samambaia',
};

/// Identifica pelo Pl@ntNet. Mandar mais de uma foto da mesma planta (ex.: a
/// foto inteira e um recorte do visor) aumenta bastante a precisão.
Future<Planta> identificarOnline(List<File> fotos) async {
  final req = http.MultipartRequest(
    'POST',
    Uri.https('my-api.plantnet.org', '/v2/identify/all', {
      'api-key': plantnetKey,
      'lang': 'pt',
      'include-related-images': 'true',
      'nb-results': '10',
    }),
  );
  for (final f in fotos) {
    req.files.add(await http.MultipartFile.fromPath('images', f.path));
    req.files.add(http.MultipartFile.fromString('organs', 'auto'));
  }
  final resp = await http.Response.fromStream(await req.send());
  // 404 = nenhuma espécie encontrada (não é falta de internet).
  if (resp.statusCode == 404) throw SemCerteza();
  if (resp.statusCode != 200) throw http.ClientException('Pl@ntNet ${resp.statusCode}');
  final resultados = jsonDecode(utf8.decode(resp.bodyBytes))['results'] as List;
  if (resultados.isEmpty) throw SemCerteza();
  final melhor = resultados.first;
  final especie = melhor['species'];
  var nomes = (especie['commonNames'] as List?) ?? [];
  var cientifico = especie['scientificNameWithoutAuthor'] as String;
  final genero = especie['genus']['scientificNameWithoutAuthor'] as String;
  final familia = especie['family']['scientificNameWithoutAuthor'] as String;
  // Espécies parecidas (cactos, suculentas) dividem a nota entre si. Somando
  // por gênero e família, dá para dizer "é um cacto" em vez de chutar a espécie.
  double soma(String nivel, String nome) => resultados
      .where((r) => r['species'][nivel]['scientificNameWithoutAuthor'] == nome)
      .fold(0.0, (s, r) => s + (r['score'] as num));
  if ((melhor['score'] as num) < confiancaEspecie) {
    if (soma('genus', genero) >= confiancaEspecie) {
      cientifico = genero;
      nomes = [];
    } else if (soma('family', familia) >= confiancaFamilia && nomesFamilia[familia] != null) {
      final planta = montarPlanta(nomesFamilia[familia]!, familia, '', familia);
      planta.fotos = [
        for (final img in (melhor['images'] as List? ?? []).take(6)) img['url']['m'] as String,
      ];
      planta.curiosidade = (await buscarWikipedia(familia))?.curiosidade ?? '';
      voz.preparar([planta.curiosidade]);
      return planta;
    } else {
      throw SemCerteza();
    }
  }
  final wiki = await buscarWikipedia(cientifico);
  // Nome popular: a tabela (nomes do dia a dia, já gravados com a voz da Yui),
  // depois o artigo da Wikipédia e por último o que o Pl@ntNet sugerir.
  final nome =
      nomesPopulares[cientifico] ??
      nomesPopulares[genero] ??
      // Cactos e afins: a espécie engana até o Pl@ntNet, a família não.
      nomesFamilia[familia] ??
      wiki?.nome ??
      (nomes.isNotEmpty ? arrumarNome(nomes.first as String) : cientifico);
  final planta = montarPlanta(nome, cientifico, genero, familia);
  planta.fotos = [
    for (final img in (melhor['images'] as List? ?? []).take(6)) img['url']['m'] as String,
    if (wiki?.foto != null) wiki!.foto!,
  ];
  planta.curiosidade = wiki?.curiosidade ?? '';
  voz.preparar(['Essa planta se chama ${planta.nome}.', planta.curiosidade]);
  return planta;
}

/// O Pl@ntNet manda nomes como "Mimo de-vênus"; vira "mimo-de-vênus".
String arrumarNome(String n) => n.contains('-') ? n.replaceAll(' ', '-') : n;

/// Nome popular, uma curiosidade curta e uma foto do artigo da Wikipédia em português.
Future<({String? nome, String curiosidade, String? foto})?> buscarWikipedia(
  String cientifico,
) async {
  try {
    final r = await http
        .get(
          Uri.https(
            'pt.wikipedia.org',
            '/api/rest_v1/page/summary/${cientifico.replaceAll(' ', '_')}',
          ),
          headers: {'Api-User-Agent': 'QuePlantaEEssa/1.0 (app Android)'},
        )
        .timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j['type'] != 'standard') return null;
    final texto = (j['extract'] as String? ?? '').replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    final frases = [
      for (final f in texto.split(RegExp(r'(?<=[.!?])\s+(?=[A-ZÁÉÍÓÚÂÊÔÃÕ])')))
        if (f.length > 25) f.trim(),
    ];
    // "O mimo-de-vênus, também conhecido por hibisco, ..." → o primeiro nome.
    String? nome;
    final titulo = (j['title'] as String).replaceAll(RegExp(r'\s*\(.*\)'), '');
    if (titulo.toLowerCase() != cientifico.toLowerCase()) nome = titulo;
    if (nome == null && frases.isNotEmpty) {
      final m = RegExp(r'^(?:[OA]s?|Um|Uma)\s+([a-zà-ú][a-zà-ú\- ]{2,30}?)[,(]').firstMatch(frases[0]);
      if (m != null && !m[1]!.contains(' é ')) nome = m[1]!.trim();
    }
    // Curiosidade: a primeira frase curta depois da definição; senão a própria definição.
    final resto = frases.skip(1).where((f) => f.length <= 220).toList();
    var curiosidade = resto.isNotEmpty ? resto.first : (frases.isNotEmpty ? frases.first : '');
    if (curiosidade.length > 260) curiosidade = '${curiosidade.substring(0, 257).trimRight()}...';
    return (nome: nome, curiosidade: curiosidade, foto: j['thumbnail']?['source'] as String?);
  } catch (_) {
    return null;
  }
}
