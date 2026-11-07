import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:town_pass/page/service_search/service_search_engine.dart';
import 'package:town_pass/page/service_search/service_search_index.dart';

/// 實驗：手機上的 EmbeddingGemma 2 Text 270M 語意搜尋，跟關鍵字模糊搜尋比較。
/// 文件只用每個服務的「標題＋說明」，不用手寫關键字，看語意本身能做到多少。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String revision = '9be6e8b90982095dc05c2bd162e4b954ee4dbac7';
  const List<String> queries = [
    'storm damage',
    'my employer hit me',
    'lost my passport',
    'where can i eat',
    'salary not paid',
    '颱風把招牌吹倒',
    '雇主打我',
    '護照不見了',
    'aku dipukul majikan',
    'đau bụng',
    'tree fallen',
    'ห้องละหมาด',
    '我收到罰單',
    'gaji tidak dibayar',
  ];

  double cosine(List<double> a, List<double> b) {
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return dot / (sqrt(na) * sqrt(nb));
  }

  testWidgets('semantic vs keyword search', (tester) async {
    await FlutterEdgeAi.initialize(embeddingBackends: const [LiteRtEmbeddingBackend()]);
    final Stopwatch install = Stopwatch()..start();
    await FlutterEdgeAi.installEmbedder()
        .modelFromNetwork('https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/resolve/$revision/embeddinggemma-2-text-270m.litertlm')
        .install();
    final EmbeddingModel embedder = await FlutterEdgeAi.getActiveEmbedder();
    // ignore: avoid_print
    print('PROBE install+load=${install.elapsedMilliseconds}ms');

    final Map<String, dynamic> json =
        jsonDecode(await rootBundle.loadString('assets/search/search_index.json')) as Map<String, dynamic>;
    final List<SearchEntry> entries = buildSearchEntries(json);
    final ServiceSearchEngine keyword = ServiceSearchEngine(entries);

    final Stopwatch docs = Stopwatch()..start();
    // A：只用標題＋說明。B：標題＋說明＋所有語言的關鍵字。
    final List<List<double>> docA = await embedder.embedAll(
      [for (final SearchEntry e in entries) EmbeddingInput.text('${e.title}：${e.description}')],
      taskType: TaskType.retrievalDocument,
    );
    final List<List<double>> docB = await embedder.embedAll(
      [for (final SearchEntry e in entries) EmbeddingInput.text('${e.title}：${e.description}。${e.keywords.join('、')}')],
      taskType: TaskType.retrievalDocument,
    );
    // ignore: avoid_print
    print('PROBE embed ${entries.length * 2} docs=${docs.elapsedMilliseconds}ms');

    String top(List<double> qv, List<List<double>> vs) {
      final List<MapEntry<SearchEntry, double>> ranked = [
        for (int i = 0; i < entries.length; i++) MapEntry(entries[i], cosine(qv, vs[i])),
      ]..sort((a, b) => b.value.compareTo(a.value));
      return ranked.take(3).map((m) => '${m.key.title}(${m.value.toStringAsFixed(2)})').join(' | ');
    }

    for (final String q in queries) {
      final List<double> qv = await embedder.embed(EmbeddingInput.text(q), taskType: TaskType.retrievalQuery);
      final List<SearchResult> kw = keyword.search(q);
      // ignore: avoid_print
      print('PROBE「$q」\n  A 說明: ${top(qv, docA)}\n  B 說明+關鍵字: ${top(qv, docB)}\n  關鍵字: ${kw.isEmpty ? '（找不到）' : kw.first.entry.title}');
    }
    await embedder.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
