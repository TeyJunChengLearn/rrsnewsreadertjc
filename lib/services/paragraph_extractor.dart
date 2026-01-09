import 'dart:math';
import 'package:html/parser.dart' as hp;
import 'package:html/dom.dart' as dom;

/// Extracts paragraphs from HTML using structure/density rules instead of keyword hard-coding.
/// Based on Mozilla Readability approach: filters out related lists and clutter using:
/// - Link density (linkTextLen / textLen)
/// - Text density (textLen / tagCount)
/// - Sentence-like detection
/// - Adaptive thresholds based on page's own distribution
class ParagraphExtractor {
  /// Extract paragraphs from article HTML.
  /// Returns List<String> where each element is one paragraph (one line).
  ///
  /// Use this with compute() for better performance:
  /// ```dart
  /// final paragraphs = await compute(extractParagraphLines, articleHtml);
  /// ```
  static List<String> extractParagraphLines(String articleHtml) {
    final doc = hp.parseFragment(articleHtml);

    // 1) Remove structural noise (not content-based keywords)
    doc
        .querySelectorAll(
            'script,style,noscript,iframe,svg,canvas,form,button,input,textarea,select,video,audio')
        .forEach((e) => e.remove());

    // 2) Get candidate blocks - common content containers
    final blocks = doc.querySelectorAll('p,h2,h3,h4,h5,h6,blockquote,li,td,th,figcaption');

    final scored = <_BlockScore>[];
    for (final el in blocks) {
      final paragraphs = _extractParagraphs(el);
      if (paragraphs.isEmpty) continue;

      // Calculate structural metrics
      final all = el.querySelectorAll('*');
      final tagCount = all.length + 1;

      final links = el.querySelectorAll('a');
      final aCount = links.length;
      final linkTextLen = _normalize(links.map((a) => a.text).join(' ')).length;

      for (final text in paragraphs) {
        if (text.length < 20) continue; // Skip very short blocks
        final textLen = text.length;
        final linkDensity = textLen == 0 ? 1.0 : linkTextLen / textLen;
        final textDensity = textLen / max(1, tagCount).toDouble();
        final tagName = el.localName ?? '';

        scored.add(_BlockScore(
          el: el,
          text: text,
          textLen: textLen,
          tagCount: tagCount,
          aCount: aCount,
          linkTextLen: linkTextLen,
          linkDensity: linkDensity,
          anchorTextRatio: linkDensity,
          textDensity: textDensity,
          sentenceLike: _looksLikeSentence(text),
          tagName: tagName,
        ));
      }
    }

    if (scored.isEmpty) return const [];

    // 3) Adaptive thresholds: use page's own distribution (more universal than hard-coded values)
    final medianLinkDensity = _medianDouble(scored.map((x) => x.linkDensity).toList());
    final medianTextLen = _medianInt(scored.map((x) => x.textLen).toList());

    // 4) Filter out noise using structural rules (not keywords)
    final kept = <String>[];
    for (final b in scored) {
      // Filter: High link density = navigation/related lists
      final tooManyLinks = (b.linkDensity > max(0.45, medianLinkDensity + 0.20)) ||
          (b.aCount >= 3 && b.textLen < 120) ||
          (b.aCount >= 5 && b.textLen < 250);

      // Filter: List items that are mostly links (related/news lists)
      final listyLinks = (b.tagName == 'li') &&
          (b.aCount >= 1) &&
          (b.anchorTextRatio > 0.12 || b.textLen < 180);

      // Filter: Blocks where anchor text dominates the paragraph
      final anchorHeavy = (b.anchorTextRatio > 0.25 && b.textLen < 260);

      // Filter: Low text density = widget/sidebar/structured layout
      final tooLowTextDensity = (b.textDensity < 3.0 && b.textLen < medianTextLen) ||
          (b.tagCount > 25 && b.textLen < 120);

      // Filter: Not sentence-like = labels/headings/junk
      final notSentence = (!b.sentenceLike && b.textLen < 80);

      if (tooManyLinks || listyLinks || anchorHeavy || tooLowTextDensity || notSentence) continue;

      kept.add(b.text);
    }

    // 5) Deduplicate (same text appearing in different nodes)
    return _deduplicatePreserveOrder(kept);
  }

  /// Normalize whitespace: replace multiple spaces/newlines with single space
  static String _normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<String> _extractParagraphs(dom.Element el) {
    // Treat each element as ONE paragraph unless it contains explicit line breaks.
    // Preserve <br> line breaks to avoid collapsing multiple logical paragraphs
    // into a single line.
    final text = _extractTextWithBreaks(el).replaceAll('\r\n', '\n');
    final parts = text.split(RegExp(r'\n+'));
    final cleaned = <String>[];
    for (final part in parts) {
      final normalized = _normalize(part);
      if (normalized.isNotEmpty) {
        cleaned.add(normalized);
      }
    }
    return cleaned;
  }

  static String _extractTextWithBreaks(dom.Node node) {
    const blockBreakTags = {
      'p',
      'div',
      'section',
      'article',
      'header',
      'footer',
      'blockquote',
      'li',
      'td',
      'th',
      'figcaption',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
    };
    final buffer = StringBuffer();
    void appendNewlineIfNeeded() {
      if (buffer.isEmpty) return;
      final lastChar = buffer.toString().codeUnitAt(buffer.length - 1);
      if (lastChar != '\n'.codeUnitAt(0)) {
        buffer.write('\n');
      }
    }

    void walk(dom.Node current, {required bool isRoot}) {
      if (current.nodeType == dom.Node.TEXT_NODE) {
        buffer.write(current.text);
        return;
      }
      if (current is dom.Element) {
        final tag = current.localName;
        if (tag == 'br') {
          appendNewlineIfNeeded();
          return;
        }
        final isBlockBoundary = !isRoot && tag != null && blockBreakTags.contains(tag);
        if (isBlockBoundary) {
          appendNewlineIfNeeded();
        }
        for (final child in current.nodes) {
          walk(child, isRoot: false);
        }
        if (isBlockBoundary) {
          appendNewlineIfNeeded();
        }
        return;
      }
      for (final child in current.nodes) {
        walk(child, isRoot: false);
      }
    }

    walk(node, isRoot: true);
    return buffer.toString();
  }

  /// Detect if text looks like a sentence (vs labels/headings/navigation)
  static bool _looksLikeSentence(String s) {
    if (s.length >= 120) return true; // Long text is likely content

    // Has punctuation and not ALL CAPS
    final hasPunct = RegExp(r'[.!?。！？,，;；:：]').hasMatch(s);
    final isAllCaps = s.isNotEmpty && s == s.toUpperCase();
    return hasPunct && !isAllCaps;
  }

  /// Calculate median of double list
  static double _medianDouble(List<double> vals) {
    if (vals.isEmpty) return 0;
    vals.sort();
    final n = vals.length;
    return (n.isOdd) ? vals[n ~/ 2] : (vals[n ~/ 2 - 1] + vals[n ~/ 2]) / 2.0;
  }

  /// Calculate median of int list
  static int _medianInt(List<int> vals) {
    if (vals.isEmpty) return 0;
    vals.sort();
    final n = vals.length;
    return (n.isOdd) ? vals[n ~/ 2] : ((vals[n ~/ 2 - 1] + vals[n ~/ 2]) ~/ 2);
  }

  /// Deduplicate while preserving order
  static List<String> _deduplicatePreserveOrder(List<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in items) {
      final key = s.toLowerCase();
      if (seen.add(key)) out.add(s);
    }
    return out;
  }
}

/// Internal scoring class for paragraph candidates
class _BlockScore {
  final dom.Element el;
  final String text;
  final int textLen;
  final int tagCount;
  final int aCount;
  final int linkTextLen;
  final double linkDensity;
  final double anchorTextRatio;
  final double textDensity;
  final bool sentenceLike;
  final String tagName;

  _BlockScore({
    required this.el,
    required this.text,
    required this.textLen,
    required this.tagCount,
    required this.aCount,
    required this.linkTextLen,
    required this.linkDensity,
    required this.anchorTextRatio,
    required this.textDensity,
    required this.sentenceLike,
    required this.tagName,
  });
}
