import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'd2pdf_converter.dart';
import 'layout_template.dart';
import 'template_renderer.dart';
import 'template_manage_screen.dart';

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
  String _currentViewMode = 'discovery'; // 'discovery', 'favorites', 'my_threads'
  List<ForumThreadItem> _threadList = [];

  // Multi-selection & batch generation state
  bool _isMultiSelectMode = false;
  final Set<String> _selectedTids = {};
  final Map<String, ForumThreadItem> _selectedItems = {};
  bool _isBatchConverting = false;
  int _batchTotalCount = 0;
  int _batchCurrentIndex = 0;
  final List<String> _batchSuccessTitles = [];
  final List<String> _batchFailedTitles = [];

  String get _currentViewModeLabel {
    switch (_currentViewMode) {
      case 'favorites':
        return '我的收藏';
      case 'my_threads':
        return '我的帖子';
      default:
        return 'Discovery';
    }
  }

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

  LayoutTemplate _selectedTemplate = TemplateManager.defaultCard;

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

    final activeTemplate = await TemplateManager.getActiveTemplate();
    _selectedTemplate = activeTemplate;

    if (savedCookies != null && savedCookies.isNotEmpty) {
      await _restoreCookiesToManager(savedCookies);
    }

    if (!mounted) return;
    setState(() {
      _isLoggedIn = hasCookie;
      _selectedTemplate = activeTemplate;
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

      final String url;
      if (_currentViewMode == 'favorites') {
        url = 'https://www.4d4y.com/forum/my.php?item=favorites&type=thread&page=$page';
      } else if (_currentViewMode == 'my_threads') {
        url = 'https://www.4d4y.com/forum/my.php?item=threads&page=$page';
      } else {
        url = 'https://www.4d4y.com/forum/forumdisplay.php?fid=2&page=$page';
      }
      await _loadUrlInController(activeController, url);

      // Wait a moment for dynamic Discuz scripts to finish DOM rendering
      await Future.delayed(const Duration(milliseconds: 1200));

      final html = await activeController.getHtml() ?? '';
      final List<ForumThreadItem> threads;
      if (_currentViewMode == 'favorites') {
        threads = D2PdfConverter.parseFavoriteThreads(html);
      } else if (_currentViewMode == 'my_threads') {
        threads = D2PdfConverter.parseMyThreads(html);
      } else {
        threads = D2PdfConverter.parseForumThreads(html);
      }

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
          final String emptyTip;
          if (_currentViewMode == 'favorites') {
            emptyTip = '未解析到收藏帖子（可能暂无收藏或第 $page 页为空）';
          } else if (_currentViewMode == 'my_threads') {
            emptyTip = '未解析到“我的帖子”（可能尚未发帖或第 $page 页为空）';
          } else {
            emptyTip = '未解析到帖子列表，请点击“刷新重试”或右上角“输入网址生成”';
          }
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

  void _switchViewMode(String mode) {
    if (_isConverting || _isBatchConverting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在执行 PDF 生成任务，请稍候切换板块')),
      );
      return;
    }
    if (_currentViewMode == mode) return;
    setState(() {
      _currentViewMode = mode;
      _currentForumPage = 1;
      _exitMultiSelectMode();
      _threadList.clear();
    });
    _loadForumPage(1);
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedTids.clear();
      _selectedItems.clear();
    });
  }

  void _enterMultiSelectMode([ForumThreadItem? item]) {
    if (_isConverting || _isBatchConverting) return;
    setState(() {
      _isMultiSelectMode = true;
      _selectedTids.clear();
      _selectedItems.clear();
      if (item != null) {
        _selectedTids.add(item.tid);
        _selectedItems[item.tid] = item;
      }
    });
  }

  void _toggleSelectItem(ForumThreadItem item) {
    setState(() {
      if (_selectedTids.contains(item.tid)) {
        _selectedTids.remove(item.tid);
        _selectedItems.remove(item.tid);
      } else {
        _selectedTids.add(item.tid);
        _selectedItems[item.tid] = item;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedTids.length == _threadList.length && _threadList.isNotEmpty) {
        _selectedTids.clear();
        _selectedItems.clear();
      } else {
        for (final item in _threadList) {
          _selectedTids.add(item.tid);
          _selectedItems[item.tid] = item;
        }
      }
    });
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '当前排版模板：',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx, false);
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (c) => TemplateManageScreen(
                              initialSelectedTemplate: _selectedTemplate,
                              onTemplateSelected: (t) {
                                setState(() {
                                  _selectedTemplate = t;
                                });
                              },
                            ),
                          ),
                        );
                        final active = await TemplateManager.getActiveTemplate();
                        setState(() {
                          _selectedTemplate = active;
                        });
                      },
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('管理/AI创建'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.style, size: 18, color: Color(0xFF192D50)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedTemplate.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      Text(
                        _selectedTemplate.isBuiltin ? '内置预设' : '自定义模板',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
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
                  {'width': 600, 'label': '600 px', 'desc': '手机卡片排版 (支持任意模板自适应)'},
                  {'width': 800, 'label': '800 px', 'desc': '标准宽屏，适合左右分栏与大图'},
                  {'width': 1280, 'label': '1280 px', 'desc': '超宽全景排版'},
                  {'width': 1440, 'label': '1440 px', 'desc': '高清 2K 宽屏'},
                  {'width': 1920, 'label': '1920 px', 'desc': '超清 4K 宽屏'},
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
    D2PdfConverter.stopKeepAlive();
    setState(() {
      _isConverting = false;
      _isBatchConverting = false;
      _isCancelRequested = false;
      _conversionStatus = '已取消生成';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消本次生成任务')),
      );
    }
  }

  // Convert a single thread to PDF in Download/D2PDF
  Future<File?> _convertSingleThreadToPdf(
    ForumThreadItem item, {
    bool isBatch = false,
    int batchIndex = 0,
    int batchTotal = 0,
  }) async {
    if (!isBatch) {
      if (_isConverting) return null;
      setState(() {
        _isConverting = true;
        _isCancelRequested = false;
        _convertingThreadTitle = item.title;
        _conversionProgress = 0.05;
        _conversionStatus = '正在分析帖子总页数...';
      });
      await D2PdfConverter.startKeepAlive(
        title: 'HiPDA D2PDF 正在生成',
        content: item.title,
      );
    } else {
      setState(() {
        _convertingThreadTitle = item.title;
        _conversionProgress = (batchIndex - 1) / batchTotal;
        _conversionStatus = '批量进度 ($batchIndex/$batchTotal): 正在分析帖子总页数...';
      });
    }

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
        return null;
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
        return null;
      }

      setState(() {
        _convertingThreadTitle = actualTitle;
        _conversionStatus = isBatch
            ? '批量进度 ($batchIndex/$batchTotal): 共 $totalPages 页，开始渲染...'
            : '检测到共 $totalPages 页，开始渲染并导出...';
        _conversionProgress = isBatch
            ? ((batchIndex - 1 + 0.05) / batchTotal)
            : 0.1;
      });

      final tempDir = await getTemporaryDirectory();
      final List<File> pagePdfs = [];

      for (int page = 1; page <= totalPages; page++) {
        if (_isCancelRequested) {
          _finishCancellation(pagePdfs);
          return null;
        }

        final double singlePageFraction = (page - 1) / totalPages;
        if (!isBatch) {
          await D2PdfConverter.updateKeepAlive(
            title: 'HiPDA D2PDF 正在生成 ($page/$totalPages)',
            content: actualTitle,
            progress: page,
            max: totalPages,
          );
        }
        setState(() {
          _conversionStatus = isBatch
              ? '批量进度 ($batchIndex/$batchTotal): 正在拉取第 $page / $totalPages 页数据...'
              : '正在拉取第 $page / $totalPages 页数据 (若内容/图片较多请耐心等待)...';
          _conversionProgress = isBatch
              ? ((batchIndex - 1 + singlePageFraction) / batchTotal)
              : (0.1 + (0.75 * singlePageFraction));
        });

        if (page > 1) {
          final pageUrl = D2PdfConverter.buildPageUrl(item.url, page);
          await _loadUrlInController(controller, pageUrl);
        }

        if (_isCancelRequested) {
          _finishCancellation(pagePdfs);
          return null;
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
          return null;
        }

        setState(() {
          _conversionStatus = '正在排版第 $page / $totalPages 页 (${_pdfWidth}px 宽屏, 左对齐)...';
        });

        final auxSizes = _MainScreenState.getAuxiliaryFontSizes(_fontSize);
        final int usernameSize = auxSizes['username']!;
        final int metaSize = auxSizes['meta']!;
        final int floorSize = auxSizes['floor']!;

        final injectionScript = TemplateRenderer.generateInjectionJs(
          template: _selectedTemplate,
          width: _pdfWidth,
          fontSize: _fontSize,
          usernameSize: usernameSize,
          metaSize: metaSize,
          floorSize: floorSize,
          pageTitle: actualTitle,
          isPreview: false,
        );

        // Inject dynamic template styles & DOM reconstruction
        await controller.evaluateJavascript(source: injectionScript);

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
          return null;
        }
      }

      if (_isCancelRequested) {
        _finishCancellation(pagePdfs);
        return null;
      }

      setState(() {
        _conversionStatus = isBatch
            ? '批量进度 ($batchIndex/$batchTotal): 正在合并保存到 Download/D2PDF...'
            : '正在合并保存到手机 Download/D2PDF 目录...';
        _conversionProgress = isBatch
            ? ((batchIndex - 1 + 0.95) / batchTotal)
            : 0.92;
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

      if (!isBatch) {
        await D2PdfConverter.stopKeepAlive();
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
      }

      return finalPdfFile;
    } catch (e) {
      if (_isCancelRequested) {
        _finishCancellation([]);
        return null;
      }
      if (!isBatch) {
        await D2PdfConverter.stopKeepAlive();
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
      return null;
    }
  }

  void _startGeneratePdf(ForumThreadItem item) {
    _convertSingleThreadToPdf(item, isBatch: false);
  }

  void _confirmStartBatchGenerate() {
    if (_selectedItems.isEmpty) return;
    final total = _selectedItems.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开始批量生成 PDF'),
        content: Text(
          '已选定 $total 个帖子进行批量生成。\n\n批量生成时应用已启动前台保活服务与唤醒锁，支持息屏与后台平稳运行。\n\n是否立即开始？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _executeBatchGeneration();
            },
            icon: const Icon(Icons.playlist_play),
            label: Text('开始生成 ($total 篇)'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeBatchGeneration() async {
    if (_isConverting || _isBatchConverting) return;
    if (_selectedItems.isEmpty) return;

    final itemsToProcess = List<ForumThreadItem>.from(_selectedItems.values);
    final totalCount = itemsToProcess.length;

    setState(() {
      _isConverting = true;
      _isBatchConverting = true;
      _isCancelRequested = false;
      _batchTotalCount = totalCount;
      _batchCurrentIndex = 0;
      _batchSuccessTitles.clear();
      _batchFailedTitles.clear();
      _conversionProgress = 0.0;
      _conversionStatus = '正在初始化批量生成任务 (共 $totalCount 篇)...';
    });

    await D2PdfConverter.startKeepAlive(
      title: 'HiPDA D2PDF 批量生成中',
      content: '准备生成 (0/$totalCount)',
    );

    for (int i = 0; i < totalCount; i++) {
      if (_isCancelRequested) {
        break;
      }

      final item = itemsToProcess[i];
      final currentNum = i + 1;

      setState(() {
        _batchCurrentIndex = currentNum;
        _convertingThreadTitle = '[$currentNum/$totalCount] ${item.title}';
      });

      await D2PdfConverter.updateKeepAlive(
        title: 'HiPDA 批量生成 ($currentNum/$totalCount)',
        content: item.title,
        progress: currentNum,
        max: totalCount,
      );

      final result = await _convertSingleThreadToPdf(
        item,
        isBatch: true,
        batchIndex: currentNum,
        batchTotal: totalCount,
      );

      if (_isCancelRequested) {
        break;
      }

      if (result != null) {
        _batchSuccessTitles.add(item.title);
      } else {
        _batchFailedTitles.add(item.title);
      }
    }

    await D2PdfConverter.stopKeepAlive();

    final isCancelled = _isCancelRequested;
    final successCount = _batchSuccessTitles.length;
    final failCount = _batchFailedTitles.length;

    setState(() {
      _isConverting = false;
      _isBatchConverting = false;
      _isCancelRequested = false;
      _conversionProgress = 1.0;
      _conversionStatus = isCancelled
          ? '批量生成已取消 (成功: $successCount, 失败/未完成: ${totalCount - successCount})'
          : '批量生成完毕！成功 $successCount 篇，失败 $failCount 篇';
    });

    _exitMultiSelectMode();

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isCancelled ? '批量生成已中止' : '批量生成已完成'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '任务概览：\n总共选定: $totalCount 篇\n成功生成: $successCount 篇\n失败/跳过: $failCount 篇\n\nPDF 文件均已保存至手机 Download/D2PDF 目录。',
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                if (_batchFailedTitles.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('失败列表：', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ..._batchFailedTitles.map((t) => Text('• $t', style: const TextStyle(fontSize: 12, color: Colors.red))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
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
          initialTemplate: _selectedTemplate,
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
          onTemplateChanged: (newTemplate) async {
            setState(() {
              _selectedTemplate = newTemplate;
            });
            await TemplateManager.setSelectedTemplateId(newTemplate.id);
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
      appBar: _isMultiSelectMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: '退出多选',
                onPressed: _exitMultiSelectMode,
              ),
              title: Text(
                '已选择 ${_selectedTids.length} 篇',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              backgroundColor: const Color(0xFF192D50),
              foregroundColor: Colors.white,
              actions: [
                TextButton.icon(
                  onPressed: _toggleSelectAll,
                  icon: Icon(
                    (_threadList.isNotEmpty && _selectedTids.length == _threadList.length)
                        ? Icons.deselect
                        : Icons.select_all,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    (_threadList.isNotEmpty && _selectedTids.length == _threadList.length)
                        ? '取消全选'
                        : '全选',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _selectedTids.isEmpty || _isConverting
                      ? null
                      : _confirmStartBatchGenerate,
                  icon: const Icon(Icons.download_for_offline, size: 16),
                  label: Text('批量生成(${_selectedTids.length})'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              title: const Text(
                'Hi! PDA',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              backgroundColor: const Color(0xFF192D50),
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.checklist_rtl),
                  tooltip: '批量选择',
                  onPressed: _threadList.isEmpty ? null : () => _enterMultiSelectMode(),
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
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    allowsInlineMediaPlayback: true,
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
                              _isBatchConverting
                                  ? '批量任务 [$_batchCurrentIndex/$_batchTotalCount]: $_convertingThreadTitle'
                                  : '正在生成: $_convertingThreadTitle',
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
                      // Section pills: Discovery | 我的收藏 | 我的帖子
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: Colors.white,
                        child: Row(
                          children: [
                            _buildSectionTab('discovery', 'Discovery', Icons.explore_outlined),
                            const SizedBox(width: 8),
                            _buildSectionTab('favorites', '我的收藏', Icons.bookmark_outline),
                            const SizedBox(width: 8),
                            _buildSectionTab('my_threads', '我的帖子', Icons.article_outlined),
                          ],
                        ),
                      ),
                      const Divider(height: 1, thickness: 1),

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
                                  '$_currentViewModeLabel (第 $_currentForumPage 页)',
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
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 12),
                                    Text('正在加载 $_currentViewModeLabel 帖子...', style: const TextStyle(color: Colors.grey)),
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
                                      final isSelected = _selectedTids.contains(item.tid);
                                      return ListTile(
                                        selected: _isMultiSelectMode && isSelected,
                                        selectedTileColor: Colors.amber.shade50.withOpacity(0.6),
                                        leading: _isMultiSelectMode
                                            ? Checkbox(
                                                value: isSelected,
                                                onChanged: (_) => _toggleSelectItem(item),
                                              )
                                            : null,
                                        onTap: () {
                                          if (_isMultiSelectMode) {
                                            _toggleSelectItem(item);
                                          } else {
                                            _openThreadPreview(item);
                                          }
                                        },
                                        onLongPress: () {
                                          if (_isMultiSelectMode) {
                                            _toggleSelectItem(item);
                                          } else {
                                            _enterMultiSelectMode(item);
                                          }
                                        },
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
                                        trailing: _isMultiSelectMode
                                            ? null
                                            : ElevatedButton.icon(
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
      bottomNavigationBar: (_isMultiSelectMode && _selectedTids.isNotEmpty)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      offset: const Offset(0, -2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已选中 ${_selectedTids.length} 篇帖子',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _isConverting ? null : _confirmStartBatchGenerate,
                      icon: const Icon(Icons.download_for_offline),
                      label: Text('开始批量生成 (${_selectedTids.length})'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF192D50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildSectionTab(String mode, String label, IconData icon) {
    final isSelected = _currentViewMode == mode;
    return Expanded(
      child: Material(
        color: isSelected ? const Color(0xFF192D50) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: (_isLoadingThreads || _isConverting) ? null : () => _switchViewMode(mode),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
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
  final LayoutTemplate initialTemplate;
  final ValueChanged<int> onFontSizeChanged;
  final ValueChanged<int>? onWidthChanged;
  final ValueChanged<LayoutTemplate>? onTemplateChanged;
  final void Function(ForumThreadItem item) onGeneratePdf;

  const ThreadPreviewScreen({
    super.key,
    required this.item,
    required this.renderWidth,
    required this.initialFontSize,
    required this.initialTemplate,
    required this.onFontSizeChanged,
    this.onWidthChanged,
    this.onTemplateChanged,
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
  late LayoutTemplate _previewTemplate;

  @override
  void initState() {
    super.initState();
    _previewFontSize = widget.initialFontSize;
    _previewWidth = widget.renderWidth;
    _previewTemplate = widget.initialTemplate;
  }

  Future<void> _injectStyles(InAppWebViewController controller) async {
    final int width = _previewWidth;
    final int fontSize = _previewFontSize;
    final auxSizes = _MainScreenState.getAuxiliaryFontSizes(fontSize);
    final int usernameSize = auxSizes['username']!;
    final int metaSize = auxSizes['meta']!;
    final int floorSize = auxSizes['floor']!;

    final injectionScript = TemplateRenderer.generateInjectionJs(
      template: _previewTemplate,
      width: width,
      fontSize: fontSize,
      usernameSize: usernameSize,
      metaSize: metaSize,
      floorSize: floorSize,
      pageTitle: widget.item.title,
      isPreview: true,
    );

    await controller.evaluateJavascript(source: injectionScript);
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
              // Template selection switcher & manager
              PopupMenuButton<String>(
                tooltip: '切换/管理排版模板',
                onSelected: (val) async {
                  if (val == '__manage__') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => TemplateManageScreen(
                          initialSelectedTemplate: _previewTemplate,
                          onTemplateSelected: (t) {
                            setState(() => _previewTemplate = t);
                            widget.onTemplateChanged?.call(t);
                            if (_webViewController != null) {
                              _injectStyles(_webViewController!);
                            }
                          },
                        ),
                      ),
                    );
                    final active = await TemplateManager.getActiveTemplate();
                    setState(() => _previewTemplate = active);
                    widget.onTemplateChanged?.call(active);
                    if (_webViewController != null) {
                      _injectStyles(_webViewController!);
                    }
                  } else {
                    final all = await TemplateManager.getAllTemplates();
                    final found = all.firstWhere((t) => t.id == val, orElse: () => _previewTemplate);
                    setState(() => _previewTemplate = found);
                    widget.onTemplateChanged?.call(found);
                    if (_webViewController != null) {
                      _injectStyles(_webViewController!);
                    }
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: TemplateManager.defaultCard.id,
                    child: Row(
                      children: [
                        Icon(
                          _previewTemplate.id == TemplateManager.defaultCard.id ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 16,
                          color: const Color(0xFF192D50),
                        ),
                        const SizedBox(width: 8),
                        const Text('经典移动卡片', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: TemplateManager.fullForum.id,
                    child: Row(
                      children: [
                        Icon(
                          _previewTemplate.id == TemplateManager.fullForum.id ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 16,
                          color: const Color(0xFF192D50),
                        ),
                        const SizedBox(width: 8),
                        const Text('经典左右分栏', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: TemplateManager.minimalReader.id,
                    child: Row(
                      children: [
                        Icon(
                          _previewTemplate.id == TemplateManager.minimalReader.id ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 16,
                          color: const Color(0xFF192D50),
                        ),
                        const SizedBox(width: 8),
                        const Text('极简纯享阅读', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: '__manage__',
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 16, color: Color(0xFF192D50)),
                        SizedBox(width: 8),
                        Text('模板库与 AI 创编...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
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
                      const Icon(Icons.style, size: 14, color: Color(0xFF192D50)),
                      const SizedBox(width: 4),
                      Text(
                        _previewTemplate.name,
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
              const SizedBox(width: 6),
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
