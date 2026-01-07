# Auto Enrichment Order Verification

## ✅ VERIFIED: Both foreground and background enrichment respect user's sort order

---

## 1. Foreground Enrichment (When App is Active)

**File:** `lib/providers/rss_provider.dart`

### Flow:

**Step 1: Filter articles needing enrichment** (Line 294-300)
```dart
final itemsNeedingEnrichment = _items.where((item) {
  final existingText = (item.mainText ?? '').trim();
  final hasContent = existingText.isNotEmpty; // Any content = skip
  return !hasContent || !hasImage;
}).toList();
```

**Step 2: Separate visible/hidden items** (Line 311-317)
```dart
for (final item in itemsNeedingEnrichment) {
  if (visibleIds.contains(item.id)) {
    visibleNeedingEnrichment.add(item);
  } else {
    hiddenNeedingEnrichment.add(item);
  }
}
```

**Step 3: Sort by user's preference** (Line 320-325)
```dart
final sortFn = (FeedItem a, FeedItem b) {
  final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
  final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
  final cmp = ad.compareTo(bd);
  return _sortOrder == SortOrder.latestFirst ? -cmp : cmp;
  //     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  //     If latestFirst: -cmp (newest first, descending)
  //     If oldestFirst: cmp (oldest first, ascending)
};

visibleNeedingEnrichment.sort(sortFn);
hiddenNeedingEnrichment.sort(sortFn);
```

**Step 4: Process in order** (Line 337-367)
```dart
for (final item in sortedItems) {
  // Enriches in the sorted order!
}
```

### Debug Logs:
```
RssProvider: Enrichment order: NEWEST first
```
or
```
RssProvider: Enrichment order: OLDEST first
```

---

## 2. Background Enrichment (When App is Closed)

**File:** `lib/services/background_task_service.dart`

### Flow:

**Step 1: Filter articles needing enrichment** (Line 77-83)
```dart
final needsContent = allArticles.where((item) {
  final existingText = (item.mainText ?? '').trim();
  final hasContent = existingText.isNotEmpty; // Any content = skip
  return !hasContent || !hasImage;
}).toList();
```

**Step 2: Read user's sort preference** (Line 88-90)
```dart
final prefs = await SharedPreferences.getInstance();
final sortOrderPref = prefs.getString('sortOrder') ?? 'latestFirst';
final isLatestFirst = sortOrderPref == 'latestFirst';
```

**Step 3: Sort by user's preference** (Line 93-98)
```dart
needsContent.sort((a, b) {
  final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
  final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
  final cmp = ad.compareTo(bd);
  return isLatestFirst ? -cmp : cmp;
  //     ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  //     If latestFirst: -cmp (newest first, descending)
  //     If oldestFirst: cmp (oldest first, ascending)
});
```

**Step 4: Take first 60 and process** (Line 103-135)
```dart
final toProcess = needsContent.take(60).toList();

for (final item in toProcess) {
  // Enriches in the sorted order!
}
```

### Debug Logs:
```
📊 Enrichment order: NEWEST first
📋 Processing 60 of 200 articles
```
or
```
📊 Enrichment order: OLDEST first
📋 Processing 60 of 200 articles
```

---

## 3. Sort Order Persistence

**File:** `lib/providers/rss_provider.dart`

### When user changes sort order (Line 384-395):
```dart
void setSortOrder(SortOrder order) async {
  _sortOrder = order;

  // Save to SharedPreferences for background task
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('sortOrder',
    order == SortOrder.latestFirst ? 'latestFirst' : 'oldestFirst');

  notifyListeners();
  _restartBackfillWithNewPriority(); // Restart foreground enrichment
}
```

**Saves to SharedPreferences:**
- User selects "Newest First" → saves `'latestFirst'`
- User selects "Oldest First" → saves `'oldestFirst'`

**Background task reads:**
```dart
final sortOrderPref = prefs.getString('sortOrder') ?? 'latestFirst';
```

---

## 4. Complete Examples

### Example A: User Selects "Newest First"

**Foreground Enrichment:**
```
Import/Refresh complete
→ 100 articles, 50 need enrichment
→ Read _sortOrder = SortOrder.latestFirst
→ Sort: newest → oldest (descending by date)
→ Start enriching:
   [1/50] Article from 2026-01-07 (today)
   [2/50] Article from 2026-01-06 (yesterday)
   [3/50] Article from 2026-01-05
   ...
   [50/50] Article from 2025-12-15 (oldest)
```

**Background Task (30 min later):**
```
Background task triggered
→ Read from SharedPreferences: 'latestFirst'
→ Filter: 30 articles need enrichment
→ Sort: newest → oldest (descending by date)
→ Take first 60 (only 30 available)
→ Start enriching:
   Article from 2026-01-07 10:00 (newest)
   Article from 2026-01-07 09:30
   Article from 2026-01-07 09:00
   ...
   Article from 2026-01-06 (oldest)
```

### Example B: User Selects "Oldest First"

**Foreground Enrichment:**
```
Import/Refresh complete
→ 100 articles, 50 need enrichment
→ Read _sortOrder = SortOrder.oldestFirst
→ Sort: oldest → newest (ascending by date)
→ Start enriching:
   [1/50] Article from 2025-12-15 (oldest)
   [2/50] Article from 2025-12-16
   [3/50] Article from 2025-12-17
   ...
   [50/50] Article from 2026-01-07 (newest)
```

**Background Task (30 min later):**
```
Background task triggered
→ Read from SharedPreferences: 'oldestFirst'
→ Filter: 30 articles need enrichment
→ Sort: oldest → newest (ascending by date)
→ Take first 60 (only 30 available)
→ Start enriching:
   Article from 2025-12-20 (oldest)
   Article from 2025-12-21
   Article from 2025-12-22
   ...
   Article from 2026-01-07 (newest)
```

---

## 5. Verification Checklist

### Foreground Enrichment ✅
- [x] Reads `_sortOrder` state
- [x] Filters articles needing enrichment FIRST
- [x] Separates visible/hidden items
- [x] Sorts by user preference (newest/oldest)
- [x] Processes in sorted order
- [x] Restarts when sort order changes
- [x] Debug logs show correct order

### Background Enrichment ✅
- [x] Reads from SharedPreferences
- [x] Filters articles needing enrichment FIRST
- [x] Sorts by saved preference (newest/oldest)
- [x] Takes first 60 after sorting
- [x] Processes in sorted order
- [x] Debug logs show correct order

### Persistence ✅
- [x] `setSortOrder()` saves to SharedPreferences
- [x] Background reads from SharedPreferences
- [x] Consistent key name: 'sortOrder'
- [x] Consistent values: 'latestFirst' / 'oldestFirst'
- [x] Default value: 'latestFirst'

### Sort Logic Consistency ✅
Both use identical logic:
```dart
return isLatestFirst ? -cmp : cmp;
```
- `latestFirst = true` → `-cmp` → descending (newest first)
- `latestFirst = false` → `cmp` → ascending (oldest first)

---

## 6. Conclusion

**✅ VERIFIED: Auto enrichment DOES respect user's filter setting**

**Newest First:**
- Foreground: Starts from newest article
- Background: Starts from newest article
- Continues chronologically backward (newest → oldest)

**Oldest First:**
- Foreground: Starts from oldest article
- Background: Starts from oldest article
- Continues chronologically forward (oldest → newest)

**Both foreground and background enrichment are perfectly synchronized and respect the user's sort preference at all times.**
