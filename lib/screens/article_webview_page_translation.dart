part of 'article_webview_page.dart';

extension _ArticleWebviewPageTranslation on _ArticleWebviewPageState {
  TranslateLanguage? _translateLanguageFromCode(String code) {
    switch (code) {
      case 'en':
        return TranslateLanguage.english;
      case 'ms':
        return TranslateLanguage.malay;
      case 'zh-CN':
      case 'zh-TW':
        return TranslateLanguage.chinese;
      case 'ja':
        return TranslateLanguage.japanese;
      case 'ko':
        return TranslateLanguage.korean;
      case 'id':
        return TranslateLanguage.indonesian;
      case 'th':
        return TranslateLanguage.thai;
      case 'vi':
        return TranslateLanguage.vietnamese;
      case 'ar':
        return TranslateLanguage.arabic;
      case 'fr':
        return TranslateLanguage.french;
      case 'es':
        return TranslateLanguage.spanish;
      case 'de':
        return TranslateLanguage.german;
      case 'pt':
        return TranslateLanguage.portuguese;
      case 'it':
        return TranslateLanguage.italian;
      case 'ru':
        return TranslateLanguage.russian;
      case 'hi':
        return TranslateLanguage.hindi;
      default:
        return null;
    }
  }

  Future<TranslateLanguage> _detectSourceLang() async {
    if (_srcLangDetected != null) return _srcLangDetected!;
    final sample = _lines.take(6).join(' ');
    final id = LanguageIdentifier(confidenceThreshold: 0.4);
    try {
      final code =
          await id.identifyLanguage(sample.isNotEmpty ? sample : 'Hello');
      TranslateLanguage lang = TranslateLanguage.english;
      if (code.startsWith('ms')) {
        lang = TranslateLanguage.malay;
      } else if (code.startsWith('zh')) {
        lang = TranslateLanguage.chinese;
      } else if (code.startsWith('ja')) {
        lang = TranslateLanguage.japanese;
      } else if (code.startsWith('ko')) {
        lang = TranslateLanguage.korean;
      } else if (code.startsWith('id')) {
        lang = TranslateLanguage.indonesian;
      } else if (code.startsWith('th')) {
        lang = TranslateLanguage.thai;
      } else if (code.startsWith('vi')) {
        lang = TranslateLanguage.vietnamese;
      } else if (code.startsWith('ar')) {
        lang = TranslateLanguage.arabic;
      } else if (code.startsWith('fr')) {
        lang = TranslateLanguage.french;
      } else if (code.startsWith('es')) {
        lang = TranslateLanguage.spanish;
      } else if (code.startsWith('de')) {
        lang = TranslateLanguage.german;
      } else if (code.startsWith('pt')) {
        lang = TranslateLanguage.portuguese;
      } else if (code.startsWith('it')) {
        lang = TranslateLanguage.italian;
      } else if (code.startsWith('ru')) {
        lang = TranslateLanguage.russian;
      } else if (code.startsWith('hi')) {
        lang = TranslateLanguage.hindi;
      }
      _srcLangDetected = lang;
      return lang;
    } catch (_) {
      return TranslateLanguage.english;
    } finally {
      id.close();
    }
  }

  /// Detect the primary language of the entire article (by analyzing first few lines)
  /// This language will be used consistently throughout the article for the same voice
  Future<String> _detectArticlePrimaryLanguage() async {
    // If already detected for this article, return cached value
    if (_articlePrimaryLanguage != null) {
      return _articlePrimaryLanguage!;
    }

    // Use first 5-10 lines (or all if fewer) to detect primary language
    final sampleLines = _lines.take(10).where((line) => line.trim().isNotEmpty).take(5);
    final sampleText = sampleLines.join(' ');

    if (sampleText.isEmpty) {
      _articlePrimaryLanguage = 'en-US';
      return 'en-US';
    }

    // Detect language using ML Kit
    final id = LanguageIdentifier(confidenceThreshold: 0.4);
    try {
      final code = await id.identifyLanguage(sampleText);

      // Map ML Kit language codes to BCP-47 codes
      String bcpCode = 'en-US'; // Default to English
      if (code.startsWith('ms')) {
        bcpCode = 'ms-MY';
      } else if (code.startsWith('zh')) {
        bcpCode = 'zh-CN';
      } else if (code.startsWith('ja')) {
        bcpCode = 'ja-JP';
      } else if (code.startsWith('ko')) {
        bcpCode = 'ko-KR';
      } else if (code.startsWith('id')) {
        bcpCode = 'id-ID';
      } else if (code.startsWith('th')) {
        bcpCode = 'th-TH';
      } else if (code.startsWith('vi')) {
        bcpCode = 'vi-VN';
      } else if (code.startsWith('ar')) {
        bcpCode = 'ar-SA';
      } else if (code.startsWith('fr')) {
        bcpCode = 'fr-FR';
      } else if (code.startsWith('es')) {
        bcpCode = 'es-ES';
      } else if (code.startsWith('de')) {
        bcpCode = 'de-DE';
      } else if (code.startsWith('pt')) {
        bcpCode = 'pt-PT';
      } else if (code.startsWith('it')) {
        bcpCode = 'it-IT';
      } else if (code.startsWith('ru')) {
        bcpCode = 'ru-RU';
      } else if (code.startsWith('hi')) {
        bcpCode = 'hi-IN';
      } else if (code.startsWith('en')) {
        bcpCode = 'en-US';
      }

      // Cache the result for this article
      _articlePrimaryLanguage = bcpCode;
      return bcpCode;
    } catch (_) {
      // On error, default to English
      _articlePrimaryLanguage = 'en-US';
      return 'en-US';
    } finally {
      id.close();
    }
  }

  /// Restore cached translation if available for this article
  Future<void> _restoreCachedTranslation() async {
    if (!mounted) return;
    final articleId = widget.articleId;
    if (articleId == null || articleId.isEmpty) return;

    final cached = _ttsState.translationCache[articleId];
    if (cached == null) return;

    final translatedLines = cached['translated'];
    final originalLines = cached['original'];

    if (translatedLines == null || translatedLines.isEmpty) return;
    if (originalLines == null || originalLines.isEmpty) return;

    // Restore translation state
    setState(() {
      _originalLinesCache = List<String>.from(originalLines);
      _lines
        ..clear()
        ..addAll(translatedLines);
      _isTranslatedView = true;
    });
    _ttsState.isTranslatedContent = true;
    // Sync global TTS state with translated lines
    _ttsState.lines = _lines;

    // Reload reader HTML with translated content
    if (_readerOn) {
      await _reloadReaderHtml(showLoading: false);
    }

    // Apply TTS locale for translated content
    final settings = context.read<SettingsProvider>();
    final code = settings.translateLangCode;
    if (code != 'off') {
      await _applyTtsLocale(code);
    }
    await _applySpeechRateFromSettings(restartIfPlaying: false);

    debugPrint('📖 Restored cached translation for article: $articleId');
  }

  /// Save translation to cache
  void _cacheTranslation(String articleId, List<String> original, List<String> translated) {
    if (articleId.isEmpty) return;
    _ttsState.translationCache[articleId] = {
      'original': List<String>.from(original),
      'translated': List<String>.from(translated),
    };
    debugPrint('💾 Cached translation for article: $articleId');
  }

  /// Clear cached translation for an article
  void _clearCachedTranslation(String articleId) {
    if (articleId.isEmpty) return;
    _ttsState.translationCache.remove(articleId);
    debugPrint('🗑️ Cleared cached translation for article: $articleId');
  }

  Future<void> _toggleTranslateToSetting() async {
    final settings = context.read<SettingsProvider>();
    final code = settings.translateLangCode;

    if (code == 'off') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Translation disabled in Settings.')),
      );
      return;
    }

    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    // already translated -> back to original
    if (_isTranslatedView) {
      if (_originalLinesCache != null) {
        final wasPlaying = _isPlaying;
        setState(() {
          _lines
            ..clear()
            ..addAll(_originalLinesCache!);
          _isTranslatedView = false;
          // Keep current line position when reverting translation
          _webHighlightText = null;
        });
        // Reset article language detection when un-translating
        _articlePrimaryLanguage = null;
        _cachedTtsLanguageCode = null;
        // Update TTS state for speed settings
        _ttsState.isTranslatedContent = false;

        await _reloadReaderHtml(showLoading: true);
        await _applyTtsLocale('en');
        // Apply speech rate for original content
        await _applySpeechRateFromSettings(restartIfPlaying: false);

        // If was playing before reverting translation, continue playing with original language
        if (wasPlaying && _lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
          await _speakCurrentLine();
        }
      }
      return;
    }

    setState(() => _isTranslating = true);

    final target = _translateLanguageFromCode(code);
    if (target == null) {
      setState(() => _isTranslating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unsupported target language: $code')),
      );
      return;
    }

    // Detect source language from the article text
    final src = await _detectSourceLang();

    // ✅ Let OnDeviceTranslator handle model download internally
    final translator =
        OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

    _originalLinesCache ??= List<String>.from(_lines);
    final translated = <String>[];

    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];

      // image marker line (we’re not using this right now, but keep logic)
      if (line.startsWith('__IMG__|')) {
        translated.add(line);
        continue;
      }

      final t = await translator.translateText(line);
      translated.add(t);
    }

    await translator.close();

    if (!mounted) return;

    final wasPlaying = _isPlaying;
    setState(() {
      _lines
        ..clear()
        ..addAll(translated);
      _isTranslatedView = true;
      _isTranslating = false;
      // Keep current line position when translating
      _webHighlightText = null;
    });
    // Reset article language detection when translating
    // This ensures the translated language is used consistently
    _articlePrimaryLanguage = null;
    _cachedTtsLanguageCode = null;
    // Update TTS state for speed settings
    _ttsState.isTranslatedContent = true;

    // Cache the translation for this article
    if (widget.articleId != null && _originalLinesCache != null) {
      _cacheTranslation(widget.articleId!, _originalLinesCache!, translated);
    }

    await _reloadReaderHtml(showLoading: true);
    await _applyTtsLocale(code);
    // Apply speech rate for translated content
    await _applySpeechRateFromSettings(restartIfPlaying: false);

    // If was playing before translation, continue playing with new language
    if (wasPlaying && _lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
      await _speakCurrentLine();
    }
  }

  /// Handle auto-translate for global TTS (background playback)
  /// This is called when loading next article during background TTS
  Future<void> _handleGlobalAutoTranslate(List<String> lines) async {
    final bool autoTranslateEnabled;
    final String translateLangCode;
    if (mounted) {
      final settings = context.read<SettingsProvider>();
      autoTranslateEnabled = settings.autoTranslate;
      translateLangCode = settings.translateLangCode;
    } else {
      autoTranslateEnabled = _ttsState.autoTranslateEnabled;
      translateLangCode = _ttsState.translateLangCode;
    }

    // Check if auto-translate is enabled AND translation language is set
    if (!autoTranslateEnabled || translateLangCode == 'off') {
      return;
    }

    if (lines.isEmpty) return;

    final code = translateLangCode;
    final target = _translateLanguageFromCode(code);
    if (target == null) return;

    try {
      // Detect source language from the first few lines
      final sampleText = lines.take(5).join(' ');
      final id = LanguageIdentifier(confidenceThreshold: 0.4);
      String mlKitCode = await id.identifyLanguage(sampleText);
      id.close();

      // Map ML Kit codes to TranslateLanguage
      TranslateLanguage src = TranslateLanguage.english;
      if (mlKitCode.startsWith('ms')) {
        src = TranslateLanguage.malay;
      } else if (mlKitCode.startsWith('zh')) {
        src = TranslateLanguage.chinese;
      } else if (mlKitCode.startsWith('ja')) {
        src = TranslateLanguage.japanese;
      } else if (mlKitCode.startsWith('ko')) {
        src = TranslateLanguage.korean;
      } else if (mlKitCode.startsWith('id')) {
        src = TranslateLanguage.indonesian;
      } else if (mlKitCode.startsWith('th')) {
        src = TranslateLanguage.thai;
      } else if (mlKitCode.startsWith('vi')) {
        src = TranslateLanguage.vietnamese;
      } else if (mlKitCode.startsWith('ar')) {
        src = TranslateLanguage.arabic;
      } else if (mlKitCode.startsWith('fr')) {
        src = TranslateLanguage.french;
      } else if (mlKitCode.startsWith('es')) {
        src = TranslateLanguage.spanish;
      } else if (mlKitCode.startsWith('de')) {
        src = TranslateLanguage.german;
      } else if (mlKitCode.startsWith('pt')) {
        src = TranslateLanguage.portuguese;
      } else if (mlKitCode.startsWith('it')) {
        src = TranslateLanguage.italian;
      } else if (mlKitCode.startsWith('ru')) {
        src = TranslateLanguage.russian;
      } else if (mlKitCode.startsWith('hi')) {
        src = TranslateLanguage.hindi;
      }

      // Create translator
      final translator = OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

      final translated = <String>[];
      for (final line in lines) {
        if (line.startsWith('__IMG__|')) {
          translated.add(line);
          continue;
        }
        final t = await translator.translateText(line);
        translated.add(t);
      }

      await translator.close();

      // Update global state with translated lines
      _ttsState.lines = translated;
      _ttsState.isTranslatedContent = true;

      // Update TTS locale for the new language
      await _applyTtsLocale(code);

      if (mounted) {
        await _applySpeechRateFromSettings(restartIfPlaying: false);
      }
    } catch (_) {
      // Silent failure - auto-translate is optional
    }
  }

  /// Auto-translate article if autoTranslate setting is enabled
  /// Called automatically when opening article or switching to next article
  Future<void> _autoTranslateIfEnabled() async {
    if (!mounted) return;

    final settings = context.read<SettingsProvider>();

    // Check if auto-translate is enabled AND translation language is set
    if (!settings.autoTranslate || settings.translateLangCode == 'off') {
      return;
    }

    // Don't auto-translate if already translated
    if (_isTranslatedView) return;

    // Don't auto-translate if currently translating
    if (_isTranslating) return;

    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    final code = settings.translateLangCode;
    final target = _translateLanguageFromCode(code);
    if (target == null) return;

    setState(() => _isTranslating = true);

    try {
      // Detect source language from the article text
      final src = await _detectSourceLang();

      // Create translator
      final translator =
          OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

      _originalLinesCache ??= List<String>.from(_lines);
      final translated = <String>[];

      for (int i = 0; i < _lines.length; i++) {
        final line = _lines[i];

        // image marker line (we're not using this right now, but keep logic)
        if (line.startsWith('__IMG__|')) {
          translated.add(line);
          continue;
        }

        final t = await translator.translateText(line);
        translated.add(t);
      }

      await translator.close();

      if (!mounted) return;

      final wasPlaying = _isPlaying;
      setState(() {
        _lines
          ..clear()
          ..addAll(translated);
        _isTranslatedView = true;
        _isTranslating = false;
        _webHighlightText = null;
      });

      // Reset article language detection when translating
      _articlePrimaryLanguage = null;
      _cachedTtsLanguageCode = null;
      // Update TTS state for speed settings
      _ttsState.isTranslatedContent = true;

      // Cache the translation for this article
      if (widget.articleId != null && _originalLinesCache != null) {
        _cacheTranslation(widget.articleId!, _originalLinesCache!, translated);
      }

      await _reloadReaderHtml(showLoading: false); // Don't show loading spinner for auto-translate
      await _applyTtsLocale(code);
      // Apply speech rate for translated content
      await _applySpeechRateFromSettings(restartIfPlaying: false);

      // If was playing before translation, continue playing with new language
      if (wasPlaying && _lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
        await _speakCurrentLine();
      }
    } catch (e) {
      // Silent failure - auto-translate is optional
      if (mounted) {
        setState(() => _isTranslating = false);
      }
    }
  }
}
