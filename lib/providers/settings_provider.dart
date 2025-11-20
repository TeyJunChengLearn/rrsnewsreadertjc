import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _darkTheme = false;
  bool _displaySummary = true;
  bool _highlightText = true;

  // how often to refresh (minutes)
  int _updateIntervalMinutes = 30;

  // how many articles to keep per feed (not enforced yet)
  int _articleLimitPerFeed = 1000;

  bool get darkTheme => _darkTheme;
  bool get displaySummary => _displaySummary;
  bool get highlightText => _highlightText;
  int get updateIntervalMinutes => _updateIntervalMinutes;
  int get articleLimitPerFeed => _articleLimitPerFeed;

  static const _kDarkTheme = 'darkTheme';
  static const _kDisplaySummary = 'displaySummary';
  static const _kHighlightText = 'highlightText';
  static const _kUpdateIntervalMinutes = 'updateIntervalMinutes';
  static const _kArticleLimitPerFeed = 'articleLimitPerFeed';

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();

    _darkTheme = prefs.getBool(_kDarkTheme) ?? _darkTheme;
    _displaySummary = prefs.getBool(_kDisplaySummary) ?? _displaySummary;
    _highlightText = prefs.getBool(_kHighlightText) ?? _highlightText;
    _updateIntervalMinutes =
        prefs.getInt(_kUpdateIntervalMinutes) ?? _updateIntervalMinutes;
    _articleLimitPerFeed =
        prefs.getInt(_kArticleLimitPerFeed) ?? _articleLimitPerFeed;

    // 🔴 add this line so translate language is restored on startup
    _translateLangCode =
        prefs.getString(_kTranslateLangKey) ?? _translateLangCode;

    notifyListeners();
    }


  Future<void> toggleDarkTheme(bool val) async {
    _darkTheme = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkTheme, _darkTheme);
  }

  Future<void> setDisplaySummary(bool val) async {
    _displaySummary = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDisplaySummary, _displaySummary);
  }

  Future<void> setHighlightText(bool val) async {
    _highlightText = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHighlightText, _highlightText);
  }

  Future<void> setUpdateIntervalMinutes(int minutes) async {
    _updateIntervalMinutes = minutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUpdateIntervalMinutes, _updateIntervalMinutes);
  }

Future<void> setArticleLimitPerFeed(int value) async {
  // clamp to 10–10 000
  value = value.clamp(10, 10000);
  _articleLimitPerFeed = value;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kArticleLimitPerFeed, _articleLimitPerFeed);
  notifyListeners();
}
  static const _kTranslateLangKey = 'translate_lang_code';
  // Codes: 'off', 'en', 'ms', 'zh-CN', 'zh-TW', 'ja', 'ko', 'id', 'th', 'vi',
  // 'ar', 'fr', 'es', 'de', 'pt', 'it', 'ru', 'hi'

  String _translateLangCode = 'off';
  String get translateLangCode => _translateLangCode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _translateLangCode = prefs.getString(_kTranslateLangKey) ?? 'off';
    notifyListeners();
  }

  Future<void> setTranslateLangCode(String code) async {
    _translateLangCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTranslateLangKey, code);
    notifyListeners();
  }

  bool get isTranslateEnabled => _translateLangCode != 'off';
}
