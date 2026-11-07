/// 服務模糊搜尋：讓民眾用自己的語言、自己的說法找到台北通裡的服務。
///
/// 全部在手機上計算，不連網、不使用 AI 模型，舊手機也能用。
/// 比對方式：
/// 1. 正規化：小寫、全形轉半形、去掉拉丁字母的聲調符號（越南文 phòng → phong）、去掉空白和標點。
/// 2. 完全相同、包含（雙向，所以「我收到罰單」找得到關鍵字「罰單」）。
/// 3. 容錯：拉丁字母用編輯距離（打錯一兩個字母也找得到），中文和泰文用相鄰兩字的重疊比例。
library;

class SearchEntry {
  const SearchEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.keywords,
    this.serviceId,
    this.path,
  });

  final String id;
  final String title;
  final String description;

  /// 各語言的關鍵字與同義詞，全部一起比對。
  final List<String> keywords;

  /// App 內建服務的 [MyServiceItemId] 名稱（例如 `reportIssue`）。
  final String? serviceId;

  /// 微服務網頁的路徑（例如 `/information/line`），會接在微服務網址後面。
  final String? path;
}

class SearchResult {
  const SearchResult(this.entry, this.score, this.matched);

  final SearchEntry entry;
  final double score;

  /// 命中的文字（標題、關鍵字或說明），用來在畫面上告訴使用者「為什麼找到這個」。
  final String matched;
}

class ServiceSearchEngine {
  ServiceSearchEngine(List<SearchEntry> entries)
      : _entries = [
          for (final SearchEntry e in entries)
            _Prepared(
              e,
              [
                _Field(e.title, 1.0),
                for (final String k in e.keywords) _Field(k, 0.9),
                _Field(e.description, 0.6),
              ],
            ),
        ];

  final List<_Prepared> _entries;

  /// 低於這個分數的結果不顯示。
  static const double minScore = 25;

  List<SearchResult> search(String query, {int limit = 20}) {
    final String q = normalize(query);
    if (q.isEmpty) {
      return const [];
    }
    final List<SearchResult> results = [];
    for (final _Prepared p in _entries) {
      double best = 0;
      String matched = '';
      for (final _Field f in p.fields) {
        final double s = _score(q, f.normalized) * f.weight;
        if (s > best) {
          best = s;
          matched = f.raw;
        }
      }
      if (best >= minScore) {
        results.add(SearchResult(p.entry, best, matched));
      }
    }
    results.sort((a, b) {
      final int byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.entry.title.compareTo(b.entry.title);
    });
    return results.take(limit).toList();
  }

  static double _score(String q, String f) {
    if (f.isEmpty) {
      return 0;
    }
    if (q == f) {
      return 100;
    }
    final bool latin = _isLatin(q) && _isLatin(f);
    if (f.contains(q)) {
      // 只打一個中文字（例如「水」）也算，但分數低一點。
      if (!latin && q.runes.length == 1) {
        return 45;
      }
      if (latin && q.length < 2) {
        return 0;
      }
      return 80;
    }
    if (q.contains(f) && f.runes.length >= 2) {
      // 輸入是一句話，裡面包含關鍵字，例如「我收到罰單」包含「罰單」。
      return 70;
    }
    if (latin) {
      final int dist = _levenshtein(q, f);
      final int allowed = q.length <= 4 ? 1 : (q.length <= 8 ? 2 : 3);
      if (dist <= allowed) {
        return 60.0 - 10 * dist;
      }
      // 關鍵字的開頭打錯（例如 musola → musholla）。
      if (q.length >= 4 && f.length > q.length) {
        final int prefixDist = _levenshtein(q, f.substring(0, q.length));
        if (prefixDist <= 1) {
          return 45;
        }
      }
      return 0;
    }
    final double dice = _bigramDice(q, f);
    return dice >= 0.4 ? 50 * dice : 0;
  }

  /// 小寫、全形轉半形、拉丁字母去聲調、去空白和標點。泰文、中文保留原字。
  static String normalize(String input) {
    final StringBuffer out = StringBuffer();
    for (final int rune in input.toLowerCase().runes) {
      int r = rune;
      // 全形 ASCII（！到～）轉半形。
      if (r >= 0xFF01 && r <= 0xFF5E) {
        r -= 0xFEE0;
      }
      final String ch = String.fromCharCode(r);
      final String folded = _foldLatin[ch] ?? ch;
      for (final int c in folded.runes) {
        if (_isSkippable(c)) {
          continue;
        }
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }

  static bool _isSkippable(int c) {
    // 空白、ASCII 標點、全形與中文標點、泰文以外的組合符號。
    if (c <= 0x2F || (c >= 0x3A && c <= 0x40) || (c >= 0x5B && c <= 0x60) || (c >= 0x7B && c <= 0x7F)) {
      return true;
    }
    if (c >= 0x3000 && c <= 0x303F) {
      return true; // 中文標點，例如「，。、」
    }
    if (c >= 0xFF00 && c <= 0xFF0F) {
      return true;
    }
    if (c >= 0x0300 && c <= 0x036F) {
      return true; // 拉丁字母的組合聲調符號
    }
    return false;
  }

  static bool _isLatin(String s) => s.runes.every((c) => c < 0x0250);

  static double _bigramDice(String a, String b) {
    final List<String> ga = _bigrams(a);
    final List<String> gb = _bigrams(b);
    if (ga.isEmpty || gb.isEmpty) {
      return 0;
    }
    final Map<String, int> counts = {};
    for (final String g in gb) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
    int overlap = 0;
    for (final String g in ga) {
      final int c = counts[g] ?? 0;
      if (c > 0) {
        overlap++;
        counts[g] = c - 1;
      }
    }
    return 2 * overlap / (ga.length + gb.length);
  }

  static List<String> _bigrams(String s) {
    final List<int> r = s.runes.toList();
    if (r.length < 2) {
      return r.isEmpty ? const [] : [String.fromCharCodes(r)];
    }
    return [for (int i = 0; i < r.length - 1; i++) String.fromCharCodes([r[i], r[i + 1]])];
  }

  static int _levenshtein(String a, String b) {
    if (a == b) {
      return 0;
    }
    if (a.isEmpty) {
      return b.length;
    }
    if (b.isEmpty) {
      return a.length;
    }
    List<int> prev = List<int>.generate(b.length + 1, (i) => i);
    for (int i = 1; i <= a.length; i++) {
      final List<int> cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// 拉丁字母去聲調（越南文、印尼文、菲律賓文常用的字母）。
  static final Map<String, String> _foldLatin = _buildFoldMap();

  static Map<String, String> _buildFoldMap() {
    const Map<String, String> groups = {
      'a': 'àáâãäåāăąạảấầẩẫậắằẳẵặ',
      'e': 'èéêëēĕėęěẹẻẽếềểễệ',
      'i': 'ìíîïĩīĭįıỉị',
      'o': 'òóôõöøōŏőơọỏốồổỗộớờởỡợ',
      'u': 'ùúûüũūŭůűųưụủứừửữự',
      'y': 'ýÿŷỳỵỷỹ',
      'c': 'çćĉċč',
      'n': 'ñńņňŉ',
      'd': 'đď',
      's': 'śŝşš',
      'z': 'źżž',
      'g': 'ĝğġģ',
    };
    final Map<String, String> map = {};
    groups.forEach((String base, String chars) {
      for (final int c in chars.runes) {
        map[String.fromCharCode(c)] = base;
      }
    });
    return map;
  }
}

class _Field {
  _Field(this.raw, this.weight) : normalized = ServiceSearchEngine.normalize(raw);

  final String raw;
  final String normalized;
  final double weight;
}

class _Prepared {
  _Prepared(this.entry, this.fields);

  final SearchEntry entry;
  final List<_Field> fields;
}
