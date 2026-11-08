import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/service_search/service_search_engine.dart';
import 'package:town_pass/page/service_search/service_search_index.dart';
import '../../integration_test/search_eval_data.dart';

/// 只測關鍵字搜尋（不需要模型，可在電腦上跑）：中英文評估題組的正確率與誤判。
void main() {
  final e = ServiceSearchEngine(buildSearchEntries(jsonDecode(File('assets/search/search_index.json').readAsStringSync())));
  for (final entry in {'中文': zhCases, 'English': enCases}.entries) {
    test('keyword eval ${entry.key}', () {
      int n = 0, top1 = 0, negOk = 0, neg = 0;
      final List<String> wrong = [];
      for (final c in entry.value) {
        final ids = e.search(c[0]).map((r) => r.entry.id).toList();
        if (c[1].isEmpty) {
          neg++;
          if (ids.isEmpty) negOk++; else wrong.add('${c[0]}（應找不到）→ ${ids.take(2).join(",")}');
          continue;
        }
        n++;
        final ok = c[1].split('|');
        if (ids.isNotEmpty && ok.contains(ids.first)) top1++; else wrong.add('${c[0]} → ${ids.isEmpty ? "找不到" : ids.first}');
      }
      // ignore: avoid_print
      print('KW ${entry.key}: 第1名 $top1/$n，無關查詢正確 $negOk/$neg\n  ${wrong.join("\n  ")}');
    });
  }
}
