import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:town_pass/page/service_search/semantic_search.dart';
import 'package:town_pass/page/service_search/service_search_engine.dart';
import 'package:town_pass/page/service_search/service_search_index.dart';

import 'search_eval_data.dart';

/// 搜尋評估：關鍵字、語意、混合（畫面上的排序：關鍵字結果在前，語意補在後）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  double cosine(List<double> a, List<double> b) {
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return dot / (sqrt(na) * sqrt(nb));
  }

  testWidgets('search eval', (tester) async {
    await FlutterEdgeAi.initialize(embeddingBackends: const [LiteRtEmbeddingBackend()]);
    await FlutterEdgeAi.installEmbedder().fromCatalog(LiteRtEmbedders.embeddinggemma2Text270m.generic).install();
    final EmbeddingModel embedder = await FlutterEdgeAi.getActiveEmbedder();

    final Map<String, dynamic> json =
        jsonDecode(await rootBundle.loadString('assets/search/search_index.json')) as Map<String, dynamic>;
    final List<SearchEntry> entries = buildSearchEntries(json);
    final ServiceSearchEngine keyword = ServiceSearchEngine(entries);
    final List<List<double>> docs = await embedder.embedAll(
      [for (final SearchEntry e in entries) EmbeddingInput.text(SemanticSearch.documentText(e))],
      taskType: TaskType.retrievalDocument,
    );

    Future<void> run(String label, List<List<String>> cases) async {
      int n = 0, kw1 = 0, kw3 = 0, kwNone = 0, sem1 = 0, sem3 = 0, hy1 = 0, hy3 = 0;
      int neg = 0, negKwClean = 0;
      final List<String> semTopScores = [];
      final StringBuffer fails = StringBuffer();
      final StringBuffer kwWrong = StringBuffer();
      final List<double> posTop = [];
      for (final List<String> c in cases) {
        final String q = c[0];
        final Set<String> ok = c[1].isEmpty ? <String>{} : c[1].split('|').toSet();
        final List<String> kw = keyword.search(q).map((r) => r.entry.id).toList();
        final List<double> qv = await embedder.embed(EmbeddingInput.text(q), taskType: TaskType.retrievalQuery);
        final List<MapEntry<String, double>> sem = [
          for (int i = 0; i < entries.length; i++) MapEntry(entries[i].id, cosine(qv, docs[i])),
        ]..sort((a, b) => b.value.compareTo(a.value));
        final List<String> semIds = sem.map((e) => e.key).toList();
        // 畫面順序：關鍵字（最多 5）＋語意補 3 個不重複的。
        final List<String> shown = [...kw.take(5)];
        for (final String id in semIds) {
          if (shown.length >= kw.take(5).length + 3) break;
          if (!shown.contains(id)) shown.add(id);
        }
        if (ok.isEmpty) {
          neg++;
          if (kw.isEmpty) negKwClean++;
          if (kw.isNotEmpty) kwWrong.writeln('  ! $q（應找不到）→ 關鍵字 ${kw.take(3).join(",")}');
          semTopScores.add('$q=${sem.first.value.toStringAsFixed(2)}');
          continue;
        }
        n++;
        if (kw.isEmpty) kwNone++;
        if (kw.isNotEmpty && ok.contains(kw.first)) kw1++;
        if (kw.isNotEmpty && !ok.contains(kw.first)) {
          kwWrong.writeln('  ! $q → 關鍵字第1名 ${kw.first}（期望 ${ok.join("/")}）');
        }
        posTop.add(sem.first.value);
        if (kw.take(3).any(ok.contains)) kw3++;
        if (ok.contains(semIds.first)) sem1++;
        if (semIds.take(3).any(ok.contains)) sem3++;
        if (ok.contains(shown.first)) hy1++;
        final bool hyHit = shown.take(3).any(ok.contains);
        if (hyHit) hy3++;
        if (!hyHit) {
          fails.writeln('  ✗ $q → 期望 ${ok.join("/")}；關鍵字 ${kw.take(3).join(",")}；語意 ${sem.take(3).map((e) => "${e.key}(${e.value.toStringAsFixed(2)})").join(",")}');
        }
      }
      String pct(int x) => '$x/$n (${(100 * x / n).round()}%)';
      // ignore: avoid_print
      print('EVAL [$label] $n 題\n'
          '  關鍵字 第1名 ${pct(kw1)}、前3名 ${pct(kw3)}、找不到 ${pct(kwNone)}\n'
          '  語意   第1名 ${pct(sem1)}、前3名 ${pct(sem3)}\n'
          '  混合   第1名 ${pct(hy1)}、前3名 ${pct(hy3)}\n'
          '  無關查詢 $neg 題：關鍵字正確回傳空 $negKwClean/$neg；語意第1名分數 ${semTopScores.join("、")}\n'
          '  混合前3名沒找到的：\n$fails'
          '  關鍵字第1名錯的：\n$kwWrong'
          '  有答案的查詢，語意第1名分數：最低 ${posTop.reduce(min).toStringAsFixed(2)}、最高 ${posTop.reduce(max).toStringAsFixed(2)}');
    }

    await run('中文', zhCases);
    await run('English', enCases);
    await embedder.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
