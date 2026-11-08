import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/service_search/service_search_engine.dart';

/// 移工微服務（TownPass-Services）的網址。
/// 部署後以 `--dart-define=MIGRANT_SERVICE_URL=https://...` 指定；未指定時用本機開發伺服器。
const String migrantServiceBaseUrl = String.fromEnvironment(
  'MIGRANT_SERVICE_URL',
  defaultValue: 'https://town-pass-services.vercel.app',
);

/// 讀取 `assets/search/search_index.json`，組成搜尋用的資料：
/// - App 內建服務：標題、說明直接取自 [MyServiceItemId]，再加上索引檔裡的同義詞。
/// - 微服務頁面：索引檔裡的 `microservice` 清單。
Future<List<SearchEntry>> loadSearchEntries() async {
  final Map<String, dynamic> json =
      jsonDecode(await rootBundle.loadString('assets/search/search_index.json')) as Map<String, dynamic>;
  return buildSearchEntries(json);
}

List<SearchEntry> buildSearchEntries(Map<String, dynamic> json) {
  final Map<String, dynamic> appKeywords = (json['appServices'] as Map<String, dynamic>?) ?? {};
  return [
    for (final MyServiceItemId id in MyServiceItemId.values)
      SearchEntry(
        id: 'app-${id.name}',
        title: id.item.title,
        description: id.item.description,
        keywords: _flatten(appKeywords[id.name]),
        serviceId: id.name,
      ),
    for (final dynamic raw in (json['microservice'] as List<dynamic>? ?? const []))
      SearchEntry(
        id: raw['id'] as String,
        title: raw['title'] as String,
        description: (raw['description'] as String?) ?? '',
        keywords: _flatten(raw['keywords']),
        path: raw['path'] as String,
      ),
  ];
}

List<String> _flatten(dynamic byLanguage) {
  if (byLanguage is! Map) {
    return const [];
  }
  return [
    for (final dynamic words in byLanguage.values)
      if (words is List) ...words.whereType<String>(),
  ];
}
