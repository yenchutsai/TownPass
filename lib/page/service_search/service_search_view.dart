import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/city_service/model/my_service_model.dart';
import 'package:town_pass/page/service_search/semantic_search.dart';
import 'package:town_pass/page/service_search/service_search_engine.dart';
import 'package:town_pass/page/service_search/service_search_index.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_text.dart';

/// 服務搜尋頁：輸入中文、英文、印尼文、越南文、泰文或菲律賓文，
/// 用自己的說法（例如「我收到罰單」「musholla」）找到台北通裡的服務。
///
/// 混合搜尋：先列關鍵字模糊搜尋的結果，下方再列 AI 語意搜尋的「可能相關」（依意思推薦，例如「雇主打我」）。
/// 語意搜尋預設開啟（App 啟動時在背景載入）；只有模型無法使用時才只顯示關鍵字結果。
class ServiceSearchController extends GetxController {
  final TextEditingController textController = TextEditingController();
  final RxString query = ''.obs;
  final RxList<SearchResult> results = <SearchResult>[].obs;
  final RxList<SearchResult> aiResults = <SearchResult>[].obs;
  final RxBool ready = false.obs;
  ServiceSearchEngine? _engine;
  List<SearchEntry> _entries = const [];
  int _searchId = 0;

  SemanticSearch get semantic => Get.isRegistered<SemanticSearch>()
      ? Get.find<SemanticSearch>()
      : Get.put<SemanticSearch>(SemanticSearch(), permanent: true);

  @override
  void onInit() {
    super.onInit();
    loadSearchEntries().then((List<SearchEntry> entries) {
      _entries = entries;
      _engine = ServiceSearchEngine(entries);
      ready.value = true;
      _run(query.value);
    });
    debounce<String>(query, _run, time: const Duration(milliseconds: 150));
    // 監聽輸入框的完整狀態，而不只是文字改變：
    // 注音、倉頡、日文等輸入法還在選字時（例如「ㄎㄢˇㄕㄨˋ」）先不搜尋；
    // 選字結束（即使文字沒變，例如切換鍵盤時直接送出）就立刻搜尋。
    textController.addListener(() {
      final TextEditingValue v = textController.value;
      final bool composing = v.composing.isValid && !v.composing.isCollapsed;
      if (!composing && query.value != v.text) {
        query.value = v.text;
      }
    });
    ever<SemanticState>(semantic.state, (SemanticState s) {
      if (s == SemanticState.ready) {
        _run(query.value);
      }
    });
  }

  /// 語意搜尋失敗時，使用者按「重新嘗試」。
  Future<void> retryAi() => semantic.enable(_entries);

  void setQuery(String value) {
    textController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    query.value = value;
  }

  Future<void> _run(String value) async {
    final int id = ++_searchId;
    final List<SearchResult> keyword = _engine?.search(value) ?? const [];
    results.value = keyword;
    if (value.trim().isEmpty) {
      aiResults.clear();
      return;
    }
    final List<SearchResult> ai = await semantic.search(value, limit: 3 + keyword.length);
    if (id != _searchId) {
      return; // 使用者已經改了輸入，丟掉舊結果。
    }
    final Set<String> shown = {for (final SearchResult r in keyword.take(5)) r.entry.id};
    aiResults.value = ai.where((SearchResult r) => !shown.contains(r.entry.id)).take(3).toList();
  }

  @override
  void onClose() {
    textController.dispose();
    super.onClose();
  }
}

class ServiceSearchView extends StatelessWidget {
  const ServiceSearchView({super.key});

  /// 範例關鍵字，讓第一次使用的人知道可以用自己的語言、自己的說法搜尋。
  static const List<String> _examples = [
    '我收到罰單',
    '樹倒了',
    '老闆欠薪',
    'musholla',
    'phòng cầu nguyện',
    'ห้องละหมาด',
    'hospital',
  ];

  @override
  Widget build(BuildContext context) {
    final ServiceSearchController c = Get.find<ServiceSearchController>();
    return Scaffold(
      backgroundColor: TPColors.white,
      appBar: const TPAppBar(title: '搜尋服務'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: c.textController,
              autofocus: true,
              // 搜尋由 controller 監聽輸入框狀態觸發（含輸入法選字結束），見 ServiceSearchController.onInit。
              textInputAction: TextInputAction.search,
              style: TPTextStyles.h3Regular.copyWith(color: TPColors.grayscale900),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: TPColors.grayscale500),
                suffixIcon: Obx(
                  () => c.query.value.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: '清除',
                          icon: const Icon(Icons.close, color: TPColors.grayscale500),
                          onPressed: () => c.setQuery(''),
                        ),
                ),
                hintText: '您想辦什麼事？可以用您的語言輸入',
                hintStyle: TPTextStyles.bodyRegular.copyWith(color: TPColors.grayscale400),
                filled: true,
                fillColor: TPColors.grayscale50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: Obx(() {
              if (!c.ready.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (c.query.value.trim().isEmpty) {
                return ListView(
                  children: [
                    _Examples(onTap: c.setQuery),
                    _AiStatus(controller: c),
                  ],
                );
              }
              final SemanticState ai = c.semantic.state.value;
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (c.results.isEmpty && (ai != SemanticState.ready || c.aiResults.isEmpty)) const _NoResult(),
                  for (final SearchResult r in c.results) _ResultTile(result: r),
                  if (ai == SemanticState.ready && c.aiResults.isNotEmpty) ...[
                    const _SectionHeader(title: '可能相關', subtitle: '由手機上的 AI 依意思推薦（EmbeddingGemma 2），僅供參考'),
                    for (final SearchResult r in c.aiResults) _ResultTile(result: r),
                  ],
                  if (ai != SemanticState.ready) _AiStatus(controller: c),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Examples extends StatelessWidget {
  const _Examples({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TPText('試試看這樣搜尋', style: TPTextStyles.h3SemiBold, color: TPColors.grayscale900),
          const SizedBox(height: 4),
          const TPText(
            '用平常說話的方式，或用中文、English、Bahasa Indonesia、Tiếng Việt、ภาษาไทย、Tagalog 都可以。',
            style: TPTextStyles.bodyRegular,
            color: TPColors.grayscale600,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final String example in ServiceSearchView._examples)
                ActionChip(
                  label: TPText(example, style: TPTextStyles.bodyRegular, color: TPColors.primary700),
                  backgroundColor: TPColors.primary50,
                  side: const BorderSide(color: TPColors.primary200),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  onPressed: () => onTap(example),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoResult extends StatelessWidget {
  const _NoResult();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          TPText('找不到相關的服務', style: TPTextStyles.h3SemiBold, color: TPColors.grayscale900),
          SizedBox(height: 8),
          TPText(
            '請換個說法再試一次，或撥打 1999 市民熱線詢問。外籍朋友可以撥打 1955 移工專線。',
            style: TPTextStyles.bodyRegular,
            color: TPColors.grayscale600,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  MyServiceItem? get _appItem {
    final String? id = result.entry.serviceId;
    if (id == null) {
      return null;
    }
    return MyServiceItemId.values.firstWhereOrNull((MyServiceItemId e) => e.name == id)?.item;
  }

  String get _url {
    final MyServiceItem? item = _appItem;
    if (item != null) {
      return item.destinationUrl;
    }
    return '$migrantServiceBaseUrl${result.entry.path ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final MyServiceItem? item = _appItem;
    final String url = _url;
    final bool available = url.isNotEmpty;
    final SearchEntry entry = result.entry;
    final bool showMatched =
        result.matched.isNotEmpty && result.matched != entry.title && result.matched != entry.description;

    return Semantics(
      button: available,
      label: '${entry.title}，${entry.description}${available ? '' : '，此服務尚未開放'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: available
            ? () => TPRoute.openUri(uri: url, forceTitle: item?.forceWebViewTitle)
            : () => Get.snackbar('尚未開放', '「${entry.title}」目前還沒有線上服務，請撥打 1999 詢問。', snackPosition: SnackPosition.BOTTOM),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: TPColors.primary50,
                  child: SizedBox(width: 28, height: 28, child: item?.icon ?? Assets.svg.iconTalk.svg()),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TPText(
                        entry.title,
                        style: TPTextStyles.h3SemiBold,
                        color: available ? TPColors.grayscale900 : TPColors.grayscale500,
                      ),
                      if (entry.description.isNotEmpty)
                        TPText(
                          entry.description,
                          style: TPTextStyles.bodyRegular,
                          color: TPColors.grayscale600,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (showMatched)
                        TPText('符合：${result.matched}', style: TPTextStyles.caption, color: TPColors.primary700),
                      if (!available)
                        const TPText('尚未開放線上服務', style: TPTextStyles.caption, color: TPColors.grayscale500),
                    ],
                  ),
                ),
                if (available) const Icon(Icons.chevron_right, color: TPColors.grayscale400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TPColors.grayscale50,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TPText(title, style: TPTextStyles.h3SemiBold, color: TPColors.grayscale900),
          TPText(subtitle, style: TPTextStyles.caption, color: TPColors.grayscale600),
        ],
      ),
    );
  }
}

/// AI 語意搜尋的狀態：準備中顯示進度，失敗時提供重新嘗試；準備好就不顯示。
class _AiStatus extends StatelessWidget {
  const _AiStatus({required this.controller});

  final ServiceSearchController controller;

  @override
  Widget build(BuildContext context) {
    final SemanticSearch semantic = controller.semantic;
    return Obx(() {
      final SemanticState state = semantic.state.value;
      if (state == SemanticState.ready) {
        return const SizedBox.shrink();
      }
      final int? progress = semantic.downloadProgress.value;
      final bool failed = state == SemanticState.failed;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            if (!failed)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.info_outline, size: 18, color: TPColors.grayscale500),
            const SizedBox(width: 8),
            Expanded(
              child: TPText(
                failed
                    ? 'AI 搜尋暫時無法使用，目前只用關鍵字搜尋。'
                    : progress != null && progress < 100
                    ? 'AI 搜尋準備中（下載 $progress%），先顯示關鍵字搜尋結果。'
                    : 'AI 搜尋準備中…',
                style: TPTextStyles.caption,
                color: TPColors.grayscale600,
              ),
            ),
            if (failed)
              TextButton(
                onPressed: controller.retryAi,
                child: const TPText('重新嘗試', style: TPTextStyles.caption, color: TPColors.primary700),
              ),
          ],
        ),
      );
    });
  }
}
