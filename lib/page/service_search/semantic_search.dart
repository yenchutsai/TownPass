import 'dart:io';
import 'dart:math';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:town_pass/page/service_search/service_search_engine.dart';
import 'package:town_pass/page/service_search/service_search_index.dart';

/// 手機上的語意搜尋：比的是「意思」而不是字面，例如「雇主打我」「đau bụng」。
///
/// 模型：EmbeddingGemma 2 Text 270M（Apache-2.0），LiteRT-LM 格式，約 165 MB，
/// 來源 Hugging Face `litert-community/embeddinggemma-2-text-270m-litert-lm`（固定版本與 SHA-256）。
/// 只把文字轉成向量，不生成文字；所有計算都在手機上，查詢內容不會傳出去。
///
/// 預設開啟：App 啟動後在背景下載（第一次約 165 MB）並載入，之後離線可用。
/// 若手機的 Documents/preloaded/ 已放好模型檔，直接使用，不必下載（Demo 用）。
/// 只有模型無法使用時（下載失敗、手機不支援），搜尋才退回只用關鍵字。
class SemanticSearch extends GetxService {
  static final LiteRtEmbedderVariant _variant = LiteRtEmbedders.embeddinggemma2Text270m.generic;

  final Rx<SemanticState> state = SemanticState.off.obs;
  final RxnInt downloadProgress = RxnInt();
  final RxnString error = RxnString();

  EmbeddingModel? _model;
  List<SearchEntry> _entries = const [];
  List<List<double>> _vectors = const [];
  Future<void>? _starting;
  bool _initialized = false;

  /// App 啟動時呼叫：在背景準備語意搜尋，不阻擋畫面。
  void warmUp() {
    loadSearchEntries().then(enable).catchError((Object e) {
      error.value = e.toString();
      state.value = SemanticState.failed;
    });
  }

  /// 下載（必要時）並載入模型，再把每個服務轉成向量。可以重複呼叫。
  Future<void> enable(List<SearchEntry> entries) {
    if (state.value == SemanticState.ready && entries.length == _entries.length) {
      return Future.value();
    }
    return _starting ??= _start(entries).whenComplete(() => _starting = null);
  }

  Future<void> _start(List<SearchEntry> entries) async {
    error.value = null;
    try {
      state.value = SemanticState.loading;
      if (!_initialized) {
        await FlutterEdgeAi.initialize(embeddingBackends: const [LiteRtEmbeddingBackend()]);
        _initialized = true;
      }
      if (_model == null) {
        final File preloaded = await _preloadedFile();
        final EmbeddingInstallationBuilder builder = await preloaded.exists()
            ? FlutterEdgeAi.installEmbedder().modelFromFile(preloaded.path)
            : FlutterEdgeAi.installEmbedder().fromCatalog(_variant);
        await builder.withProgress((int p) => downloadProgress.value = p).install();
        _model = await FlutterEdgeAi.getActiveEmbedder();
      }
      _vectors = await _model!.embedAll([
        for (final SearchEntry e in entries) EmbeddingInput.text(documentText(e)),
      ], taskType: TaskType.retrievalDocument);
      _entries = entries;
      state.value = SemanticState.ready;
    } catch (e) {
      error.value = e.toString();
      state.value = SemanticState.failed;
    }
  }

  /// 每個服務拿去轉向量的文字：標題、說明，加上各語言的關鍵字。
  /// 實測加上關鍵字後，第一名的正確率從 4/14 提高到 8/14。
  static String documentText(SearchEntry e) => '${e.title}：${e.description}。${e.keywords.join('、')}';

  /// 依意思排序，回傳前 [limit] 名。模型還沒準備好時回傳空清單。
  Future<List<SearchResult>> search(String query, {int limit = 3}) async {
    final EmbeddingModel? model = _model;
    if (state.value != SemanticState.ready || model == null || query.trim().isEmpty) {
      return const [];
    }
    final List<double> q = await model.embed(EmbeddingInput.text(query), taskType: TaskType.retrievalQuery);
    final List<SearchResult> ranked = [
      for (int i = 0; i < _entries.length; i++) SearchResult(_entries[i], _cosine(q, _vectors[i]), ''),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(limit).toList();
  }

  static Future<File> _preloadedFile() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    return File('${documents.path}/preloaded/${_variant.model.installFilename}');
  }

  static double _cosine(List<double> a, List<double> b) {
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na == 0 || nb == 0 ? 0 : dot / (sqrt(na) * sqrt(nb));
  }

  @override
  void onClose() {
    _model?.close();
    super.onClose();
  }
}

enum SemanticState { off, loading, ready, failed }
