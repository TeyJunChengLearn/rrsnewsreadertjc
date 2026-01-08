# Improved Paragraph Extraction

## Overview

The readability service has been restructured with **density-based filtering** instead of hard-coded keyword matching. This approach:

- ✅ **More universal** - works across languages and cultures (no "related", "recommended" keywords)
- ✅ **Adaptive** - uses each page's own distribution to set thresholds
- ✅ **Cleaner output** - filters navigation/widgets using structure, not content
- ✅ **One paragraph = one line** - perfect for TTS and clean reading

## What Changed

### Before (Hard-coded keywords)
```dart
// ❌ Old approach - brittle, language-specific
if (headingText.contains('related') ||
    headingText.contains('recommended') ||
    headingText.contains('more stories')) {
  // Remove...
}
```

### After (Density-based filtering)
```dart
// ✅ New approach - structural analysis
final linkDensity = linkTextLen / textLen;
final textDensity = textLen / tagCount;
final medianLinkDensity = calculateMedian(allBlocks);

// Filter blocks with abnormally high link density
if (linkDensity > max(0.45, medianLinkDensity + 0.20)) {
  // This is likely navigation/related list
}
```

## Usage

### 1. Extract Article (includes paragraphs)

```dart
final result = await readability.extractMainContent(url);

if (result != null) {
  // Old way: single string with \n\n separators
  print(result.mainText);

  // New way: clean list of paragraphs
  for (final paragraph in result.paragraphs ?? []) {
    print(paragraph); // Each paragraph is one line
  }
}
```

### 2. Display in Flutter UI

```dart
// Recommended: One paragraph per Text widget
ListView.separated(
  itemCount: result.paragraphs?.length ?? 0,
  separatorBuilder: (_, __) => const SizedBox(height: 12),
  itemBuilder: (context, i) => Text(
    result.paragraphs![i],
    style: const TextStyle(fontSize: 16, height: 1.4),
  ),
);
```

### 3. Use with compute() for Performance

```dart
import 'package:flutter/foundation.dart';
import 'package:your_app/services/paragraph_extractor.dart';

// Extract paragraphs in isolate (recommended for large HTML)
final paragraphs = await compute(
  ParagraphExtractor.extractParagraphLines,
  articleHtml,
);
```

### 4. Direct Extraction from HTML

```dart
// If you already have the HTML
final paragraphs = await Readability4JExtended.extractParagraphsFromHtml(
  htmlString,
);
```

## How It Works

### Metrics Calculated

For each content block (p, h2-h6, blockquote, li):

1. **Link Density** = (text length in links) / (total text length)
   - High link density → likely navigation/related articles

2. **Text Density** = (text length) / (number of HTML tags)
   - Low text density → likely widget/sidebar/structured layout

3. **Sentence Detection** = has punctuation + not ALL CAPS
   - Non-sentence short text → likely labels/headings/junk

### Adaptive Thresholds

Instead of hard-coded cutoffs, we use the page's own distribution:

```dart
final medianLinkDensity = calculateMedian(allBlocks.linkDensity);
final medianTextLen = calculateMedian(allBlocks.textLen);

// Filter blocks that deviate significantly from the page's norm
final tooManyLinks = (linkDensity > medianLinkDensity + 0.20);
```

This makes filtering **universal** - works on any site without configuration.

## Examples of What Gets Filtered

### ✅ Kept (Real Content)
- Paragraphs with low link density (< 45%)
- Text with good text density (> 3.0 chars/tag)
- Sentence-like text (has punctuation, not all caps)

### ❌ Filtered (Noise)
- Navigation menus (high link density, many short items)
- Related articles lists (many links, short text)
- Widgets/sidebars (low text density, many tags)
- Labels/buttons (short, no punctuation, all caps)

## Testing

To verify the improvement:

```dart
// Before: might include "Related Articles", "You may also like", etc.
final oldText = result.mainText;

// After: clean paragraphs only
final newParagraphs = result.paragraphs;

print('Old: ${oldText.split('\n').length} blocks');
print('New: ${newParagraphs.length} paragraphs');
```

## Performance

- ✅ Uses same HTML parsing (no extra cost)
- ✅ Single-pass algorithm (O(n) where n = number of blocks)
- ✅ Works well with `compute()` for isolate execution
- ✅ Median calculation is fast (O(n log n) but n is small)

## Backward Compatibility

The old API still works:

```dart
// Still works - mainText is populated
final text = result.mainText; // String with \n\n separators

// New feature - paragraphs list
final paras = result.paragraphs; // List<String>
```

## References

Based on:
- [Mozilla Readability](https://github.com/mozilla/readability) - Firefox Reader View
- [Readability4J](https://github.com/dankito/Readability4J) - Kotlin port
- [xayn_readability](https://github.com/xaynetwork/xayn_readability) - Dart port

## Future Enhancements

Potential improvements:
- [ ] Image extraction per paragraph
- [ ] Heading structure preservation
- [ ] List/quote block type detection
- [ ] Configurable filtering thresholds
