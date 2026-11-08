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
          _Prepared(e, [
            _Field(e.title, 1.0),
            for (final String k in e.keywords) _Field(k, 0.9),
            _Field(e.description, 0.7),
          ]),
      ];

  final List<_Prepared> _entries;

  /// 低於這個分數的結果不顯示。
  static const double minScore = 25;

  List<SearchResult> search(String query, {int limit = 20}) {
    final String q = normalize(query);
    if (q.isEmpty) {
      return const [];
    }
    final List<String> qTokens = [
      for (final String t in tokens(query))
        if (!_stopWords.contains(t)) t,
    ];
    final bool latinQuery = _isLatin(q);
    final List<SearchResult> results = [];
    for (final _Prepared p in _entries) {
      // 1. 單一欄位的比對：完全相同、欄位包含查詢、打錯字。
      double best = 0;
      String matched = '';
      for (final _Field f in p.fields) {
        final double s = _score(q, f.normalized) * f.weight;
        if (s > best) {
          best = s;
          matched = f.raw;
        }
      }
      // 2. 涵蓋率：查詢裡有多少部分被這個服務的關鍵字「解釋」到。
      //    例如「labor bureau news」三個字都對到勞動局最新消息，只對到「news」的 YouTube 分數較低。
      final _Coverage cov = latinQuery && qTokens.length >= 2
          ? _wordCoverage(qTokens, p.fields)
          : _charCoverage(q, p.fields);
      if (cov.score > best) {
        best = cov.score;
        matched = cov.matched;
      }
      if (best >= minScore) {
        // 分數相同時，標題和查詢比較像的排前面（例如「親子活動」→ 親子館）。
        final double titleBonus = latinQuery ? 0 : 3 * _bigramDice(q, p.fields.first.normalized);
        results.add(SearchResult(p.entry, best + titleBonus, matched));
      }
    }
    results.sort((a, b) {
      final int byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.entry.title.compareTo(b.entry.title);
    });
    return results.take(limit).toList();
  }

  /// 英文、印尼文、越南文（無聲調）、菲律賓文：以「字」為單位，順序不拘。
  /// 一個關鍵字的每個字都出現在查詢裡，就算這個關鍵字命中；所有命中的關鍵字一起計算涵蓋了查詢的幾個字。
  static _Coverage _wordCoverage(List<String> qTokens, List<_Field> fields) {
    final List<double> covered = List<double>.filled(qTokens.length, 0);
    String matched = '';
    int matchedLen = 0;
    double partial = 0;
    String partialMatched = '';
    for (final _Field f in fields) {
      if (f.tokens.isEmpty) {
        continue;
      }
      final List<int> hits = [
        for (int i = 0; i < qTokens.length; i++)
          if (f.tokens.any((String ft) => _wordMatches(qTokens[i], ft))) i,
      ];
      final bool wholeKeyword = f.tokens.every((String ft) => qTokens.any((String qt) => _wordMatches(qt, ft)));
      if (wholeKeyword && hits.isNotEmpty) {
        for (final int i in hits) {
          for (final String ft in f.tokens) {
            final double qual = _wordQuality(qTokens[i], ft);
            if (qual > covered[i]) {
              covered[i] = qual;
            }
          }
        }
        if (f.tokens.length > matchedLen) {
          matchedLen = f.tokens.length;
          matched = f.raw;
        }
      } else if (qTokens.length >= 3 && hits.length / qTokens.length >= 0.5) {
        // 關鍵字只有一部分出現，但查詢夠長、對到一半以上的字。
        final double s = 40 * hits.length / qTokens.length * f.weight;
        if (s > partial) {
          partial = s;
          partialMatched = f.raw;
        }
      }
    }
    final double n = covered.fold(0, (double a, double b) => a + b);
    if (n == 0) {
      return _Coverage(partial, partialMatched);
    }
    final double s = (50 + 25 * n / qTokens.length) * 0.9;
    return s >= partial ? _Coverage(s, matched) : _Coverage(partial, partialMatched);
  }

  /// 中文、泰文：查詢裡被關鍵字蓋到的字數比例。例如「小孩發燒」裡，
  /// 只蓋到「小孩」的親子館（2/4）會輸給蓋到「發燒」又蓋到更多字的服務。
  static _Coverage _charCoverage(String q, List<_Field> fields) {
    final List<int> qr = q.runes.toList();
    if (qr.length < 2) {
      return const _Coverage(0, '');
    }
    final List<bool> covered = List<bool>.filled(qr.length, false);
    String matched = '';
    int matchedLen = 0;
    for (final _Field f in fields) {
      final List<int> fr = f.normalized.runes.toList();
      if (fr.isEmpty || fr.length >= qr.length) {
        continue;
      }
      // 一個字的關鍵字（例如「狗」「書」）只在關鍵字欄位採用，避免說明裡的單字亂中。
      if (fr.length == 1 && f.weight != 0.9) {
        continue;
      }
      bool hit = false;
      for (int i = 0; i + fr.length <= qr.length; i++) {
        bool same = true;
        for (int j = 0; j < fr.length; j++) {
          if (qr[i + j] != fr[j]) {
            same = false;
            break;
          }
        }
        if (same) {
          hit = true;
          for (int j = 0; j < fr.length; j++) {
            covered[i + j] = true;
          }
        }
      }
      if (hit && fr.length > matchedLen) {
        matchedLen = fr.length;
        matched = f.raw;
      }
    }
    final int n = covered.where((bool c) => c).length;
    if (n == 0) {
      return const _Coverage(0, '');
    }
    return _Coverage((50 + 25 * n / qr.length) * 0.9, matched);
  }

  /// 不影響意思的英文常用字，計算涵蓋率時忽略。
  static const Set<String> _stopWords = {
    'a',
    'an',
    'the',
    'my',
    'me',
    'i',
    'is',
    'are',
    'was',
    'were',
    'am',
    'on',
    'at',
    'in',
    'for',
    'to',
    'of',
    'and',
    'or',
    'can',
    'where',
    'how',
    'what',
    'do',
    'does',
    'did',
    'this',
    'that',
    'it',
    'please',
    'want',
    'need',
    'with',
    'from',
    'yang',
    'di',
    'ke',
    'saya',
    'aku',
    'toi',
    'cua',
    'ang',
    'ng',
    'sa',
  };

  static bool _wordMatches(String q, String f) => _wordQuality(q, f) > 0;

  /// 兩個字有多像：完全相同 1、前綴相同 0.8（短的那個至少 4 個字母，例如 trees/tree）、
  /// 打錯字 0.6（7 個字母以上可錯 1 個、9 個以上可錯 2 個；broken/broker 這種 6 個字母的不算），其他 0。
  /// 規則刻意收緊：測試發現 new/news、weather/water、broken/broker、took/book 都被誤當成同一個字。
  static double _wordQuality(String q, String f) {
    if (q == f) {
      return 1;
    }
    final int shorter = q.length < f.length ? q.length : f.length;
    if (shorter >= 4 && (f.startsWith(q) || q.startsWith(f))) {
      return 0.8;
    }
    if (q.length >= 7 && f.length >= 7) {
      final int allowed = q.length >= 9 ? 2 : 1;
      if (_levenshtein(q, f) <= allowed) {
        return 0.6;
      }
    }
    return 0;
  }

  /// 拉丁文字切成字（小寫、去聲調）。中文、泰文不切字，回傳空清單。
  static List<String> tokens(String input) {
    final List<String> words = [];
    final StringBuffer cur = StringBuffer();
    void flush() {
      if (cur.isNotEmpty) {
        words.add(cur.toString());
        cur.clear();
      }
    }

    for (final int rune in input.toLowerCase().runes) {
      int r = rune;
      if (r >= 0xFF01 && r <= 0xFF5E) {
        r -= 0xFEE0;
      }
      final String folded = _foldLatin[String.fromCharCode(r)] ?? String.fromCharCode(r);
      for (final int c in folded.runes) {
        final bool letterOrDigit = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7A);
        if (letterOrDigit) {
          cur.writeCharCode(c);
        } else if (c >= 0x0300 && c <= 0x036F) {
          continue; // 組合聲調符號
        } else if (c < 0x0250) {
          flush(); // 空白、標點
        } else {
          return const []; // 含中文或泰文：不逐字比對
        }
      }
    }
    flush();
    return words.length >= 2 ? words : const [];
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
    // 查詢的字有多少出現在欄位裡（順序不拘）：「借書」→「圖書借閱」、「繳水費」→「繳交水費」。
    final double inField = _queryInField(q, f);
    final double best = dice > inField ? dice : inField;
    return best >= 0.4 ? 50 * best : 0;
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

  /// 不帶意思的中文虛字，計算「查詢的字出現在欄位裡」時不算。
  static const String _filler = '的了我是在有和要想去把被就也都很嗎呢吧啊';

  /// 中文、泰文：查詢的兩字組合、單字各有多少比例出現在欄位裡（取較高者，單字打八折）。
  /// 只用在欄位比查詢長、而且整句對不上的時候。
  static double _queryInField(String q, String f) {
    final List<int> qr = [
      for (final int c in q.runes)
        if (!_filler.contains(String.fromCharCode(c))) c,
    ];
    if (qr.length < 2 || f.runes.length <= qr.length) {
      return 0;
    }
    final String qs = String.fromCharCodes(qr);
    final List<String> grams = _bigrams(qs);
    final double bigramRatio = grams.where(f.contains).length / grams.length;
    final double charRatio = qr.where((int c) => f.contains(String.fromCharCode(c))).length / qr.length;
    final double c = 0.8 * charRatio;
    return bigramRatio > c ? bigramRatio : c;
  }

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
    return [
      for (int i = 0; i < r.length - 1; i++) String.fromCharCodes([r[i], r[i + 1]]),
    ];
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
  _Field(this.raw, this.weight)
    : normalized = ServiceSearchEngine.normalize(raw),
      tokens =
          ServiceSearchEngine.tokens(raw).isEmpty && ServiceSearchEngine._isLatin(ServiceSearchEngine.normalize(raw))
          ? [ServiceSearchEngine.normalize(raw)]
          : ServiceSearchEngine.tokens(raw);

  final String raw;
  final String normalized;
  final List<String> tokens;
  final double weight;
}

class _Prepared {
  _Prepared(this.entry, this.fields);

  final SearchEntry entry;
  final List<_Field> fields;
}

class _Coverage {
  const _Coverage(this.score, this.matched);

  final double score;
  final String matched;
}
