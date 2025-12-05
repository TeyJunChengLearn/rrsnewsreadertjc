import '../models/feed_item.dart';
import 'article_dao.dart';
import 'readability_service.dart';

class ArticleContentService {
  final Readability4JExtended readability;
  final ArticleDao articleDao;

  ArticleContentService({required this.readability, required this.articleDao});

  /// Fetches main article text/images for any FeedItem missing them.
  /// Returns a map of article id -> extracted content for rows that were updated.
  Future<Map<String, ArticleReadabilityResult>> backfillMissingContent(
    List<FeedItem> items,
  ) async {
    final updated = <String, ArticleReadabilityResult>{};

    for (final item in items) {
      if (item.link.isEmpty) continue;
      final existingText = (item.mainText ?? '').trim();
      final needsBetterText = _looksLikeTeaser(existingText);
      final needsImage = (item.imageUrl ?? '').trim().isEmpty;

      if (!needsBetterText && !needsImage) continue;

      final content = await readability.extractMainContent(item.link);
      if (content == null) continue;

      final updates = <String, String?>{};
      final trimmedText = content.mainText?.trim();
      if ((needsBetterText || needsImage) && (trimmedText ?? '').isNotEmpty) {
        final longerThanExisting =
            (existingText.isEmpty) || ((trimmedText?.length ?? 0) > existingText.length);
        if (longerThanExisting || needsBetterText) {
          updates['mainText'] = trimmedText;
        }
      }

      final leadImage = content.imageUrl?.trim();
      if (needsImage && (leadImage ?? '').isNotEmpty) {
        updates['imageUrl'] = leadImage;
      }

      if (updates.isEmpty) continue;

      await articleDao.updateContent(item.id, updates['mainText'], updates['imageUrl']);
      updated[item.id] = ArticleReadabilityResult(
        mainText: updates['mainText'],
        imageUrl: updates['imageUrl'],
        pageTitle: content.pageTitle,
      );
    }

    return updated;
  }

  Future<void> saveExtractedContent({
    required String articleId,
    String? mainText,
    String? imageUrl,
  }) async {
    final trimmedText = mainText?.trim() ?? '';
    final trimmedImage = imageUrl?.trim() ?? '';

    if (trimmedText.isEmpty && trimmedImage.isEmpty) return;

    final existing = await articleDao.findById(articleId);
    if (existing == null) return;

    final updates = <String, String?>{};
    final currentText = (existing.mainText ?? '').trim();
    if (trimmedText.isNotEmpty) {
      final needsBetterText =
          _looksLikeTeaser(currentText) || trimmedText.length > currentText.length;
      if (needsBetterText) {
        updates['mainText'] = trimmedText;
      }
    }

    final hasImage = (existing.imageUrl ?? '').trim().isNotEmpty;
    if (!hasImage && trimmedImage.isNotEmpty) {
      updates['imageUrl'] = trimmedImage;
    }

    if (updates.isEmpty) return;

    await articleDao.updateContent(
      articleId,
      updates['mainText'],
      updates['imageUrl'],
    );
  }
}

bool _looksLikeTeaser(String? text) {
  if (text == null) return true;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return true;

  if (trimmed.length < 400) return true;

  final lower = trimmed.toLowerCase();
  const patterns = [
    'continue reading',
    'subscribe to read',
    'to continue reading',
    'login to read',
    'premium content',
  ];

  if (trimmed.endsWith('...') || trimmed.endsWith('…')) return true;

  for (final pattern in patterns) {
    if (lower.contains(pattern)) return true;
  }

  return false;
}