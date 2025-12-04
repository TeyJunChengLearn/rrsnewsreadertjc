// test_malaysiakini.dart
import 'package:http/http.dart' as http;
import 'package:flutter_rss_reader/services/readability_service.dart';

void main() async {
  print('=== MalaysiaKini Content Extraction Test ===\n');
  
  // 创建可读性提取器，配置针对新闻网站
  final readability = Readability4JExtended(
    config: ReadabilityConfig(
      useMobileUserAgent: true,
      requestDelay: const Duration(seconds: 2),
      pageLoadDelay: const Duration(seconds: 1),
      paginationPageLimit: 5,
      customHeaders: {
        'Accept-Language': 'en-US,en;q=0.9,ms;q=0.8,zh;q=0.7',
        'Referer': 'https://www.malaysiakini.com/',
      },
    ),
  );

  // 测试多个不同文章
  final testUrls = [
    'https://www.malaysiakini.com/news/700000',
    'https://www.malaysiakini.com/news/699999',
    'https://www.malaysiakini.com/news/699998',
    'https://www.malaysiakini.com/news/700001',
  ];

  int successful = 0;
  int failed = 0;
  
  for (int i = 0; i < testUrls.length; i++) {
    final url = testUrls[i];
    print('\n📰 [Test ${i + 1}/${testUrls.length}] Testing: $url');
    print('─' * 50);
    
    try {
      final startTime = DateTime.now();
      final result = await readability.extractMainContent(url);
      final duration = DateTime.now().difference(startTime);
      
      if (result == null) {
        print('❌ Result is NULL');
        failed++;
        continue;
      }
      
      // 基本结果
      print('✅ Title: ${result.pageTitle ?? "No title"}');
      print('✅ Source: ${result.source ?? "Unknown"}');
      print('✅ Paywalled: ${result.isPaywalled ?? false}');
      print('✅ Content length: ${result.mainText?.length ?? 0} chars');
      print('✅ Image: ${result.imageUrl != null ? "Yes" : "No"}');
      if (result.imageUrl != null) print('   📸 ${result.imageUrl}');
      print('⏱️  Time: ${duration.inSeconds}s');
      
      // 内容分析
      if (result.mainText != null) {
        final text = result.mainText!;
        
        // 显示预览
        print('\n📝 Content preview (300 chars):');
        final preview = text.length > 300 ? '${text.substring(0, 300)}...' : text;
        print(preview);
        
        // 检查截断迹象
        final truncatedIndicators = [
          '...',
          '…',
          'continue reading',
          'read more',
          'read the full story',
          'subscribe',
          'premium',
          'members-only',
          'To continue reading',
        ];
        
        bool isTruncated = false;
        String? truncationType;
        
        for (final indicator in truncatedIndicators) {
          if (text.toLowerCase().contains(indicator.toLowerCase())) {
            isTruncated = true;
            truncationType = indicator;
            break;
          }
        }
        
        if (isTruncated) {
          print('\n⚠️  WARNING: Content appears TRUNCATED (found: "$truncationType")');
        } else {
          print('\n✓ Content appears COMPLETE');
        }
        
        // 检查段落数量
        final paragraphs = text.split('\n\n').where((p) => p.trim().isNotEmpty).length;
        print('📊 Paragraphs: $paragraphs');
        
        // 检查是否足够长（新闻文章通常至少300字）
        if (text.length < 300) {
          print('⚠️  Content may be too short for a news article');
        }
      }
      
      successful++;
      
    } catch (e) {
      print('❌ ERROR: $e');
      failed++;
    }
    
    // 延迟以避免被屏蔽
    if (i < testUrls.length - 1) {
      print('\n⏳ Waiting 3 seconds before next test...');
      await Future.delayed(const Duration(seconds: 3));
    }
  }
  
  // 总结
  print('\n' + '=' * 50);
  print('📊 TEST SUMMARY');
  print('=' * 50);
  print('✅ Successful: $successful');
  print('❌ Failed: $failed');
  print('📈 Success rate: ${((successful/testUrls.length)*100).toStringAsFixed(1)}%');
  
  // RSS源测试
  print('\n' + '=' * 50);
  print('📡 TESTING MalaysiaKini RSS FEEDS');
  print('=' * 50);
  
  final rssParser = RssFeedParser();
  final rssUrls = [
    'https://www.malaysiakini.com/rss/en/news.rss',
    'https://www.malaysiakini.com/rss/malay/news.rss',
    'https://www.malaysiakini.com/rss/chinese/news.rss',
    'https://www.malaysiakini.com/feed',
    'https://www.malaysiakini.com/rss',
  ];
  
  for (final rssUrl in rssUrls) {
    print('\nTesting RSS: $rssUrl');
    try {
      final response = await http.get(Uri.parse(rssUrl));
      if (response.statusCode == 200) {
        print('✅ Available (${response.body.length} bytes)');
        
        // 检查是否是有效的RSS
        if (response.body.contains('<rss') || response.body.contains('<feed')) {
          print('   ✓ Valid RSS/Atom format');
        } else {
          print('   ⚠️  Not a valid RSS format');
        }
      } else {
        print('❌ Unavailable: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error: $e');
    }
  }
  
  // 手动检查建议
  print('\n' + '=' * 50);
  print('🔍 MANUAL CHECK SUGGESTIONS');
  print('=' * 50);
  print('1. Open a MalaysiaKini article in browser');
  print('2. Press Ctrl+U to view page source');
  print('3. Search for:');
  print('   - "infinite-scroll"');
  print('   - "load-more"');
  print('   - "查看更多"');
  print('   - "read more"');
  print('   - "Continue reading"');
  print('4. Check Network tab for AJAX/XHR requests');
  print('5. Look for JSON-LD script tags');
}