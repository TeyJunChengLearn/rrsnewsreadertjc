# Paragraph Preservation Fix

## Problem
Articles were showing merged paragraphs in reader WebView instead of separate paragraph lines. Multiple paragraphs would collapse into a single block.

## Root Causes

### 1. RSS Content Normalization (FIXED)
**Location**: `RssFeedParser._normalizeWhitespace()` (line 273-289)

**Before**:
```dart
String _normalizeWhitespace(String input) {
  return input.replaceAll(RegExp(r'\s+'), ' ').trim();
}
```
This replaced **ALL** whitespace (including `\n\n` paragraph separators) with single spaces, destroying paragraph structure.

**After**:
```dart
String _normalizeWhitespace(String input) {
  // Preserve paragraph breaks (\n\n) while normalizing whitespace within lines
  final paragraphs = input.split('\n\n');
  final normalized = <String>[];

  for (final para in paragraphs) {
    // Normalize whitespace within each paragraph only
    final cleaned = para.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isNotEmpty) {
      normalized.add(cleaned);
    }
  }

  return normalized.join('\n\n');
}
```

**Fix**: Split by `\n\n` first, normalize each paragraph individually, then rejoin with `\n\n`.

### 2. Double Normalization After ParagraphExtractor (FIXED)
**Location**: `_extractFromHtml()` and `extractFromHtml()` (lines 432-433, 926-927)

**Before**:
```dart
final (content, paragraphs) = _extractMainText(articleRoot);
final normalizedContent = _normalizeWhitespace(content);

return ArticleReadabilityResult(
  mainText: normalizedContent,
  // ...
);
```

**After**:
```dart
final (content, paragraphs) = _extractMainText(articleRoot);
// ParagraphExtractor already normalizes each paragraph, no need to normalize again

return ArticleReadabilityResult(
  mainText: content,
  // ...
);
```

**Fix**: Removed redundant normalization since `ParagraphExtractor` already normalizes whitespace within each paragraph.

## How Paragraphs Flow Now

### HTML Extraction Pipeline
1. **Extract**: `_extractMainText()` → `ParagraphExtractor.extractParagraphLines()`
   - Returns `List<String>` where each element is one normalized paragraph

2. **Join**: Paragraphs joined with `\n\n` separator
   - `text = paragraphs.join('\n\n')`

3. **No More Normalization**: Content preserved as-is
   - Paragraph breaks (`\n\n`) remain intact

### RSS Extraction Pipeline
1. **Parse RSS**: Extract `<p>`, `<li>`, `<blockquote>` elements
2. **Build Buffer**: Join elements with `\n\n` separators
3. **Smart Normalization**: Preserve `\n\n` while cleaning whitespace within paragraphs
4. **Result**: Each paragraph becomes one line

### Reader WebView Display
In `article_webview_page.dart`:

1. **Load Content**: `mainText` contains paragraphs separated by `\n\n`
2. **Split**: `text.split('\n\n')` creates array of paragraphs
3. **Render**: Each paragraph becomes one `<p>` tag in HTML
   ```dart
   '<p data-idx="$i">$line</p>'
   ```

## What Was Fixed

✅ **RSS content** - Paragraph breaks no longer collapsed
✅ **HTML content** - No double-normalization destroying structure
✅ **WebView display** - Each paragraph shows as separate line
✅ **TTS reading** - Each paragraph is one readable chunk

## Testing

To verify the fix:
1. Open an article from RSS feed → Should show separate paragraphs
2. Open an article from HTML → Should show separate paragraphs
3. Enable TTS reading → Each paragraph should be one speaking segment
4. Check reader mode → Each `<p>` tag should contain one paragraph

## Technical Notes

- `ParagraphExtractor` uses density-based filtering (link density, text density) to identify real content
- Each paragraph is normalized internally: `replaceAll(RegExp(r'\s+'), ' ').trim()`
- `\n\n` is the paragraph separator throughout the pipeline
- RSS and HTML use same paragraph preservation logic now
