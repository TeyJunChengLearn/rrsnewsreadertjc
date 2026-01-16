part of 'article_webview_page.dart';

/// Map MLKit TranslateLanguage -> BCP-47 (for model downloads)
String bcpFromTranslateLanguage(TranslateLanguage lang) {
  switch (lang) {
    case TranslateLanguage.english:
      return 'en';
    case TranslateLanguage.malay:
      return 'ms';
    case TranslateLanguage.chinese:
      return 'zh-CN';
    case TranslateLanguage.japanese:
      return 'ja';
    case TranslateLanguage.korean:
      return 'ko';
    case TranslateLanguage.indonesian:
      return 'id';
    case TranslateLanguage.thai:
      return 'th';
    case TranslateLanguage.vietnamese:
      return 'vi';
    case TranslateLanguage.arabic:
      return 'ar';
    case TranslateLanguage.french:
      return 'fr';
    case TranslateLanguage.spanish:
      return 'es';
    case TranslateLanguage.german:
      return 'de';
    case TranslateLanguage.portuguese:
      return 'pt';
    case TranslateLanguage.italian:
      return 'it';
    case TranslateLanguage.russian:
      return 'ru';
    case TranslateLanguage.hindi:
      return 'hi';
    default:
      // Fallback for languages we don't map explicitly (e.g. afrikaans)
      return 'en';
  }
}

/// Choose concrete TTS locale from short language code
String _ttsLocaleForCode(String code) {
  // Handle already-BCP47 codes (e.g., "en-US", "zh-CN")
  if (code.contains('-')) return code;

  switch (code) {
    case 'en':
      return 'en-US';
    case 'ms':
      return 'ms-MY';
    case 'zh':
      return 'zh-CN';
    case 'ja':
      return 'ja-JP';
    case 'ko':
      return 'ko-KR';
    case 'id':
      return 'id-ID';
    case 'th':
      return 'th-TH';
    case 'vi':
      return 'vi-VN';
    case 'ar':
      return 'ar-SA';
    case 'fr':
      return 'fr-FR';
    case 'es':
      return 'es-ES';
    case 'de':
      return 'de-DE';
    case 'pt':
      return 'pt-PT';
    case 'it':
      return 'it-IT';
    case 'ru':
      return 'ru-RU';
    case 'hi':
      return 'hi-IN';
    default:
      return 'en-US';
  }
}

// ---------- Chinese number helper (for TTS) ----------

String _toChineseNumber(String rawDigits) {
  int n = int.tryParse(rawDigits) ?? 0;
  if (n == 0) return '零';

  const smallUnits = ['', '十', '百', '千'];
  const bigUnits = ['', '万', '亿'];
  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

  String sectionToCn(int sec) {
    String res = '';
    int unitPos = 0;
    bool zero = false;
    while (sec > 0) {
      final v = sec % 10;
      if (v == 0) {
        if (!zero && res.isNotEmpty) {
          res = '零$res';
        }
        zero = true;
      } else {
        res = digits[v] + smallUnits[unitPos] + res;
        zero = false;
      }
      unitPos++;
      sec ~/= 10;
    }
    return res;
  }

  String result = '';
  int unitPos = 0;
  while (n > 0) {
    int section = n % 10000;
    if (section != 0) {
      String sectionStr = sectionToCn(section) + bigUnits[unitPos];
      result = sectionStr + result;
    } else {
      if (!result.startsWith('零')) {
        result = '零$result';
      }
    }
    unitPos++;
    n ~/= 10000;
  }

  result = result.replaceAll(RegExp(r'零+$'), '');
  result = result.replaceAll('零零', '零');
  return result;
}

/// Normalize numbers, date/time etc for TTS in target language
String _normalizeForTts(String text, String langCode) {
  String s = text;

  if (langCode.startsWith('zh')) {
    // 2025-10-30 -> 2025年10月30日
    s = s.replaceAllMapped(
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
      (m) =>
          '${_toChineseNumber(m[1]!)}年${_toChineseNumber(m[2]!)}月${_toChineseNumber(m[3]!)}日',
    );
    // 14:05 -> 14点05分
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,2}):(\d{2})'),
      (m) => '${_toChineseNumber(m[1]!)}点${_toChineseNumber(m[2]!)}分',
    );
    // 12% -> 百分之十二
    s = s.replaceAllMapped(
      RegExp(r'(\d+)%'),
      (m) => '百分之${_toChineseNumber(m[1]!)}',
    );
    // units & currency
    s = s.replaceAll('km/h', '公里每小时').replaceAll(RegExp(r'\bkm\b'), '公里');
    s = s.replaceAll('USD', '美元').replaceAll(RegExp(r'\$'), '美元');
    // generic numbers
    s = s.replaceAllMapped(
      RegExp(r'\d+'),
      (m) => _toChineseNumber(m[0]!),
    );
  } else if (langCode == 'ja') {
    s = s.replaceAllMapped(
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
      (m) => '${m[1]}年${m[2]}月${m[3]}日',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,2}):(\d{2})'),
      (m) => '${m[1]}時${m[2]}分',
    );
    s = s.replaceAll('km/h', 'キロ毎時').replaceAll(RegExp(r'\bkm\b'), 'キロ');
    s = s.replaceAll('USD', '米ドル').replaceAll(RegExp(r'\$'), 'ドル');
  } else if (langCode == 'ko') {
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,2}):(\d{2})'),
      (m) => '${m[1]}시 ${m[2]}분',
    );
    s = s.replaceAll('km/h', '시속 킬로미터').replaceAll(RegExp(r'\bkm\b'), '킬로미터');
    s = s.replaceAll('USD', '미 달러').replaceAll(RegExp(r'\$'), '달러');
  }

  return s;
}
