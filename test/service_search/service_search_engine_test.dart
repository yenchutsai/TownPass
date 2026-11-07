import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/service_search/service_search_engine.dart';
import 'package:town_pass/page/service_search/service_search_index.dart';

void main() {
  late ServiceSearchEngine engine;

  setUpAll(() {
    final Map<String, dynamic> json =
        jsonDecode(File('assets/search/search_index.json').readAsStringSync()) as Map<String, dynamic>;
    engine = ServiceSearchEngine(buildSearchEntries(json));
  });

  String? top(String q) {
    final results = engine.search(q);
    return results.isEmpty ? null : results.first.entry.id;
  }

  // [查詢, 預期第一名]
  const List<List<String>> cases = [
    // 中文：完全符合、生活說法、一句話、錯一個字
    ['災情通報', 'app-disasterReport'],
    ['樹倒了', 'app-disasterReport'],
    ['我收到罰單', 'app-districtOffice'],
    ['老闆欠薪', 'migrant-phone'],
    ['我的老闆欠薪水', 'migrant-phone'],
    ['祈禱室', 'migrant-living-map'],
    ['看醫生', 'app-medicalAppointment'],
    ['叫號', 'app-reservation'],
    ['借書', 'app-library'],
    // 全形、大小寫
    ['ＬＩＮＥ', 'migrant-line'],
    ['line', 'migrant-line'],
    // 印尼文、拼錯
    ['musholla', 'migrant-living-map'],
    ['mushola', 'migrant-living-map'],
    ['musola', 'migrant-living-map'],
    ['gaji tidak dibayar', 'migrant-phone'],
    ['dokter', 'app-medicalAppointment'],
    // 越南文：有聲調、沒聲調
    ['phòng cầu nguyện', 'migrant-living-map'],
    ['phong cau nguyen', 'migrant-living-map'],
    ['no luong', 'migrant-phone'],
    ['bệnh viện', 'app-medicalAppointment'],
    // 泰文
    ['ห้องละหมาด', 'migrant-living-map'],
    ['ฮาลาล', 'migrant-living-map'],
    ['สายด่วนแรงงาน', 'migrant-phone'],
    // 英文、菲律賓文、拼錯
    ['halal', 'migrant-living-map'],
    ['prayer rom', 'migrant-living-map'],
    ['hospitl', 'app-medicalAppointment'],
    ['pulis', 'app-police'],
    ['1955', 'migrant-phone'],
  ];

  for (final c in cases) {
    test('「${c[0]}」→ ${c[1]}', () {
      expect(top(c[0]), c[1], reason: engine.search(c[0]).take(3).map((r) => '${r.entry.id}:${r.score.toStringAsFixed(0)}').join(', '));
    });
  }

  test('空白輸入沒有結果', () {
    expect(engine.search('   '), isEmpty);
  });

  test('無關的字沒有結果', () {
    expect(engine.search('xyzqwv'), isEmpty);
    expect(engine.search('飛機票'), isEmpty);
  });

  test('normalize 去聲調、全形轉半形、去空白', () {
    expect(ServiceSearchEngine.normalize('Phòng  Cầu Nguyện'), 'phongcaunguyen');
    expect(ServiceSearchEngine.normalize('ＬＩＮＥ！'), 'line');
    expect(ServiceSearchEngine.normalize('Đường dây'), 'duongday');
  });
}
