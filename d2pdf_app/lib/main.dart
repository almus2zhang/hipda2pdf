import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'd2pdf_converter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const D2PdfApp());
}

class D2PdfApp extends StatelessWidget {
  const D2PdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hi! PDA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF192D50),
          primary: const Color(0xFF192D50),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isLoggedIn = false;
  bool _isLoadingThreads = false;
  int _currentForumPage = 1;
  String _currentViewMode = 'discovery'; // 'discovery' or 'favorites'
  List<ForumThreadItem> _threadList = [];

  // PDF render width setting (default 600px mobile card layout, supports 600, 800, 1280, 1440, 1920)
  int _pdfWidth = 600;
  static const List<int> kSupportedWidths = [600, 800, 1280, 1440, 1920];

  // Font size setting (default 16px, supports 14, 16, 18, 20, 24, 28, 32, 36)
  int _fontSize = 16;
  static const List<int> kSupportedFontSizes = [14, 16, 18, 20, 24, 28, 32, 36];

  /// Tier-based auxiliary font sizing:
  /// - 14~18: default/compact tier -> user 15px, time/floor 12-13px
  /// - 20~28: medium tier (大一号) -> user 18px, time/floor 15-16px
  /// - 32~36: large tier (再大一号) -> user 22px, time/floor 18-19px
  static Map<String, int> getAuxiliaryFontSizes(int mainFontSize) {
    if (mainFontSize >= 32) {
      return {'username': 22, 'meta': 18, 'floor': 19};
    } else if (mainFontSize >= 20) {
      return {'username': 18, 'meta': 15, 'floor': 16};
    } else {
      return {'username': 15, 'meta': 12, 'floor': 13};
    }
  }

  // Conversion state
  bool _isConverting = false;
  bool _isCancelRequested = false;
  String _convertingThreadTitle = '';
  double _conversionProgress = 0.0;
  String _conversionStatus = '';

  InAppWebViewController? _converterWebViewController;
  Completer<void>? _pageLoadCompleter;

  static const String kDesktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _checkSavedLoginState();
  }

  Future<void> _checkSavedLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCookies = prefs.getStringList('saved_session_cookies');
    final hasCookie = (savedCookies != null && savedCookies.isNotEmpty) || (prefs.getBool('has_saved_login_cookie') ?? false);
    
    final savedWidth = prefs.getInt('pdf_render_width');
    if (savedWidth != null && kSupportedWidths.contains(savedWidth)) {
      _pdfWidth = savedWidth;
    } else {
      _pdfWidth = 600;
    }

    final savedFontSize = prefs.getInt('pdf_render_font_size');
    if (savedFontSize != null && kSupportedFontSizes.contains(savedFontSize)) {
      _fontSize = savedFontSize;
    } else {
      _fontSize = 16;
    }

    if (savedCookies != null && savedCookies.isNotEmpty) {
      await _restoreCookiesToManager(savedCookies);
    }

    if (!mounted) return;
    setState(() {
      _isLoggedIn = hasCookie;
    });

    if (hasCookie && _converterWebViewController != null) {
      _loadForumPage(1);
    }
  }

  static Future<void> _restoreCookiesToManager(List<String> rawCookies) async {
    final cookieManager = CookieManager.instance();
    for (final raw in rawCookies) {
      final parts = raw.split('=');
      if (parts.length >= 2) {
        final name = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
        if (name.isEmpty) continue;
        await cookieManager.setCookie(
          url: WebUri('https://www.4d4y.com'),
          name: name,
          value: value,
          domain: '.4d4y.com',
          path: '/',
        );
        await cookieManager.setCookie(
          url: WebUri('https://www.4d4y.com/forum/'),
          name: name,
          value: value,
          domain: 'www.4d4y.com',
          path: '/',
        );
      }
    }
    await D2PdfConverter.flushCookiesNative();
  }

  static Future<void> saveCurrentCookies() async {
    final cookieManager = CookieManager.instance();
    await D2PdfConverter.flushCookiesNative();
    final cookiesForum = await cookieManager.getCookies(
      url: WebUri('https://www.4d4y.com/forum/'),
    );
    final cookiesRoot = await cookieManager.getCookies(
      url: WebUri('https://www.4d4y.com/'),
    );
    final Map<String, String> cookieMap = {};
    for (final c in [...cookiesForum, ...cookiesRoot]) {
      if (c.name.isNotEmpty && c.value.isNotEmpty) {
        cookieMap[c.name] = c.value;
      }
    }
    final List<String> list = cookieMap.entries.map((e) => '${e.key}=${e.value}').toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_session_cookies', list);
    await prefs.setBool('has_saved_login_cookie', list.isNotEmpty);
  }

  // Open interactive Login WebView screen
  Future<void> _openLoginDialog() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const LoginWebViewScreen(),
      ),
    );

    if (result == true) {
      await saveCurrentCookies();
      if (!mounted) return;
      setState(() {
        _isLoggedIn = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录成功，已记录免登凭证！正在加载帖子...')),
      );
      _loadForumPage(1);
    }
  }

  // Clear cookie/session
  Future<void> _clearLoginSession() async {
    final cookieManager = CookieManager.instance();
    await cookieManager.deleteAllCookies();
    await D2PdfConverter.flushCookiesNative();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('has_saved_login_cookie');
    await prefs.remove('saved_session_cookies');
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _threadList.clear();
      _currentForumPage = 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录并清除Cookie')),
    );
  }

  // Load threads from forumdisplay.php or my.php?item=favorites&type=thread
  Future<void> _loadForumPage(int page) async {
    if (_isLoadingThreads || _isConverting) return;
    setState(() {
      _isLoadingThreads = true;
      _currentForumPage = page;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCookies = prefs.getStringList('saved_session_cookies');
      if (savedCookies != null && savedCookies.isNotEmpty) {
        await _restoreCookiesToManager(savedCookies);
      }

      final controller = _converterWebViewController;
      if (controller == null) {
        // Wait 1.5 second if controller is still initializing
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      final activeController = _converterWebViewController;
      if (activeController == null) {
        throw Exception('渲染内核尚未就绪，请稍后刷新重试');
      }

      final url = _currentViewMode == 'favorites'
          ? 'https://www.4d4y.com/forum/my.php?item=favorites&type=thread&page=$page'
          : 'https://www.4d4y.com/forum/forumdisplay.php?fid=2&page=$page';
      await _loadUrlInController(activeController, url);

      // Wait a moment for dynamic Discuz scripts to finish DOM rendering
      await Future.delayed(const Duration(milliseconds: 1200));

      final html = await activeController.getHtml() ?? '';
      final threads = _currentViewMode == 'favorites'
          ? D2PdfConverter.parseFavoriteThreads(html)
          : D2PdfConverter.parseForumThreads(html);

      setState(() {
        _isLoadingThreads = false;
        _threadList = threads;
      });

      // Update saved cookies if we successfully loaded
      await saveCurrentCookies();

      if (threads.isEmpty && mounted) {
        final isAuthError = html.contains('您尚未登录') ||
            html.contains('没有权限访问该版块') ||
            html.contains('抱歉，本论坛只有特定用户可以访问');
        final isCloudflare = html.contains('Just a moment...') ||
            html.contains('Checking your browser');
        if (isCloudflare) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('遇到 Cloudflare 人机安全防护，请点击右上角登录菜单重新验证'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (isAuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('论坛提示需要登录后才能浏览，请点击右上角菜单进行登录'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          final emptyTip = _currentViewMode == 'favorites'
              ? '未解析到收藏帖子（可能暂无收藏或第 $page 页为空）'
              : '未解析到帖子列表，请点击“刷新重试”或右上角“输入网址生成”';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(emptyTip)),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoadingThreads = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载板块失败: $e')),
        );
      }
    }
  }

  void _toggleFavoritesView() {
    if (_isConverting) return;
    setState(() {
      if (_currentViewMode == 'favorites') {
        _currentViewMode = 'discovery';
      } else {
        _currentViewMode = 'favorites';
      }
      _currentForumPage = 1;
      _threadList.clear();
    });
    _loadForumPage(1);
  }

  // Dialog for direct URL input -> PDF generation
  Future<void> _openDirectUrlDialog() async {
    final textController = TextEditingController(
      text: '',
    );

    final submittedUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Color(0xFF192D50)),
            SizedBox(width: 8),
            Text('输入帖子网址生成 PDF', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持直接输入任意 4D4Y 帖子地址，将自动抓取该帖子所有分页并生成完整 PDF：',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://www.4d4y.com/forum/viewthread.php?tid=...',
                prefixIcon: Icon(Icons.public),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () {
              final val = textController.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx, val);
              }
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('开始生成'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF192D50),
            ),
          ),
        ],
      ),
    );

    if (submittedUrl != null && submittedUrl.isNotEmpty) {
      final tidMatch = RegExp(r'tid=(\d+)').firstMatch(submittedUrl);
      final tid = tidMatch != null ? tidMatch.group(1)! : 'custom';
      final item = ForumThreadItem(
        tid: tid,
        title: '帖子_$tid',
        author: '用户指定',
        replies: '-',
        views: '-',
        url: submittedUrl,
      );
      _startGeneratePdf(item);
    }
  }

  // Dialog to configure PDF width & font size
  Future<void> _openSettingsDialog() async {
    int tempWidth = _pdfWidth;
    int tempFontSize = _fontSize;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.tune, color: Color(0xFF192D50)),
              SizedBox(width: 8),
              Text('排版与字体设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '正文字体大小：',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kSupportedFontSizes.map((size) {
                    final isSelected = size == tempFontSize;
                    return ChoiceChip(
                      label: Text('${size}px${size == 16 ? ' (默认)' : ''}'),
                      selected: isSelected,
                      selectedColor: const Color(0xFF192D50),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() {
                            tempFontSize = size;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const Divider(height: 24),
                const Text(
                  '页面宽度排版：',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                ...[
                  {'width': 600, 'label': '600 px', 'desc': '手机卡片排版 (42px圆头像，紧凑楼层)'},
                  {'width': 800, 'label': '800 px', 'desc': '紧凑排版，字体与图片更大'},
                  {'width': 1280, 'label': '1280 px', 'desc': '标准宽屏'},
                  {'width': 1440, 'label': '1440 px', 'desc': '高清宽屏，适合平板/高分屏'},
                  {'width': 1920, 'label': '1920 px', 'desc': '超宽全景模式'},
                ].map((opt) {
                  final w = opt['width'] as int;
                  final isCurrent = w == tempWidth;
                  return RadioListTile<int>(
                    value: w,
                    groupValue: tempWidth,
                    title: Text(
                      opt['label'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? const Color(0xFF192D50) : null,
                      ),
                    ),
                    subtitle: Text(opt['desc'] as String, style: const TextStyle(fontSize: 11)),
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF192D50),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          tempWidth = val;
                        });
                      }
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF192D50)),
              child: const Text('保存设置'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pdf_render_width', tempWidth);
      await prefs.setInt('pdf_render_font_size', tempFontSize);
      setState(() {
        _pdfWidth = tempWidth;
        _fontSize = tempFontSize;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存设置：宽度 ${tempWidth}px，字号 ${tempFontSize}px')),
        );
      }
    }
  }

  void _finishCancellation(List<File> pagePdfs) {
    for (final f in pagePdfs) {
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    setState(() {
      _isConverting = false;
      _isCancelRequested = false;
      _conversionStatus = '已取消生成';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消本次 PDF 生成')),
      );
    }
  }

  // Start converting a specific thread to PDF in Download/D2PDF
  Future<void> _startGeneratePdf(ForumThreadItem item) async {
    if (_isConverting) return;

    setState(() {
      _isConverting = true;
      _isCancelRequested = false;
      _convertingThreadTitle = item.title;
      _conversionProgress = 0.05;
      _conversionStatus = '正在分析帖子总页数...';
    });

    try {
      final controller = _converterWebViewController;
      if (controller == null) {
        throw Exception('渲染器初始化失败');
      }

      // Restore cookies before loading thread
      final prefs = await SharedPreferences.getInstance();
      final savedCookies = prefs.getStringList('saved_session_cookies');
      if (savedCookies != null && savedCookies.isNotEmpty) {
        await _restoreCookiesToManager(savedCookies);
      }

      // Step 1: Load Page 1
      final page1Url = D2PdfConverter.buildPageUrl(item.url, 1);
      setState(() {
        _conversionStatus = '正在拉取第 1 页数据 (若内容/图片较多请稍候)...';
      });
      await _loadUrlInController(controller, page1Url);

      if (_isCancelRequested) {
        _finishCancellation([]);
        return;
      }

      await Future.delayed(const Duration(milliseconds: 1000));

      // Step 2: Extract real title & total pages
      final html = await controller.getHtml() ?? '';
      
      // Check if page prompt says login is required or blocked by CF
      if (html.contains('Just a moment...') || html.contains('Checking your browser')) {
        throw Exception('遇到 Cloudflare 人机安全防护拦截，请先点击右上角菜单进行“论坛登录与CF验证”！');
      }
      if (html.contains('您尚未登录') ||
          html.contains('您需要先登录') ||
          html.contains('只有特定用户可以访问') ||
          html.contains('没有权限访问该版块')) {
        throw Exception('论坛提示需要先登录才能查看该内容。请先点击右上角菜单进行“论坛登录”！');
      }

      final totalPages = D2PdfConverter.extractTotalPages(html);

      // Extract thread title from page title tag if needed
      var actualTitle = item.title;
      final pageTitleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(html);
      if (pageTitleMatch != null) {
        var t = pageTitleMatch.group(1) ?? '';
        t = t.replaceAll(' - 4D4Y', '').replaceAll(' - Discovery', '').trim();
        if (t.isNotEmpty && !t.contains('提示信息')) {
          actualTitle = t;
        }
      }

      if (_isCancelRequested) {
        _finishCancellation([]);
        return;
      }

      setState(() {
        _convertingThreadTitle = actualTitle;
        _conversionStatus = '检测到共 $totalPages 页，开始渲染并导出...';
        _conversionProgress = 0.1;
      });

      final tempDir = await getTemporaryDirectory();
      final List<File> pagePdfs = [];

      for (int page = 1; page <= totalPages; page++) {
        if (_isCancelRequested) {
          _finishCancellation(pagePdfs);
          return;
        }

        setState(() {
          _conversionStatus = '正在拉取第 $page / $totalPages 页数据 (若内容/图片较多请耐心等待)...';
          _conversionProgress = 0.1 + (0.75 * (page - 1) / totalPages);
        });

        if (page > 1) {
          final pageUrl = D2PdfConverter.buildPageUrl(item.url, page);
          await _loadUrlInController(controller, pageUrl);
        }

        if (_isCancelRequested) {
          _finishCancellation(pagePdfs);
          return;
        }

        // Query image count to provide accurate progress feedback
        int imgCount = 0;
        try {
          final countVal = await controller.evaluateJavascript(source: """
            (function() {
              return document.querySelectorAll('img[file], .postmessage img, .t_msgfont img').length || document.images.length || 0;
            })();
          """);
          if (countVal is int) {
            imgCount = countVal;
          } else if (countVal is num) {
            imgCount = countVal.toInt();
          }
        } catch (_) {}

        if (imgCount > 0) {
          setState(() {
            _conversionStatus = '第 $page 页检测到含 $imgCount 张图片，正在缓冲与拉取高清大图...';
          });
        }

        // Wait dynamically based on images on page (up to 3.5s for heavy image galleries)
        final waitMs = (imgCount > 10) ? 3500 : ((imgCount > 3) ? 2500 : 1500);
        await Future.delayed(Duration(milliseconds: waitMs));

        if (_isCancelRequested) {
          _finishCancellation(pagePdfs);
          return;
        }

        setState(() {
          _conversionStatus = '正在排版第 $page / $totalPages 页 (${_pdfWidth}px 宽屏, 左对齐)...';
        });

        final auxSizes = _MainScreenState.getAuxiliaryFontSizes(_fontSize);
        final int usernameSize = auxSizes['username']!;
        final int metaSize = auxSizes['meta']!;
        final int floorSize = auxSizes['floor']!;
        final String jsTitle = jsonEncode(actualTitle);

        final String extraCss = (_pdfWidth == 600)
            ? '''
              .postauthor, td.postauthor {
                display: none !important;
              }
              .postcontent, td.postcontent {
                display: block !important;
                width: 600px !important;
                max-width: 600px !important;
                box-sizing: border-box !important;
              }
              .postmessage, .t_msgfont, .t_msgfontfix {
                padding: 10px 14px 14px 14px !important;
                box-sizing: border-box !important;
                font-size: ${_fontSize}px !important;
                line-height: 1.65 !important;
              }
              img {
                max-width: 572px !important;
                height: auto !important;
              }
            '''
            : '''
              .postauthor, .postauthor * {
                text-align: left !important;
              }
              .postmessage, .t_msgfont, .t_msgfontfix {
                font-size: ${_fontSize}px !important;
                line-height: 1.65 !important;
              }
            ''';

        // Inject styles: ${_pdfWidth}px width, zero margin, text-align left
        await controller.evaluateJavascript(source: """
          (function() {
            document.querySelectorAll('img[file]').forEach(function(img) {
              if (img.getAttribute('file')) {
                img.src = img.getAttribute('file');
              }
            });

            var hideSelectors = [
              '#header', '#umenu', '#menu', '#footer',
              '.postactions', '.modact', '.pages', '.pageback', '#quickpost',
              '.pages_btns', '#postlist_act', '.postbtn', '#newspecial', '#post_reply',
              '.threadactions', '#visitedforums', '.forumcontrol', '#f_post',
              'form[action*="post.php"]'
            ];
            hideSelectors.forEach(function(sel) {
              document.querySelectorAll(sel).forEach(function(el) {
                el.style.display = 'none';
              });
            });

            // Remove any elements after #postlist (such as bottom reply form, bottom pagination, return to list)
            var postlistEl = document.getElementById('postlist');
            if (postlistEl && postlistEl.parentNode) {
              var sib = postlistEl.nextElementSibling;
              while (sib) {
                var next = sib.nextElementSibling;
                sib.remove();
                sib = next;
              }
            }

            // Remove top & bottom reply/newpost buttons and "返回列表"
            document.querySelectorAll('a, button, span, div, p').forEach(function(el) {
              var t = el.innerText ? el.innerText.trim() : '';
              if (t === '发表回复' || t === '发表新帖' || t === '发新帖' || t === '发帖' || t === '回复' ||
                  t === '返回列表' || t.indexOf('返回列表') !== -1) {
                var container = el.closest('.pages_btns') || el.closest('.postbtn') || el.closest('.forumcontrol') || el.closest('#postlist_act') || el;
                container.style.display = 'none';
              }
            });

            document.querySelectorAll('a').forEach(function(a) {
              if (a.innerText && a.innerText.indexOf('只看该作者') !== -1) {
                a.style.display = 'none';
              }
            });

            var is600 = ($_pdfWidth === 600);
            if (is600) {
              // 600px Mobile Card Layout
              var tables = document.querySelectorAll('#postlist table[id^="pid"], table[id^="pid"]');
              if (tables.length === 0) {
                tables = document.querySelectorAll('table.viewthread, #postlist > table');
              }

              tables.forEach(function(table) {
                var authorTd = table.querySelector('.postauthor');
                var contentTd = table.querySelector('.postcontent');
                if (!contentTd) return;

                // Extract Avatar (img with file attribute or src)
                var avatarSrc = '';
                if (authorTd) {
                  var avImg = authorTd.querySelector('.avatar img') || authorTd.querySelector('img[src*="avatar"]') || authorTd.querySelector('img');
                  if (avImg) {
                    avatarSrc = avImg.getAttribute('file') || avImg.src;
                  }
                }

                // Extract Username
                var username = '';
                if (authorTd) {
                  var userLink = authorTd.querySelector('.postinfo a') || authorTd.querySelector('cite a') || authorTd.querySelector('a[href*="space.php"]');
                  if (userLink) {
                    username = userLink.innerText.trim();
                  }
                }
                if (!username && contentTd) {
                  var cl = contentTd.querySelector('a[href*="space.php"]');
                  if (cl) username = cl.innerText.trim();
                }

                // Extract Post Time & Floor Number from postinfo
                var postInfo = contentTd.querySelector('.postinfo');
                var postTime = '';
                var floorText = '';
                if (postInfo) {
                  var strongEl = postInfo.querySelector('strong');
                  if (strongEl) {
                    floorText = strongEl.innerText.replace(/\\s+/g, ' ').trim();
                  }

                  var emList = postInfo.querySelectorAll('em');
                  emList.forEach(function(em) {
                    var t = em.innerText.trim();
                    if (t.indexOf('发表于') !== -1 || /\\d{4}-\\d{1,2}-\\d{1,2}/.test(t)) {
                      postTime = t;
                    }
                  });
                  if (!postTime) {
                    var m = postInfo.innerText.match(/发表于\\s*[\\d\\-:\\s]+/);
                    if (m) postTime = m[0].trim();
                  }

                  postInfo.style.display = 'none';
                }

                // Hide author sidebar
                if (authorTd) {
                  authorTd.style.display = 'none';
                }

                // Style table and content container
                table.style.width = '600px';
                table.style.display = 'block';
                table.style.margin = '0 0 10px 0';
                table.style.border = 'none';
                table.style.background = '#ffffff';

                contentTd.style.display = 'block';
                contentTd.style.width = '600px';
                contentTd.style.padding = '0';
                contentTd.style.boxSizing = 'border-box';

                // Insert compact card header: top line 12px to avatar, bottom line 6px to avatar
                if (!contentTd.querySelector('.d2pdf-custom-header')) {
                  var header = document.createElement('div');
                  header.className = 'd2pdf-custom-header';
                  header.style.cssText = 'display: flex !important; align-items: center !important; justify-content: space-between !important; ' +
                    'padding-top: 12px !important; padding-bottom: 6px !important; padding-left: 14px !important; padding-right: 14px !important; ' +
                    'width: 600px !important; box-sizing: border-box !important; ' +
                    'border-top: 1px solid #e5e7eb !important; border-bottom: 1px solid #f0f0f0 !important; ' +
                    'background: #ffffff !important; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif !important;';

                  // Left part: Avatar + Username
                  var left = document.createElement('div');
                  left.style.cssText = 'display: flex !important; align-items: center !important; flex: 1 !important; min-width: 0 !important;';

                  if (avatarSrc) {
                    var img = document.createElement('img');
                    img.src = avatarSrc;
                    img.style.cssText = 'width: 42px !important; height: 42px !important; min-width: 42px !important; min-height: 42px !important; border-radius: 50% !important; object-fit: cover !important; margin-right: 8px !important; display: block !important; border: 1px solid #e5e7eb !important;';
                    left.appendChild(img);
                  } else {
                    var placeholder = document.createElement('div');
                    placeholder.className = 'd2pdf-header-placeholder';
                    placeholder.style.cssText = 'width: 42px !important; height: 42px !important; min-width: 42px !important; min-height: 42px !important; border-radius: 50% !important; background: #e0e7ff !important; color: #3730a3 !important; display: flex !important; align-items: center !important; justify-content: center !important; font-weight: bold !important; margin-right: 8px !important;';
                    placeholder.style.fontSize = '${usernameSize}px';
                    placeholder.innerText = username ? username.substring(0, 1).toUpperCase() : '?';
                    left.appendChild(placeholder);
                  }

                  var name = document.createElement('span');
                  name.className = 'd2pdf-header-username';
                  name.style.cssText = 'font-weight: bold !important; color: #111827 !important; overflow: hidden !important; text-overflow: ellipsis !important; white-space: nowrap !important; margin-right: 8px !important;';
                  name.style.fontSize = '${usernameSize}px';
                  name.innerText = username || '用户';
                  left.appendChild(name);

                  header.appendChild(left);

                  // Right part: Post Time + Floor
                  var right = document.createElement('div');
                  right.className = 'd2pdf-header-right';
                  right.style.cssText = 'display: flex !important; align-items: center !important; gap: 8px !important; color: #6b7280 !important; flex-shrink: 0 !important;';
                  right.style.fontSize = '${metaSize}px';

                  if (postTime) {
                    var timeSpan = document.createElement('span');
                    timeSpan.className = 'd2pdf-header-time';
                    timeSpan.style.cssText = 'color: #6b7280 !important; white-space: nowrap !important;';
                    timeSpan.style.fontSize = '${metaSize}px';
                    timeSpan.innerText = postTime;
                    right.appendChild(timeSpan);
                  }

                  if (floorText) {
                    var floorSpan = document.createElement('span');
                    floorSpan.className = 'd2pdf-header-floor';
                    floorSpan.style.cssText = 'font-weight: bold !important; color: #0369a1 !important; white-space: nowrap !important;';
                    floorSpan.style.fontSize = '${floorSize}px';
                    floorSpan.innerText = floorText;
                    right.appendChild(floorSpan);
                  }

                  header.appendChild(right);

                  contentTd.insertBefore(header, contentTd.firstChild);
                }
              });
            }

            // Update auxiliary font sizes dynamically on existing DOM elements
            document.querySelectorAll('.d2pdf-header-username').forEach(function(el) {
              el.style.fontSize = '${usernameSize}px';
            });
            document.querySelectorAll('.d2pdf-header-time').forEach(function(el) {
              el.style.fontSize = '${metaSize}px';
            });
            document.querySelectorAll('.d2pdf-header-floor').forEach(function(el) {
              el.style.fontSize = '${floorSize}px';
            });
            document.querySelectorAll('.d2pdf-header-placeholder').forEach(function(el) {
              el.style.fontSize = '${usernameSize}px';
            });
            document.querySelectorAll('.d2pdf-header-right').forEach(function(el) {
              el.style.fontSize = '${metaSize}px';
            });
            document.querySelectorAll('.postinfo strong, .postinfo strong a').forEach(function(el) {
              el.style.fontSize = '${floorSize}px';
            });
            document.querySelectorAll('.postinfo em, .postinfo em span').forEach(function(el) {
              el.style.fontSize = '${metaSize}px';
            });
            document.querySelectorAll('.postauthor cite, .postauthor cite a').forEach(function(el) {
              el.style.fontSize = '${usernameSize}px';
            });

            // Handle topmost navigation bar: remove 4D4Y >> Discovery, show ONLY the thread title, enlarged!
            var navEl = document.getElementById('nav') || document.querySelector('.nav');
            var passedTitle = $jsTitle;
            var finalTitle = passedTitle || '';
            if (!finalTitle) {
              var h1El = document.querySelector('#threadtitle h1, #threadtitle, h1, .threadtitle, #postlist h2');
              if (h1El && h1El.innerText && h1El.innerText.trim()) {
                finalTitle = h1El.innerText.trim();
              } else if (document.title) {
                finalTitle = document.title.split(' - ')[0].split(' _ ')[0].trim();
              }
            }

            if (navEl) {
              navEl.innerHTML = '';
              var topTitleDiv = document.createElement('div');
              topTitleDiv.className = 'd2pdf-top-title';
              topTitleDiv.innerText = finalTitle;
              navEl.appendChild(topTitleDiv);
            } else if (finalTitle) {
              var newNav = document.createElement('div');
              newNav.id = 'nav';
              newNav.className = 'nav';
              var topTitleDiv = document.createElement('div');
              topTitleDiv.className = 'd2pdf-top-title';
              topTitleDiv.innerText = finalTitle;
              newNav.appendChild(topTitleDiv);
              var wrapEl = document.getElementById('wrap') || document.querySelector('.wrap') || document.body;
              wrapEl.insertBefore(newNav, wrapEl.firstChild);
            }

            document.body.style.width = '${_pdfWidth}px';
            document.body.style.margin = '0px';
            document.body.style.padding = '0px';
            document.body.style.textAlign = 'left';
            document.documentElement.style.width = '${_pdfWidth}px';

            var styleEl = document.createElement('style');
            styleEl.innerHTML = `
              html, body {
                background: #ffffff !important;
                background-color: #ffffff !important;
                background-image: none !important;
                text-align: left !important;
                width: ${_pdfWidth}px !important;
                margin: 0 !important;
                padding: 0 !important;
                overflow-x: hidden !important;
              }
              #wrap, #postlist, .viewthread, .mainbox, table.viewthread, table[id^="pid"], #postlist > table {
                text-align: left !important;
                width: ${_pdfWidth}px !important;
                max-width: ${_pdfWidth}px !important;
                margin: 0 !important;
                padding: 0 !important;
                border: none !important;
                background: #ffffff !important;
                background-color: #ffffff !important;
              }
              table, tbody, tr, td, .postcontent, .postmessage, .t_msgfont, .t_msgfontfix, p, div, span, h1, h2, h3, h4 {
                text-align: left !important;
              }
              /* Top navigation: keep ONLY thread title, magnified */
              #nav, .nav {
                display: block !important;
                height: auto !important;
                min-height: unset !important;
                line-height: 1.4 !important;
                padding-top: 10px !important;
                padding-bottom: 12px !important;
                padding-left: 14px !important;
                padding-right: 14px !important;
                margin: 0 !important;
                background: transparent !important;
                border: none !important;
                text-align: left !important;
              }
              .d2pdf-top-title, #nav .d2pdf-top-title, .nav .d2pdf-top-title {
                font-size: 200% !important;
                line-height: 1.4 !important;
                font-weight: bold !important;
                color: #111827 !important;
                text-align: left !important;
                display: block !important;
                margin: 0 !important;
                padding: 0 !important;
                word-break: break-word !important;
              }
              .d2pdf-header-username {
                font-size: ${usernameSize}px !important;
              }
              .d2pdf-header-time, .d2pdf-header-right {
                font-size: ${metaSize}px !important;
              }
              .d2pdf-header-floor {
                font-size: ${floorSize}px !important;
              }
              .d2pdf-header-placeholder {
                font-size: ${usernameSize}px !important;
              }
              .postinfo strong, .postinfo strong a {
                font-size: ${floorSize}px !important;
              }
              .postinfo em, .postinfo em span {
                font-size: ${metaSize}px !important;
              }
              .postauthor cite, .postauthor cite a {
                font-size: ${usernameSize}px !important;
              }
              $extraCss
            `;
            document.head.appendChild(styleEl);

            var wrap = document.querySelector('.wrap') || document.querySelector('#wrap');
            if (wrap) {
              wrap.style.width = '${_pdfWidth}px';
              wrap.style.margin = '0px';
              wrap.style.padding = '0px';
              wrap.style.textAlign = 'left';
            }

            var postlist = document.getElementById('postlist');
            if (postlist) {
              postlist.style.width = '${_pdfWidth}px';
              postlist.style.margin = '0px';
              postlist.style.padding = '0px';
              postlist.style.textAlign = 'left';
            }
          })();
        """);

        await Future.delayed(const Duration(milliseconds: 500));

        // Measure page height
        final heightVal = await controller.evaluateJavascript(source: """
          Math.max(
            document.body.scrollHeight || 0,
            document.documentElement.scrollHeight || 0,
            document.body.offsetHeight || 0,
            1080
          );
        """);
        final double rawHeight = (heightVal is num)
            ? heightVal.toDouble()
            : double.tryParse(heightVal?.toString() ?? '1080') ?? 1080.0;
        final double contentHeight = rawHeight + 40.0;

        setState(() {
          _conversionStatus = '正在提取第 $page / $totalPages 页样式与排版...';
        });

        // Step 4: Extract rendered HTML and print to PDF via native Android PrintDocumentAdapter
        final String pageHtml = await controller.getHtml() ?? '';
        final pagePdfFile = File('${tempDir.path}/thread_${item.tid}_p$page.pdf');
        if (pagePdfFile.existsSync()) {
          pagePdfFile.deleteSync();
        }

        setState(() {
          _conversionStatus = '正在将第 $page / $totalPages 页保存为高精度 PDF...';
        });

        await D2PdfConverter.printHtmlToPdfNative(
          htmlContent: pageHtml,
          outputPath: pagePdfFile.path,
          widthPx: _pdfWidth.toDouble(),
          heightPx: contentHeight,
        );

        pagePdfs.add(pagePdfFile);

        if (_isCancelRequested) {
          _finishCancellation(pagePdfs);
          return;
        }
      }

      if (_isCancelRequested) {
        _finishCancellation(pagePdfs);
        return;
      }

      setState(() {
        _conversionStatus = '正在合并保存到手机 Download/D2PDF 目录...';
        _conversionProgress = 0.92;
      });

      // Target directory: Download/D2PDF
      final destDir = await D2PdfConverter.getDownloadD2PdfDirectory();
      final fileName = D2PdfConverter.sanitizeFileName(actualTitle);
      final finalPdfPath = '${destDir.path}/$fileName';

      final finalPdfFile = await D2PdfConverter.mergePdfs(pagePdfs, finalPdfPath);

      // Clean up temporary single page files
      for (final f in pagePdfs) {
        if (f.existsSync()) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }

      setState(() {
        _isConverting = false;
        _isCancelRequested = false;
        _conversionProgress = 1.0;
        _conversionStatus = '全部 $totalPages 页生成完毕！';
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('PDF 生成成功'),
            content: Text(
              '已成功生成并保存到手机目录：\n\n${finalPdfFile.path}\n\n文件名: $fileName',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openGeneratedPdf(finalPdfFile.path);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('立即打开'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (_isCancelRequested) {
        _finishCancellation([]);
        return;
      }
      setState(() {
        _isConverting = false;
        _conversionStatus = '生成失败: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成错误: $e')),
        );
      }
    }
  }

  Future<void> _loadUrlInController(InAppWebViewController controller, String url) async {
    _pageLoadCompleter = Completer<void>();
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    await _pageLoadCompleter!.future.timeout(
      const Duration(seconds: 40),
      onTimeout: () {},
    );
  }

  void _openGeneratedPdf(String path) {
    if (File(path).existsSync()) {
      OpenFilex.open(path);
    }
  }

  void _openThreadPreview(ForumThreadItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ThreadPreviewScreen(
          item: item,
          renderWidth: _pdfWidth,
          initialFontSize: _fontSize,
          onFontSizeChanged: (newSize) async {
            setState(() {
              _fontSize = newSize;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('pdf_render_font_size', newSize);
          },
          onWidthChanged: (newWidth) async {
            setState(() {
              _pdfWidth = newWidth;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('pdf_render_width', newWidth);
          },
          onGeneratePdf: (threadItem) {
            _startGeneratePdf(threadItem);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hi! PDA',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
        ),
        backgroundColor: const Color(0xFF192D50),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _currentViewMode == 'favorites' ? Icons.bookmark : Icons.bookmark_border,
              color: _currentViewMode == 'favorites' ? Colors.amber : Colors.white,
            ),
            tooltip: _currentViewMode == 'favorites' ? '返回Discovery板块' : '我的收藏',
            onPressed: _toggleFavoritesView,
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: '输入网址生成PDF',
            onPressed: _openDirectUrlDialog,
          ),
          if (_isLoggedIn)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新帖子列表',
              onPressed: () => _loadForumPage(_currentForumPage),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'direct_url') {
                _openDirectUrlDialog();
              } else if (val == 'settings') {
                _openSettingsDialog();
              } else if (val == 'login') {
                _openLoginDialog();
              } else if (val == 'logout') {
                _clearLoginSession();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'direct_url',
                child: Row(
                  children: [
                    Icon(Icons.link, size: 20, color: Color(0xFF192D50)),
                    SizedBox(width: 10),
                    Text('输入网址生成 PDF'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    const Icon(Icons.tune, size: 20, color: Color(0xFF192D50)),
                    const SizedBox(width: 10),
                    Text('排版与字体设置 (${_pdfWidth}px / ${_fontSize}px)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'login',
                child: Row(
                  children: [
                    const Icon(Icons.login, size: 20, color: Color(0xFF192D50)),
                    const SizedBox(width: 10),
                    Text(_isLoggedIn ? '重新登录/切换账号' : '登录论坛 (CF认证)'),
                  ],
                ),
              ),
              if (_isLoggedIn)
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: Colors.red),
                      SizedBox(width: 10),
                      Text('退出登录 (清除Cookie)'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background rendering InAppWebView (completely shielded and hidden from UI view and touch)
          Positioned(
            left: -9999,
            top: -9999,
            width: _pdfWidth.toDouble(),
            height: 1080,
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 0.0,
                child: InAppWebView(
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    cacheEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    userAgent: _MainScreenState.kDesktopUserAgent,
                  ),
                  onWebViewCreated: (controller) {
                    _converterWebViewController = controller;
                    // Auto trigger loading forum page 1 if already logged in
                    if (_isLoggedIn && _threadList.isEmpty && !_isLoadingThreads) {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted && _isLoggedIn) {
                          _loadForumPage(1);
                        }
                      });
                    }
                  },
                  onLoadStop: (controller, url) {
                    if (_pageLoadCompleter != null && !_pageLoadCompleter!.isCompleted) {
                      _pageLoadCompleter!.complete();
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (_pageLoadCompleter != null && !_pageLoadCompleter!.isCompleted) {
                      _pageLoadCompleter!.complete();
                    }
                  },
                ),
              ),
            ),
          ),

          // Main UI
          Column(
            children: [
              // Conversion Progress banner if active
              if (_isConverting) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.amber.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '正在生成: $_convertingThreadTitle',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _isCancelRequested
                                ? null
                                : () {
                                    setState(() {
                                      _isCancelRequested = true;
                                      _conversionStatus = '正在取消本次任务...';
                                    });
                                  },
                            icon: const Icon(Icons.close, size: 14, color: Colors.red),
                            label: Text(
                              _isCancelRequested ? '取消中' : '取消生成',
                              style: const TextStyle(fontSize: 12, color: Colors.red),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: _conversionProgress),
                      const SizedBox(height: 4),
                      Text(
                        _conversionStatus,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],

              // Not logged in view
              if (!_isLoggedIn)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF192D50).withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.forum, size: 60, color: Color(0xFF192D50)),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '欢迎使用 Hi! PDA',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '论坛需要登录且具备 Cloudflare 防护\n点击下方按钮登录后即可浏览首页帖子并一键导出 PDF',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _openLoginDialog,
                            icon: const Icon(Icons.login),
                            label: const Text('论坛登录 (CF认证与免登)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF192D50),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _openDirectUrlDialog,
                            icon: const Icon(Icons.link),
                            label: const Text('输入任意帖子网址生成 PDF'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                // Threads list view
                Expanded(
                  child: Column(
                    children: [
                      // Forum sub-header & pagination control
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.grey.shade100,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_currentViewMode == 'favorites' ? '我的收藏' : 'Discovery'} (第 $_currentForumPage 页)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _openSettingsDialog,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF192D50).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.tune, size: 12, color: Color(0xFF192D50)),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${_pdfWidth}px · ${_fontSize}px',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF192D50), fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                                  tooltip: '上一页',
                                  onPressed: (_currentForumPage > 1 && !_isLoadingThreads && !_isConverting)
                                      ? () => _loadForumPage(_currentForumPage - 1)
                                      : null,
                                ),
                                Text(
                                  '$_currentForumPage',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                                  tooltip: '下一页',
                                  onPressed: (!_isLoadingThreads && !_isConverting)
                                      ? () => _loadForumPage(_currentForumPage + 1)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Thread items list
                      Expanded(
                        child: _isLoadingThreads
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 12),
                                    Text('正在加载 Discovery 板块帖子...', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              )
                            : _threadList.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.inbox, size: 48, color: Colors.grey),
                                        const SizedBox(height: 12),
                                        const Text('暂无帖子或正在解析...', style: TextStyle(fontSize: 15)),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          alignment: WrapAlignment.center,
                                          children: [
                                            ElevatedButton.icon(
                                              onPressed: () => _loadForumPage(_currentForumPage),
                                              icon: const Icon(Icons.refresh),
                                              label: const Text('刷新重试'),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: _openLoginDialog,
                                              icon: const Icon(Icons.login),
                                              label: const Text('登录 / CF验证'),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: _openDirectUrlDialog,
                                              icon: const Icon(Icons.link),
                                              label: const Text('输入网址生成'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _threadList.length,
                                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                                    itemBuilder: (ctx, index) {
                                      final item = _threadList[index];
                                      return ListTile(
                                        onTap: () => _openThreadPreview(item),
                                        title: Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                          child: Row(
                                            children: [
                                              Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                                              const SizedBox(width: 4),
                                              Text(
                                                item.author,
                                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                              ),
                                              const SizedBox(width: 16),
                                              Icon(Icons.chat_bubble_outline, size: 13, color: Colors.grey[600]),
                                              const SizedBox(width: 4),
                                              Text(
                                                '回复: ${item.replies} / 查看: ${item.views}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                              ),
                                            ],
                                          ),
                                        ),
                                        trailing: ElevatedButton.icon(
                                          onPressed: _isConverting ? null : () => _startGeneratePdf(item),
                                          icon: const Icon(Icons.picture_as_pdf, size: 16),
                                          label: const Text('生成PDF', style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            backgroundColor: const Color(0xFF192D50),
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class LoginWebViewScreen extends StatefulWidget {
  const LoginWebViewScreen({super.key});

  @override
  State<LoginWebViewScreen> createState() => _LoginWebViewScreenState();
}

class _LoginWebViewScreenState extends State<LoginWebViewScreen> {
  double _progress = 0.0;
  InAppWebViewController? _webViewController;
  bool _isAutoExiting = false;

  Future<bool> _checkIsActuallyLoggedIn(InAppWebViewController? controller) async {
    if (controller == null) return false;
    final currentUrl = (await controller.getUrl())?.toString() ?? '';

    // Check DOM for actual login state
    try {
      final result = await controller.evaluateJavascript(source: """
        (function() {
          // If there is an explicit logout link in DOM
          var hasLogoutLink = !!document.querySelector('a[href*="logging.php?action=logout"]');
          if (hasLogoutLink) return 'LOGGED_IN';

          // Check if umenu explicitly contains "退出" or "我的空间"
          var umenu = document.getElementById('umenu');
          if (umenu) {
            var txt = umenu.innerText || '';
            if (txt.indexOf('退出') !== -1 || txt.indexOf('我的空间') !== -1) {
              return 'LOGGED_IN';
            }
          }

          // Check if Discuz login success prompt is visible
          var bodyTxt = document.body ? document.body.innerText : '';
          if (bodyTxt.indexOf('欢迎您回来') !== -1 || bodyTxt.indexOf('现在将转入登录前页面') !== -1) {
            return 'LOGGED_IN';
          }

          // Check if still on login form
          var loginForm = document.querySelector('form[action*="logging.php"]') || document.querySelector('input[name="password"]');
          if (loginForm) {
            return 'LOGIN_FORM';
          }

          return 'UNKNOWN';
        })();
      """);

      if (result == 'LOGGED_IN') {
        return true;
      }
      if (result == 'LOGIN_FORM') {
        return false;
      }
    } catch (_) {}

    // If DOM check was inconclusive, check cookies:
    // Discuz auth cookie: e.g. cdb_auth, 4d4y_auth, or ending in 'auth'
    // Value must be substantial (>20 characters) and current URL must not be the login form page
    if (!currentUrl.contains('action=login')) {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri('https://www.4d4y.com/forum/'),
      );
      final hasAuthCookie = cookies.any((c) =>
          c.name.toLowerCase().endsWith('auth') &&
          c.value.trim().isNotEmpty &&
          c.value.length > 20);
      if (hasAuthCookie) {
        return true;
      }
    }

    return false;
  }

  Future<void> _handleConfirmLoggedIn() async {
    final isLoggedIn = await _checkIsActuallyLoggedIn(_webViewController);
    if (!mounted) return;
    if (isLoggedIn) {
      await D2PdfConverter.flushCookiesNative();
      await _MainScreenState.saveCurrentCookies();
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('登录状态确认'),
            ],
          ),
          content: const Text(
            '系统尚未在当前页面检测到登录成功标识（例如“退出”按钮或论坛身份Cookie）。\n\n'
            '• 如果您刚输入完账号密码，请点击网页中的【登录】提交按钮。\n'
            '• 如果页面卡在 Cloudflare 验证，请点击勾选人机验证框。\n'
            '• 如果您确认已经在网页中登录成功，可直接点击【强制确认为已登录】。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('返回网页继续'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _webViewController?.loadUrl(
                  urlRequest: URLRequest(url: WebUri('https://www.4d4y.com/forum/forumdisplay.php?fid=2')),
                );
              },
              child: const Text('前往 Discovery 板块'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await D2PdfConverter.flushCookiesNative();
                await _MainScreenState.saveCurrentCookies();
                if (mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('强制确认为已登录'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hi! PDA 论坛登录与验证'),
        backgroundColor: const Color(0xFF192D50),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新网页',
            onPressed: () => _webViewController?.reload(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.tonal(
              onPressed: _handleConfirmLoggedIn,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('已完成登录', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '网页后退',
                onPressed: () async {
                  if (await _webViewController?.canGoBack() ?? false) {
                    _webViewController?.goBack();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: '网页前进',
                onPressed: () async {
                  if (await _webViewController?.canGoForward() ?? false) {
                    _webViewController?.goForward();
                  }
                },
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _webViewController?.loadUrl(
                  urlRequest: URLRequest(url: WebUri('https://www.4d4y.com/forum/logging.php?action=login')),
                ),
                icon: const Icon(Icons.login, size: 16),
                label: const Text('登录页面', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _webViewController?.loadUrl(
                  urlRequest: URLRequest(url: WebUri('https://www.4d4y.com/forum/forumdisplay.php?fid=2')),
                ),
                icon: const Icon(Icons.forum, size: 16),
                label: const Text('Discovery板块', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_progress < 1.0) LinearProgressIndicator(value: _progress),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade50,
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '提示：请在下方网页中输入论坛账号密码登录。若遇到 CF 防护请点击验证。登录完成后会自动返回（或点击右上角“已完成登录”）。',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://www.4d4y.com/forum/logging.php?action=login'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                thirdPartyCookiesEnabled: true,
                cacheEnabled: true,
                userAgent: _MainScreenState.kDesktopUserAgent,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100;
                });
              },
              onLoadStop: (controller, url) async {
                if (_isAutoExiting) return;
                final isLoggedIn = await _checkIsActuallyLoggedIn(controller);
                if (isLoggedIn && mounted) {
                  _isAutoExiting = true;
                  await D2PdfConverter.flushCookiesNative();
                  await _MainScreenState.saveCurrentCookies();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('检测到登录成功！正在进入论坛...'),
                      duration: Duration(milliseconds: 1500),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await Future.delayed(const Duration(milliseconds: 800));
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ThreadPreviewScreen extends StatefulWidget {
  final ForumThreadItem item;
  final int renderWidth;
  final int initialFontSize;
  final ValueChanged<int> onFontSizeChanged;
  final ValueChanged<int>? onWidthChanged;
  final void Function(ForumThreadItem item) onGeneratePdf;

  const ThreadPreviewScreen({
    super.key,
    required this.item,
    required this.renderWidth,
    required this.initialFontSize,
    required this.onFontSizeChanged,
    this.onWidthChanged,
    required this.onGeneratePdf,
  });

  @override
  State<ThreadPreviewScreen> createState() => _ThreadPreviewScreenState();
}

class _ThreadPreviewScreenState extends State<ThreadPreviewScreen> {
  InAppWebViewController? _webViewController;
  double _progress = 0.0;
  late int _previewFontSize;
  late int _previewWidth;

  @override
  void initState() {
    super.initState();
    _previewFontSize = widget.initialFontSize;
    _previewWidth = widget.renderWidth;
  }

  Future<void> _injectStyles(InAppWebViewController controller) async {
    final int width = _previewWidth;
    final int fontSize = _previewFontSize;
    final auxSizes = _MainScreenState.getAuxiliaryFontSizes(fontSize);
    final int usernameSize = auxSizes['username']!;
    final int metaSize = auxSizes['meta']!;
    final int floorSize = auxSizes['floor']!;
    final String jsTitle = jsonEncode(widget.item.title);

    final bool is600 = (width == 600);
    final String extraCss = is600
        ? '''
          .postauthor, td.postauthor {
            display: none !important;
          }
          .postcontent, td.postcontent {
            display: block !important;
            width: 100% !important;
            max-width: 100% !important;
            box-sizing: border-box !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix {
            padding: 10px 14px 14px 14px !important;
            box-sizing: border-box !important;
            font-size: ${fontSize}px !important;
            line-height: 1.65 !important;
          }
          img {
            max-width: 100% !important;
            height: auto !important;
          }
        '''
        : '''
          .postauthor, td.postauthor {
            display: table-cell !important;
            width: 160px !important;
            max-width: 180px !important;
          }
          .postcontent, td.postcontent {
            display: table-cell !important;
            width: auto !important;
            box-sizing: border-box !important;
          }
          .postauthor, .postauthor * {
            text-align: left !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix {
            font-size: ${fontSize}px !important;
            line-height: 1.65 !important;
          }
          img {
            max-width: 100% !important;
            height: auto !important;
          }
        ''';

    await controller.evaluateJavascript(source: """
      (function() {
        // Load lazy images
        document.querySelectorAll('img[file]').forEach(function(img) {
          if (img.getAttribute('file')) {
            img.src = img.getAttribute('file');
          }
        });

        var hideSelectors = [
          '#header', '#umenu', '#menu', '#footer',
          '.postactions', '.modact', '#quickpost',
          '#postlist_act', '.postbtn', '#newspecial', '#post_reply',
          '.threadactions', '#visitedforums', '.forumcontrol', '#f_post',
          'form[action*="post.php"]'
        ];
        hideSelectors.forEach(function(sel) {
          document.querySelectorAll(sel).forEach(function(el) {
            el.style.display = 'none';
          });
        });

        // Hide all elements following #postlist (such as return to list, reply form, footer)
        var postlistEl = document.getElementById('postlist');
        if (postlistEl && postlistEl.parentNode) {
          var sib = postlistEl.nextElementSibling;
          while (sib) {
            var next = sib.nextElementSibling;
            sib.remove();
            sib = next;
          }
        }

        // Hide top & bottom reply/newpost buttons and '返回列表'
        document.querySelectorAll('a, button, span, div, p').forEach(function(el) {
          var t = el.innerText ? el.innerText.trim() : '';
          if (t === '发表回复' || t === '发表新帖' || t === '发新帖' || t === '发帖' || t === '回复' ||
              t === '返回列表' || t.indexOf('返回列表') !== -1) {
            var container = el.closest('.pages_btns') || el.closest('.postbtn') || el.closest('.forumcontrol') || el.closest('#postlist_act') || el;
            if (container) container.style.display = 'none';
          }
        });

        document.querySelectorAll('a').forEach(function(a) {
          if (a.innerText && a.innerText.indexOf('只看该作者') !== -1) {
            a.style.display = 'none';
          }
        });

        var is600 = ($width === 600);
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        meta.setAttribute('content', is600
          ? 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes'
          : 'width=' + $width + ', initial-scale=1.0, maximum-scale=3.0, user-scalable=yes'
        );

        document.documentElement.style.background = '#ffffff';
        document.documentElement.style.backgroundColor = '#ffffff';
        document.documentElement.style.backgroundImage = 'none';
        document.body.style.background = '#ffffff';
        document.body.style.backgroundColor = '#ffffff';
        document.body.style.backgroundImage = 'none';

        var tables = document.querySelectorAll('#postlist table[id^="pid"], table[id^="pid"]');
        if (tables.length === 0) {
          tables = document.querySelectorAll('table.viewthread, #postlist > table');
        }

        if (is600) {
          tables.forEach(function(table) {
            var authorTd = table.querySelector('.postauthor');
            var contentTd = table.querySelector('.postcontent');
            if (!contentTd) return;

            // Extract Avatar
            var avatarSrc = '';
            if (authorTd) {
              var avImg = authorTd.querySelector('.avatar img') || authorTd.querySelector('img[src*="avatar"]') || authorTd.querySelector('img');
              if (avImg) {
                avatarSrc = avImg.getAttribute('file') || avImg.src;
              }
            }

            // Extract Username
            var username = '';
            if (authorTd) {
              var userLink = authorTd.querySelector('.postinfo a') || authorTd.querySelector('cite a') || authorTd.querySelector('a[href*="space.php"]');
              if (userLink) {
                username = userLink.innerText.trim();
              }
            }
            if (!username && contentTd) {
              var cl = contentTd.querySelector('a[href*="space.php"]');
              if (cl) username = cl.innerText.trim();
            }

            // Extract Post Time & Floor
            var postInfo = contentTd.querySelector('.postinfo');
            var postTime = '';
            var floorText = '';
            if (postInfo) {
              var strongEl = postInfo.querySelector('strong');
              if (strongEl) {
                floorText = strongEl.innerText.replace(/\\s+/g, ' ').trim();
              }

              var emList = postInfo.querySelectorAll('em');
              emList.forEach(function(em) {
                var t = em.innerText.trim();
                if (t.indexOf('发表于') !== -1 || /\\d{4}-\\d{1,2}-\\d{1,2}/.test(t)) {
                  postTime = t;
                }
              });
              if (!postTime) {
                var m = postInfo.innerText.match(/发表于\\s*[\\d\\-:\\s]+/);
                if (m) postTime = m[0].trim();
              }

              postInfo.style.display = 'none';
            }

            if (authorTd) {
              authorTd.style.display = 'none';
            }

            table.style.width = '100%';
            table.style.display = 'block';
            table.style.margin = '0 0 10px 0';
            table.style.border = 'none';
            table.style.background = '#ffffff';

            contentTd.style.display = 'block';
            contentTd.style.width = '100%';
            contentTd.style.padding = '0';
            contentTd.style.boxSizing = 'border-box';

            var existingHeader = contentTd.querySelector('.d2pdf-custom-header');
            if (existingHeader) {
              existingHeader.style.display = 'flex';
            } else {
              var header = document.createElement('div');
              header.className = 'd2pdf-custom-header';
              header.style.cssText = 'display: flex !important; align-items: center !important; justify-content: space-between !important; ' +
                'padding-top: 12px !important; padding-bottom: 6px !important; padding-left: 14px !important; padding-right: 14px !important; ' +
                'width: 100% !important; box-sizing: border-box !important; ' +
                'border-top: 1px solid #e5e7eb !important; border-bottom: 1px solid #f0f0f0 !important; ' +
                'background: #ffffff !important; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif !important;';

              var left = document.createElement('div');
              left.className = 'd2pdf-header-left';
              left.style.cssText = 'display: flex !important; align-items: center !important; flex: 1 !important; min-width: 0 !important;';

              if (avatarSrc) {
                var img = document.createElement('img');
                img.src = avatarSrc;
                img.style.cssText = 'width: 42px !important; height: 42px !important; min-width: 42px !important; min-height: 42px !important; border-radius: 50% !important; object-fit: cover !important; margin-right: 8px !important; display: block !important; border: 1px solid #e5e7eb !important;';
                left.appendChild(img);
              } else {
                var placeholder = document.createElement('div');
                placeholder.className = 'd2pdf-header-placeholder';
                placeholder.style.cssText = 'width: 42px !important; height: 42px !important; min-width: 42px !important; min-height: 42px !important; border-radius: 50% !important; background: #e0e7ff !important; color: #3730a3 !important; display: flex !important; align-items: center !important; justify-content: center !important; font-weight: bold !important; margin-right: 8px !important;';
                placeholder.style.fontSize = '${usernameSize}px';
                placeholder.innerText = username ? username.substring(0, 1).toUpperCase() : '?';
                left.appendChild(placeholder);
              }

              var name = document.createElement('span');
              name.className = 'd2pdf-header-username';
              name.style.cssText = 'font-weight: bold !important; color: #111827 !important; overflow: hidden !important; text-overflow: ellipsis !important; white-space: nowrap !important; margin-right: 8px !important;';
              name.style.fontSize = '${usernameSize}px';
              name.innerText = username || '用户';
              left.appendChild(name);

              header.appendChild(left);

              var right = document.createElement('div');
              right.className = 'd2pdf-header-right';
              right.style.cssText = 'display: flex !important; align-items: center !important; gap: 8px !important; color: #6b7280 !important; flex-shrink: 0 !important;';
              right.style.fontSize = '${metaSize}px';

              if (postTime) {
                var timeSpan = document.createElement('span');
                timeSpan.className = 'd2pdf-header-time';
                timeSpan.style.cssText = 'color: #6b7280 !important; white-space: nowrap !important;';
                timeSpan.style.fontSize = '${metaSize}px';
                timeSpan.innerText = postTime;
                right.appendChild(timeSpan);
              }

              if (floorText) {
                var floorSpan = document.createElement('span');
                floorSpan.className = 'd2pdf-header-floor';
                floorSpan.style.cssText = 'font-weight: bold !important; color: #0369a1 !important; white-space: nowrap !important;';
                floorSpan.style.fontSize = '${floorSize}px';
                floorSpan.innerText = floorText;
                right.appendChild(floorSpan);
              }

              header.appendChild(right);
              contentTd.insertBefore(header, contentTd.firstChild);
            }
          });
        } else {
          // Restore standard desktop layout
          tables.forEach(function(table) {
            var authorTd = table.querySelector('.postauthor');
            var contentTd = table.querySelector('.postcontent');
            if (!contentTd) return;

            var postInfo = contentTd.querySelector('.postinfo');
            if (postInfo) postInfo.style.display = '';
            if (authorTd) authorTd.style.display = '';

            table.style.width = '${width}px';
            table.style.maxWidth = '${width}px';
            table.style.display = '';
            table.style.margin = '0 0 10px 0';
            table.style.border = '';
            table.style.background = '#ffffff';

            contentTd.style.display = '';
            contentTd.style.width = '';
            contentTd.style.padding = '';
            contentTd.style.boxSizing = '';

            var existingHeader = contentTd.querySelector('.d2pdf-custom-header');
            if (existingHeader) {
              existingHeader.style.display = 'none';
            }
          });
        }

        if (is600) {
          document.body.style.width = '100%';
          document.documentElement.style.width = '100%';
          var wrap = document.querySelector('.wrap') || document.querySelector('#wrap');
          if (wrap) {
            wrap.style.width = '100%';
            wrap.style.margin = '0';
            wrap.style.padding = '0';
          }
          var postlist = document.getElementById('postlist');
          if (postlist) {
            postlist.style.width = '100%';
            postlist.style.margin = '0';
            postlist.style.padding = '0';
          }
        } else {
          document.body.style.width = '${width}px';
          document.documentElement.style.width = '${width}px';
          var wrap = document.querySelector('.wrap') || document.querySelector('#wrap');
          if (wrap) {
            wrap.style.width = '${width}px';
            wrap.style.margin = '0';
            wrap.style.padding = '0';
          }
          var postlist = document.getElementById('postlist');
          if (postlist) {
            postlist.style.width = '${width}px';
            postlist.style.margin = '0';
            postlist.style.padding = '0';
          }
        }

        // Update auxiliary font sizes dynamically on existing DOM elements
        document.querySelectorAll('.d2pdf-header-username').forEach(function(el) {
          el.style.fontSize = '${usernameSize}px';
        });
        document.querySelectorAll('.d2pdf-header-time').forEach(function(el) {
          el.style.fontSize = '${metaSize}px';
        });
        document.querySelectorAll('.d2pdf-header-floor').forEach(function(el) {
          el.style.fontSize = '${floorSize}px';
        });
        document.querySelectorAll('.d2pdf-header-placeholder').forEach(function(el) {
          el.style.fontSize = '${usernameSize}px';
        });
        document.querySelectorAll('.d2pdf-header-right').forEach(function(el) {
          el.style.fontSize = '${metaSize}px';
        });
        document.querySelectorAll('.postinfo strong, .postinfo strong a').forEach(function(el) {
          el.style.fontSize = '${floorSize}px';
        });
        document.querySelectorAll('.postinfo em, .postinfo em span').forEach(function(el) {
          el.style.fontSize = '${metaSize}px';
        });
        document.querySelectorAll('.postauthor cite, .postauthor cite a').forEach(function(el) {
          el.style.fontSize = '${usernameSize}px';
        });

        // Handle topmost navigation bar: remove 4D4Y >> Discovery, show ONLY the thread title, enlarged!
        var navEl = document.getElementById('nav') || document.querySelector('.nav');
        var passedTitle = $jsTitle;
        var finalTitle = passedTitle || '';
        if (!finalTitle) {
          var h1El = document.querySelector('#threadtitle h1, #threadtitle, h1, .threadtitle, #postlist h2');
          if (h1El && h1El.innerText && h1El.innerText.trim()) {
            finalTitle = h1El.innerText.trim();
          } else if (document.title) {
            finalTitle = document.title.split(' - ')[0].split(' _ ')[0].trim();
          }
        }

        if (navEl) {
          navEl.innerHTML = '';
          var topTitleDiv = document.createElement('div');
          topTitleDiv.className = 'd2pdf-top-title';
          topTitleDiv.innerText = finalTitle;
          navEl.appendChild(topTitleDiv);
        } else if (finalTitle) {
          var newNav = document.createElement('div');
          newNav.id = 'nav';
          newNav.className = 'nav';
          var topTitleDiv = document.createElement('div');
          topTitleDiv.className = 'd2pdf-top-title';
          topTitleDiv.innerText = finalTitle;
          newNav.appendChild(topTitleDiv);
          var wrapEl = document.getElementById('wrap') || document.querySelector('.wrap') || document.body;
          wrapEl.insertBefore(newNav, wrapEl.firstChild);
        }

        var styleEl = document.getElementById('d2pdf-custom-preview-style');
        if (!styleEl) {
          styleEl = document.createElement('style');
          styleEl.id = 'd2pdf-custom-preview-style';
          document.head.appendChild(styleEl);
        }
        styleEl.innerHTML = `
          html, body {
            background: #ffffff !important;
            background-color: #ffffff !important;
            background-image: none !important;
            margin: 0 !important;
            padding: 0 !important;
            text-align: left !important;
            width: ${is600 ? '100%' : '${width}px'} !important;
          }
          #wrap, #postlist, .viewthread, .mainbox, table.viewthread, table[id^="pid"], #postlist > table {
            width: ${is600 ? '100%' : '${width}px'} !important;
            max-width: ${is600 ? '100%' : '${width}px'} !important;
            margin: 0 !important;
            padding: 0 !important;
            border: none !important;
            box-sizing: border-box !important;
            background: #ffffff !important;
            background-color: #ffffff !important;
          }
          table, tbody, tr, td, .postcontent, .postmessage, .t_msgfont, .t_msgfontfix, p, div, span, h1, h2, h3, h4 {
            text-align: left !important;
          }
          /* Top navigation: keep ONLY thread title, magnified */
          #nav, .nav {
            display: block !important;
            height: auto !important;
            min-height: unset !important;
            line-height: 1.4 !important;
            padding-top: 10px !important;
            padding-bottom: 12px !important;
            padding-left: 14px !important;
            padding-right: 14px !important;
            margin: 0 !important;
            background: transparent !important;
            border: none !important;
            text-align: left !important;
          }
          .d2pdf-top-title, #nav .d2pdf-top-title, .nav .d2pdf-top-title {
            font-size: 200% !important;
            line-height: 1.4 !important;
            font-weight: bold !important;
            color: #111827 !important;
            text-align: left !important;
            display: block !important;
            margin: 0 !important;
            padding: 0 !important;
            word-break: break-word !important;
          }
          .d2pdf-header-username {
            font-size: ${usernameSize}px !important;
          }
          .d2pdf-header-time, .d2pdf-header-right {
            font-size: ${metaSize}px !important;
          }
          .d2pdf-header-floor {
            font-size: ${floorSize}px !important;
          }
          .d2pdf-header-placeholder {
            font-size: ${usernameSize}px !important;
          }
          .postinfo strong, .postinfo strong a {
            font-size: ${floorSize}px !important;
          }
          .postinfo em, .postinfo em span {
            font-size: ${metaSize}px !important;
          }
          .postauthor cite, .postauthor cite a {
            font-size: ${usernameSize}px !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix {
            font-size: ${fontSize}px !important;
            line-height: 1.65 !important;
          }
          $extraCss
        `;
      })();
    """);
  }

    void _updateFontSize(int newSize) {
    setState(() {
      _previewFontSize = newSize;
    });
    widget.onFontSizeChanged(newSize);
    if (_webViewController != null) {
      _injectStyles(_webViewController!);
    }
  }

  void _updateWidth(int newWidth) {
    setState(() {
      _previewWidth = newWidth;
    });
    widget.onWidthChanged?.call(newWidth);
    if (_webViewController != null) {
      _injectStyles(_webViewController!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.item.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF192D50),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新预览',
            onPressed: () => _webViewController?.reload(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onGeneratePdf(widget.item);
              },
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('生成PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '网页后退',
                onPressed: () async {
                  if (await _webViewController?.canGoBack() ?? false) {
                    _webViewController?.goBack();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: '网页前进',
                onPressed: () async {
                  if (await _webViewController?.canGoForward() ?? false) {
                    _webViewController?.goForward();
                  }
                },
              ),
              const SizedBox(width: 8),
              // Font size adjustment toolbar
              const Icon(Icons.format_size, size: 18, color: Color(0xFF192D50)),
              const SizedBox(width: 4),
              Text(
                '字号: ${_previewFontSize}px',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF192D50)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                tooltip: '调小字体',
                onPressed: () {
                  final curIdx = _MainScreenState.kSupportedFontSizes.indexOf(_previewFontSize);
                  if (curIdx > 0) {
                    _updateFontSize(_MainScreenState.kSupportedFontSizes[curIdx - 1]);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: '调大字体',
                onPressed: () {
                  final curIdx = _MainScreenState.kSupportedFontSizes.indexOf(_previewFontSize);
                  if (curIdx >= 0 && curIdx < _MainScreenState.kSupportedFontSizes.length - 1) {
                    _updateFontSize(_MainScreenState.kSupportedFontSizes[curIdx + 1]);
                  }
                },
              ),
              const Spacer(),
              // Width selection switcher
              PopupMenuButton<int>(
                tooltip: '切换排版宽度',
                initialValue: _previewWidth,
                onSelected: (int newWidth) {
                  _updateWidth(newWidth);
                },
                itemBuilder: (context) => _MainScreenState.kSupportedWidths.map((w) {
                  final bool isSelected = (w == _previewWidth);
                  final String label = (w == 600)
                      ? '600px (手机卡片版)'
                      : (w == 800)
                          ? '800px (标准宽屏)'
                          : (w == 1280)
                              ? '1280px (超宽排版)'
                              : (w == 1440)
                                  ? '1440px (2K 宽屏)'
                                  : '1920px (4K 宽屏)';
                  return PopupMenuItem<int>(
                    value: w,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected ? const Color(0xFF192D50) : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF192D50) : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blueGrey.shade200, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.aspect_ratio, size: 14, color: Color(0xFF192D50)),
                      const SizedBox(width: 4),
                      Text(
                        '${_previewWidth}px',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF192D50),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF192D50)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_progress < 1.0) LinearProgressIndicator(value: _progress),
          Expanded(
            child: Container(
              color: Colors.white,
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.item.url),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  useWideViewPort: true,
                  loadWithOverviewMode: true,
                  thirdPartyCookiesEnabled: true,
                  cacheEnabled: true,
                  userAgent: _MainScreenState.kDesktopUserAgent,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _progress = progress / 100;
                  });
                },
                onLoadStop: (controller, url) async {
                  await _injectStyles(controller);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
