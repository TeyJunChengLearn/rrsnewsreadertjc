// lib/screens/trash_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_item.dart';
import '../providers/rss_provider.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<FeedItem> _trashedItems = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadTrashedItems();
  }

  Future<void> _loadTrashedItems() async {
    setState(() => _isLoading = true);
    final rss = context.read<RssProvider>();
    final items = await rss.getHiddenArticles();
    if (mounted) {
      setState(() {
        _trashedItems = items;
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      // Exit selection mode if nothing selected
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds = _trashedItems.map((e) => e.id).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _restoreSelected() async {
    if (_selectedIds.isEmpty) return;

    final itemsToRestore = _trashedItems
        .where((e) => _selectedIds.contains(e.id))
        .toList();

    final rss = context.read<RssProvider>();
    await rss.restoreMultipleFromTrash(itemsToRestore);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored ${itemsToRestore.length} article(s)')),
      );
      _clearSelection();
      await _loadTrashedItems();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently Delete'),
        content: Text(
          'Are you sure you want to permanently delete ${_selectedIds.length} article(s)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final itemsToDelete = _trashedItems
        .where((e) => _selectedIds.contains(e.id))
        .toList();

    final rss = context.read<RssProvider>();
    await rss.permanentlyDeleteMultiple(itemsToDelete);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${itemsToDelete.length} article(s)')),
      );
      _clearSelection();
      await _loadTrashedItems();
    }
  }

  Future<void> _deleteAll() async {
    if (_trashedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash'),
        content: Text(
          'Are you sure you want to permanently delete all ${_trashedItems.length} article(s) in trash? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final rss = context.read<RssProvider>();
    await rss.permanentlyDeleteAllHidden();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trash emptied')),
      );
      _clearSelection();
      await _loadTrashedItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode
            ? '${_selectedIds.length} selected'
            : 'Trash (${_trashedItems.length})'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
              tooltip: 'Select all',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _clearSelection,
              tooltip: 'Cancel selection',
            ),
          ] else if (_trashedItems.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: _deleteAll,
              tooltip: 'Empty trash',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trashedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Trash is empty',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTrashedItems,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _trashedItems.length,
                    itemBuilder: (context, index) {
                      final item = _trashedItems[index];
                      final isSelected = _selectedIds.contains(item.id);

                      return _TrashItemTile(
                        item: item,
                        isSelected: isSelected,
                        isSelectionMode: _isSelectionMode,
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelection(item.id);
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            _isSelectionMode = true;
                            _selectedIds.add(item.id);
                          });
                        },
                        onRestore: () async {
                          final rss = context.read<RssProvider>();
                          await rss.restoreFromTrash(item);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Article restored')),
                            );
                            await _loadTrashedItems();
                          }
                        },
                        onDelete: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Permanently Delete'),
                              content: const Text(
                                'Are you sure you want to permanently delete this article? This cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;

                          final rss = context.read<RssProvider>();
                          await rss.permanentlyDeleteArticle(item);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Article permanently deleted')),
                            );
                            await _loadTrashedItems();
                          }
                        },
                      );
                    },
                  ),
                ),
      bottomNavigationBar: _isSelectionMode && _selectedIds.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _restoreSelected,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _TrashItemTile extends StatelessWidget {
  final FeedItem item;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TrashItemTile({
    required this.item,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      leading: isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onTap(),
            )
          : CircleAvatar(
              backgroundColor: Colors.grey.shade300,
              backgroundImage:
                  item.imageUrl != null ? NetworkImage(item.imageUrl!) : null,
              child: item.imageUrl == null
                  ? Icon(Icons.article, color: Colors.grey.shade600)
                  : null,
            ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
      subtitle: Text(
        item.sourceTitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        ),
      ),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: isSelectionMode
          ? null
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'restore') {
                  onRestore();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'restore',
                  child: ListTile(
                    leading: Icon(Icons.restore),
                    title: Text('Restore'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('Delete permanently',
                        style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
    );
  }
}
