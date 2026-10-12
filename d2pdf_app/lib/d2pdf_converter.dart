import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class ForumThreadItem {
  final String tid;
  final String title;
  final String author;
  final String replies;
  final String views;
  final String url;

  ForumThreadItem({
    required this.tid,
    required this.title,
    required this.author,
    required this.replies,
    required this.views,
    required this.url,
  });
}

class D2PdfConverter {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.d2pdf/native_printer');

  /// Flush Android native CookieManager
  static Future<void> flushCookiesNative() async {
    try {
      await _nativeChannel.invokeMethod('flushCookies');
    } catch (_) {}
  }

  /// Convert HTML to PDF using native Android PrintDocumentAdapter
  static Future<File> printHtmlToPdfNative({
    required String htmlContent,
    required String outputPath,
    required double widthPx,
    required double heightPx,
  }) async {
    // 1 inch = 96 px = 1000 mills. Therefore: mills = px * (1000 / 96)
    final int widthMills = (widthPx * (1000.0 / 96.0)).round();
    final int heightMills = (heightPx * (1000.0 / 96.0)).round();

    final result = await _nativeChannel.invokeMethod<String>('printHtmlToPdf', {
      'html': htmlContent,
      'outputPath': outputPath,
      'widthMills': widthMills,
      'heightMills': heightMills,
    });

    return File(result ?? outputPath);
  }

  /// Extract total pages and base URL from Discuz page html
  static int extractTotalPages(String html) {
    int maxPage = 1;
    final pageRegex = RegExp('viewthread\\.php\\?[^\'"\\s]*page=(\\d+)', caseSensitive: false);
    for (final match in pageRegex.allMatches(html)) {
      final p = int.tryParse(match.group(1) ?? '1') ?? 1;
      if (p > maxPage) {
        maxPage = p;
      }
    }
    final tagRegex = RegExp('<a[^>]*page=(\\d+)[^>]*>(\\d+)</a>');
    for (final match in tagRegex.allMatches(html)) {
      final p = int.tryParse(match.group(2) ?? '1') ?? 1;
      if (p > maxPage) {
        maxPage = p;
      }
    }
    return maxPage;
  }

  /// Normalize tid and build page URL
  static String buildPageUrl(String originalUrl, int page) {
    final uri = Uri.parse(originalUrl);
    final tid = uri.queryParameters['tid'];
    if (tid != null) {
      return 'https://www.4d4y.com/forum/viewthread.php?tid=$tid&page=$page';
    }
    if (originalUrl.contains('page=')) {
      return originalUrl.replaceAll(RegExp(r'page=\d+'), 'page=$page');
    }
    final sep = originalUrl.contains('?') ? '&' : '?';
    return '$originalUrl${sep}page=$page';
  }

  /// Parse threads from forumdisplay.php html (supporting both raw Discuz HTML & rendered DOM)
  static List<ForumThreadItem> parseForumThreads(String html) {
    final List<ForumThreadItem> list = [];
    final Set<String> seenTids = {};

    // 1. Primary parser: match <tbody id="normalthread_123"> or <tbody id="stickthread_123">
    final tbodyRegex = RegExp(
      r'<tbody[^>]*id="(?:normalthread|stickthread)_(\d+)"[^>]*>(.*?)</tbody>',
      dotAll: true,
      caseSensitive: false,
    );

    for (final match in tbodyRegex.allMatches(html)) {
      final tid = match.group(1) ?? '';
      if (seenTids.contains(tid)) continue;
      final content = match.group(2) ?? '';

      // Title & URL
      String title = '';
      final titleMatch = RegExp(
        r'<span[^>]*id="thread_\d+"[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
        dotAll: true,
      ).firstMatch(content);

      if (titleMatch != null) {
        title = titleMatch.group(2) ?? '';
        title = title.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      }

      if (title.isEmpty) {
        final fallbackTitle = RegExp(r'<a[^>]*viewthread\.php\?tid=\d+[^>]*>(.*?)</a>', dotAll: true).firstMatch(content);
        if (fallbackTitle != null) {
          title = fallbackTitle.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        }
      }

      if (title.isEmpty) continue;

      // Author
      String author = '匿名';
      final authorMatch = RegExp(r'<td class="author"[^>]*>.*?<cite[^>]*>(?:<a[^>]*>)?(.*?)(?:</a>)?</cite>', dotAll: true).firstMatch(content);
      if (authorMatch != null) {
        author = authorMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      }

      // Replies & views
      String replies = '0';
      String views = '0';
      final numsMatch = RegExp(r'<td class="nums"[^>]*><strong>(\d+)</strong>/<em>(\d+)</em>', dotAll: true).firstMatch(content);
      if (numsMatch != null) {
        replies = numsMatch.group(1) ?? '0';
        views = numsMatch.group(2) ?? '0';
      }

      seenTids.add(tid);
      list.add(ForumThreadItem(
        tid: tid,
        title: title,
        author: author,
        replies: replies,
        views: views,
        url: 'https://www.4d4y.com/forum/viewthread.php?tid=$tid',
      ));
    }

    // 2. Secondary fallback: if tbody matched nothing (e.g. DOM stripped or table reformatted)
    if (list.isEmpty) {
      final linkRegex = RegExp(
        r'<a[^>]*href="[^"]*viewthread\.php\?tid=(\d+)[^"]*"[^>]*>(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      );
      for (final match in linkRegex.allMatches(html)) {
        final tid = match.group(1) ?? '';
        if (seenTids.contains(tid)) continue;
        var title = match.group(2) ?? '';
        title = title.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (title.isEmpty || title == '最后发表' || title == '新帖' || title.length < 2) continue;

        seenTids.add(tid);
        list.add(ForumThreadItem(
          tid: tid,
          title: title,
          author: '楼主',
          replies: '-',
          views: '-',
          url: 'https://www.4d4y.com/forum/viewthread.php?tid=$tid',
        ));
      }
    }

    return list;
  }

  /// Parse threads from favorites page html (my.php?item=favorites&type=thread)
  static List<ForumThreadItem> parseFavoriteThreads(String html) {
    final List<ForumThreadItem> list = [];
    final Set<String> seenTids = {};

    // 1. In Discuz 7.2 favorites table, each thread is usually in a <tr> or <tbody>
    // with <th><a href="viewthread.php?tid=123"...>Title</a></th>
    // author in <td class="author"><a ...>Author</a></td> or <td class="forum">
    // and replies/views in <td class="nums">12/345</td>
    final trRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
    for (final match in trRegex.allMatches(html)) {
      final row = match.group(1) ?? '';
      final linkMatch = RegExp(r'<a[^>]*href="[^"]*viewthread\.php\?tid=(\d+)[^"]*"[^>]*>(.*?)</a>', dotAll: true, caseSensitive: false).firstMatch(row);
      if (linkMatch == null) continue;

      final tid = linkMatch.group(1) ?? '';
      if (seenTids.contains(tid)) continue;

      var title = linkMatch.group(2) ?? '';
      title = title.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (title.isEmpty || title == '最后发表' || title == '新帖') continue;

      // Author
      String author = '楼主';
      final authorMatch = RegExp(r'<td class="author"[^>]*>.*?<cite[^>]*>(?:<a[^>]*>)?(.*?)(?:</a>)?</cite>', dotAll: true).firstMatch(row) ??
          RegExp(r'<td class="author"[^>]*>(?:<a[^>]*>)?(.*?)(?:</a>)?</td>', dotAll: true).firstMatch(row);
      if (authorMatch != null) {
        author = authorMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      }

      // Replies & views
      String replies = '0';
      String views = '0';
      final numsMatch = RegExp(r'<td class="nums"[^>]*>(?:<strong>)?(\d+)(?:</strong>)?/(?:<em>)?(\d+)(?:</em>)?', dotAll: true).firstMatch(row);
      if (numsMatch != null) {
        replies = numsMatch.group(1) ?? '0';
        views = numsMatch.group(2) ?? '0';
      }

      seenTids.add(tid);
      list.add(ForumThreadItem(
        tid: tid,
        title: title,
        author: author,
        replies: replies,
        views: views,
        url: 'https://www.4d4y.com/forum/viewthread.php?tid=$tid',
      ));
    }

    // 2. Fallback: if table parsing returned empty, try generic thread links regex
    if (list.isEmpty) {
      final linkRegex = RegExp(
        r'<a[^>]*href="[^"]*viewthread\.php\?tid=(\d+)[^"]*"[^>]*>(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      );
      for (final match in linkRegex.allMatches(html)) {
        final tid = match.group(1) ?? '';
        if (seenTids.contains(tid)) continue;
        var title = match.group(2) ?? '';
        title = title.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (title.isEmpty || title == '最后发表' || title == '新帖' || title.length < 2) continue;

        seenTids.add(tid);
        list.add(ForumThreadItem(
          tid: tid,
          title: title,
          author: '楼主',
          replies: '-',
          views: '-',
          url: 'https://www.4d4y.com/forum/viewthread.php?tid=$tid',
        ));
      }
    }

    return list;
  }

  /// Get or create Download/D2PDF destination directory
  static Future<Directory> getDownloadD2PdfDirectory() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
    }

    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download/D2PDF');
      try {
        if (!downloadDir.existsSync()) {
          downloadDir.createSync(recursive: true);
        }
        return downloadDir;
      } catch (_) {}
    }

    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      final dir = Directory('${extDir.path}/Download/D2PDF');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/D2PDF');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Sanitize filename for safe saving
  static String sanitizeFileName(String title) {
    var name = title.replaceAll(RegExp(r'[\/\\:\*\?"<>\|\r\n\t]'), '_').trim();
    if (name.isEmpty) {
      name = 'thread_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (name.length > 50) {
      name = name.substring(0, 50);
    }
    return 'hipda-$name.pdf';
  }

  /// Merge multiple PDF files into one destination file while preserving each page's unique height and 1920px width
  static Future<File> mergePdfs(List<File> pdfFiles, String outputPath) async {
    final sf.PdfDocument finalDoc = sf.PdfDocument();
    finalDoc.pageSettings.margins.all = 0;

    for (final file in pdfFiles) {
      final bytes = await file.readAsBytes();
      final sf.PdfDocument loadedDoc = sf.PdfDocument(inputBytes: bytes);
      for (int i = 0; i < loadedDoc.pages.count; i++) {
        final loadedPage = loadedDoc.pages[i];
        final sf.PdfTemplate template = loadedPage.createTemplate();
        
        final sf.PdfSection section = finalDoc.sections!.add();
        section.pageSettings.margins.all = 0;
        section.pageSettings.size = loadedPage.size;
        
        final sf.PdfPage newPage = section.pages.add();
        newPage.graphics.drawPdfTemplate(
          template,
          const Offset(0, 0),
          loadedPage.size,
        );
      }
      loadedDoc.dispose();
    }

    final List<int> savedBytes = await finalDoc.save();
    finalDoc.dispose();

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(savedBytes, flush: true);
    return outputFile;
  }
}
