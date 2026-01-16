part of 'article_webview_page.dart';

extension _ArticleWebviewPageReader on _ArticleWebviewPageState {
  Future<void> _loadReaderContent() async {
    final shouldShowLoading = _lines.isEmpty;
    if (shouldShowLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    await _ensureLinesLoaded();
    if (_lines.isEmpty) {
      if (mounted) {
        setState(() {
          _readerOn = false;
          _isLoading = false;
        });
      }
      await _loadArticleUrl();
      return;
    }

    if (!mounted) return;
    final isDark = context.read<SettingsProvider>().darkTheme;
    final html = _buildReaderHtml(_lines, _heroImageUrl, isDark: isDark);
    await _controller.loadRequest(
      Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8),
    );

    if (mounted && shouldShowLoading) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _reloadReaderHtml({bool showLoading = false}) async {
    if (!_readerOn) return;
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    final isDark = context.read<SettingsProvider>().darkTheme;
    final html = _buildReaderHtml(_lines, _heroImageUrl, isDark: isDark);

    await _controller.loadRequest(
      Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8),
    );

    if (showLoading && mounted) {
      setState(() => _isLoading = false);
    }

    // Highlight current line after reload (whether playing or not)
    if (_lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
      // Small delay to let the HTML render
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && _readerOn) {
        await _highlightLine(_currentLine);
      }
    }
  }

  String _buildReaderHtml(List<String> lines, String? heroUrl, {bool isDark = false}) {
    // Colors for light and dark mode
    final bgColor = isDark ? '#121212' : '#fff';
    final textColor = isDark ? '#e0e0e0' : '#000';
    final highlightColor = isDark ? 'rgba(255,235,59,0.3)' : 'rgba(255,235,59,0.4)';

    final buffer = StringBuffer();
    buffer.writeln('<html><head>'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<style>'
        'body{margin:0;background:$bgColor;color:$textColor;font-family:-apple-system,BlinkMacSystemFont,system-ui,Roboto,"Segoe UI",sans-serif;}'
        '.wrap{max-width:760px;margin:0 auto;padding:16px;}'
        'img.hero{width:100%;height:auto;border-radius:8px;margin-bottom:16px;object-fit:cover;}'
        'p{font-size:1.02rem;line-height:1.7;margin:0 0 1rem 0;color:$textColor;}'
        'p.hl{background-color:$highlightColor !important;}'
        // treat first line (index 0) as header
        'p[data-idx="0"]{font-size:1.25rem;font-weight:600;margin-bottom:1.2rem;}'
        '</style>');
    buffer.writeln('<script>'
        'window.flutterHighlightLine=function(index){'
        'try{'
        'var paras=document.querySelectorAll("p[data-idx]");'
        'var found=false;'
        'for(var i=0;i<paras.length;i++){' 
        'var el=paras[i];'
        'var idx=parseInt(el.getAttribute("data-idx")||"-1");'
        'if(idx===index){'
        'el.classList.add("hl");'
        // Cancel any ongoing smooth scroll and use instant scroll for rapid navigation
        'if(window.scrollTimeout){clearTimeout(window.scrollTimeout);}'
        'el.scrollIntoView({behavior:"instant",block:"center"});'
        // Then apply a smooth scroll after a brief delay for better UX
        'window.scrollTimeout=setTimeout(function(){'
        'if(el.classList.contains("hl")){' 
        'el.scrollIntoView({behavior:"smooth",block:"center"});'
        '}'
        '},50);'
        'found=true;'
        '}else{'
        'el.classList.remove("hl");'
        '}'
        '}'
        'return found;'
        '}catch(e){'
        'console.error("Highlight error:",e);'
        'return false;'
        '}'
        '};'
        '</script>');
    buffer.writeln('</head><body><div class="wrap">');

    if (heroUrl != null && heroUrl.isNotEmpty) {
      buffer.writeln('<img src="$heroUrl" class="hero" />');
    }

    for (var i = 0; i < lines.length; i++) {
      final p = lines[i];
      final escaped = p
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      buffer.writeln('<p data-idx="$i">$escaped</p>');
    }

    buffer.writeln('</div></body></html>');
    return buffer.toString();
  }

  bool _isLikelyPreviewText(String text, bool pagePaywalled) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final lower = trimmed.toLowerCase();
    final wordCount =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final previewMarkers = [
      'continue reading',
      'read more',
      'subscribe to read',
      'to continue reading',
      'log in to read',
      'sign in to continue',
      'unlock full article',
    ];

    // Check if markers appear at the END (last 200 chars), not anywhere in text
    final last200 = trimmed.length > 200 ? lower.substring(lower.length - 200) : lower;
    final hasMarkersAtEnd = previewMarkers.any(last200.contains);
    final trailingEllipsis = RegExp(r'(\.\.\.|…)$').hasMatch(trimmed);

    // Only consider it preview if markers at end OR ellipsis with short content
    if (hasMarkersAtEnd && wordCount < 200) return true;
    if (trailingEllipsis && wordCount < 150) return true;

    // Lowered from 180 to 100 - be more lenient for authenticated users
    // After paywall removal, even short content should be considered valid
    if (pagePaywalled && wordCount < 100) return true;

    return false;
  }
}
