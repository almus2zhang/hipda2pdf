import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 动态排版模板数据模型
class LayoutTemplate {
  String id;
  String name;
  String description;
  int defaultWidth;
  bool isBuiltin;

  // 用户信息三要素配置：
  // 1. 头像
  bool showAvatar;
  int avatarSize; // px, 默认 42
  bool avatarRound; // true 为圆形，false 为微圆角方形
  String avatarBorderColor; // 如 "#e5e7eb"

  // 2. 名字 (用户名)
  bool showUsername;
  int usernameFontSize; // 0 表示跟随全局比例计算
  String usernameColor; // 如 "#111827"
  bool usernameBold;

  // 3. 剩余其他信息 (等级、太阳月亮星星、UID、帖子数、积分、注册日期等)
  bool showOtherInfo;
  int otherInfoFontSize; // 0 表示跟随全局比例计算
  String otherInfoColor; // 如 "#6b7280"

  // 楼层元信息配置：
  bool showFloorBadge; // 楼层号 (楼主/沙发/2楼)
  String floorColor; // 如 "#0369a1"
  bool showPostTime; // 发帖时间
  String postTimeColor; // 如 "#6b7280"

  // 正文与签名配置：
  String postTextColor; // 如 "#1f2937"
  double postLineHeight; // 如 1.65
  bool showSignature; // 是否显示签名档

  // 整体卡片排版模式：
  // 'card': 现代移动卡片流式（每楼独立气泡卡片，支持交替双色、边框与底色，各宽度自动填满）
  // 'split': 经典论坛左右分栏（左侧作者栏，右侧正文栏）
  // 'minimal': 极简阅读（去掉多余修饰，纯净阅读，全宽填满）
  // 'raw': 原汁原味（原汁原味保留论坛经典桌面排版，仅调整宽度与字号，净化功能按钮）
  String layoutMode; 
  int splitAuthorWidth; // 经典左右分栏模式下左侧作者栏宽度 (如 140px)

  // 气泡卡片外框/分割线/背景样式
  String cardBorderColor; // 如 "#e2e8f0"
  int cardBorderWidth; // 气泡边框粗细，如 1px (0 为无边框)
  int cardBorderRadius; // 气泡圆角大小，如 10px (0 为直角)
  int cardSpacing; // 气泡之间的纵向间距，如 10px
  bool showFloorDivider; // 楼层内作者与正文间微弱分割线
  String cardBackgroundColor; // 气泡主颜色，如 "#ffffff"
  bool enableAlternateBubbleColor; // 是否启用气泡交替双色
  String alternateBubbleColor; // 气泡交替第二色，如 "#f8fafc" 或 "#f0f7ff"
  String pageBackgroundColor; // 页面背景底色，如 "#f1f5f9" 或 "#ffffff"

  // 针对不同宽度的布局微调配置 (如 600, 800, 1000 等各宽度的头像大小、圆角等)
  Map<String, dynamic> widthConfigs;

  // 额外自定义 CSS (AI分析生成或高级微调时使用)
  String customCss;

  LayoutTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.defaultWidth = 600,
    this.isBuiltin = false,
    this.showAvatar = true,
    this.avatarSize = 30,
    this.avatarRound = true,
    this.avatarBorderColor = '#e5e7eb',
    this.showUsername = true,
    this.usernameFontSize = 0,
    this.usernameColor = '#111827',
    this.usernameBold = true,
    this.showOtherInfo = true,
    this.otherInfoFontSize = 0,
    this.otherInfoColor = '#6b7280',
    this.showFloorBadge = true,
    this.floorColor = '#0369a1',
    this.showPostTime = true,
    this.postTimeColor = '#6b7280',
    this.postTextColor = '#1f2937',
    this.postLineHeight = 1.65,
    this.showSignature = false,
    this.layoutMode = 'card',
    this.splitAuthorWidth = 160,
    this.cardBorderColor = '#e2e8f0',
    this.cardBorderWidth = 1,
    this.cardBorderRadius = 10,
    this.cardSpacing = 10,
    this.showFloorDivider = false,
    this.cardBackgroundColor = '#ffffff',
    this.enableAlternateBubbleColor = false,
    this.alternateBubbleColor = '#f8fafc',
    this.pageBackgroundColor = '#f1f5f9',
    Map<String, dynamic>? widthConfigs,
    this.customCss = '',
  }) : widthConfigs = widthConfigs ?? {};

  /// 获取简洁的两字名称：气泡，经典，极简，还原；新增自定义模板取前两个字
  String get shortName {
    if (id == 'builtin_card' || layoutMode == 'card' || name.contains('气泡') || name.contains('卡片')) {
      return '气泡';
    }
    if (id == 'builtin_full_forum' || layoutMode == 'split' || name.contains('经典') || name.contains('左右')) {
      return '经典';
    }
    if (id == 'builtin_minimal' || layoutMode == 'minimal' || name.contains('极简')) {
      return '极简';
    }
    if (id == 'builtin_raw' || layoutMode == 'raw' || name.contains('原汁') || name.contains('还原')) {
      return '还原';
    }
    final trimmed = name.trim();
    if (trimmed.length <= 2) return trimmed;
    return trimmed.substring(0, 2);
  }

  /// 获取指定宽度下的头像大小 (若该宽度有微调则使用微调值，否则返回全局设置)
  int getAvatarSizeForWidth(int width) {
    final cfg = widthConfigs[width.toString()];
    if (cfg is Map && cfg['avatarSize'] != null) {
      return (cfg['avatarSize'] as num).toInt();
    }
    if (width <= 600 && avatarSize > 32) return 30;
    return avatarSize;
  }

  /// 获取指定宽度下的卡片圆角大小 (0 为直角)
  int getBorderRadiusForWidth(int width) {
    final cfg = widthConfigs[width.toString()];
    if (cfg is Map && cfg['borderRadius'] != null) {
      return (cfg['borderRadius'] as num).toInt();
    }
    return cardBorderRadius;
  }

  /// 获取指定宽度下的气泡卡片纵向间距
  int getCardSpacingForWidth(int width) {
    final cfg = widthConfigs[width.toString()];
    if (cfg is Map && cfg['cardSpacing'] != null) {
      return (cfg['cardSpacing'] as num).toInt();
    }
    return cardSpacing;
  }

  /// 获取指定宽度下的经典左右分栏作者栏宽度
  int getAuthorWidthForWidth(int width) {
    final cfg = widthConfigs[width.toString()];
    if (cfg is Map && cfg['authorWidth'] != null) {
      return (cfg['authorWidth'] as num).toInt();
    }
    if (width <= 600 && splitAuthorWidth > 140) {
      return 140;
    }
    return splitAuthorWidth;
  }

  /// 检查某宽度下某元素是否显示 (优先使用该宽度独立定制配置，否则回退到模板基准设置)
  bool isElementVisibleForWidth(int width, String key, bool defaultValue) {
    final cfg = widthConfigs[width.toString()];
    if (cfg is Map && cfg.containsKey(key)) {
      return cfg[key] == true;
    }
    return defaultValue;
  }

  bool getShowAvatarForWidth(int width) => isElementVisibleForWidth(width, 'showAvatar', showAvatar);
  bool getShowUsernameForWidth(int width) => isElementVisibleForWidth(width, 'showUsername', showUsername);
  bool getShowOtherInfoForWidth(int width) => isElementVisibleForWidth(width, 'showOtherInfo', showOtherInfo);
  bool getShowFloorBadgeForWidth(int width) => isElementVisibleForWidth(width, 'showFloorBadge', showFloorBadge);
  bool getShowPostTimeForWidth(int width) => isElementVisibleForWidth(width, 'showPostTime', showPostTime);
  bool getShowSignatureForWidth(int width) => isElementVisibleForWidth(width, 'showSignature', showSignature);
  bool getShowFloorDividerForWidth(int width) => isElementVisibleForWidth(width, 'showFloorDivider', showFloorDivider);

  /// 设置或清除某宽度下某元素的定制显示状态 (value 为 null 表示重置跟随模板通用值)
  void setElementVisibleForWidth(int width, String key, bool? value) {
    widthConfigs = Map<String, dynamic>.from(widthConfigs);
    final keyStr = width.toString();
    final cur = Map<String, dynamic>.from(widthConfigs[keyStr] as Map? ?? {});
    if (value == null) {
      cur.remove(key);
    } else {
      cur[key] = value;
    }
    widthConfigs[keyStr] = cur;
  }

  /// 为特定宽度微调属性
  void setWidthConfig(int width, String key, dynamic value) {
    widthConfigs = Map<String, dynamic>.from(widthConfigs);
    final keyStr = width.toString();
    final cur = Map<String, dynamic>.from(widthConfigs[keyStr] as Map? ?? {});
    if (value == null) {
      cur.remove(key);
    } else {
      cur[key] = value;
    }
    widthConfigs[keyStr] = cur;
  }

  /// 获取特定宽度的微调属性
  dynamic getWidthConfig(int width, String key) {
    final cfg = widthConfigs[width.toString()];
    if (cfg is Map) {
      return cfg[key];
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'defaultWidth': defaultWidth,
    'isBuiltin': isBuiltin,
    'showAvatar': showAvatar,
    'avatarSize': avatarSize,
    'avatarRound': avatarRound,
    'avatarBorderColor': avatarBorderColor,
    'showUsername': showUsername,
    'usernameFontSize': usernameFontSize,
    'usernameColor': usernameColor,
    'usernameBold': usernameBold,
    'showOtherInfo': showOtherInfo,
    'otherInfoFontSize': otherInfoFontSize,
    'otherInfoColor': otherInfoColor,
    'showFloorBadge': showFloorBadge,
    'floorColor': floorColor,
    'showPostTime': showPostTime,
    'postTimeColor': postTimeColor,
    'postTextColor': postTextColor,
    'postLineHeight': postLineHeight,
    'showSignature': showSignature,
    'layoutMode': layoutMode,
    'splitAuthorWidth': splitAuthorWidth,
    'cardBorderColor': cardBorderColor,
    'cardBorderWidth': cardBorderWidth,
    'cardBorderRadius': cardBorderRadius,
    'cardSpacing': cardSpacing,
    'showFloorDivider': showFloorDivider,
    'cardBackgroundColor': cardBackgroundColor,
    'enableAlternateBubbleColor': enableAlternateBubbleColor,
    'alternateBubbleColor': alternateBubbleColor,
    'pageBackgroundColor': pageBackgroundColor,
    'widthConfigs': widthConfigs,
    'customCss': customCss,
  };

  factory LayoutTemplate.fromJson(Map<String, dynamic> json) {
    final mode = json['layoutMode'] ?? 'card';
    return LayoutTemplate(
      id: json['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] ?? '自定义模板',
      description: json['description'] ?? '',
      defaultWidth: json['defaultWidth'] ?? 600,
      isBuiltin: json['isBuiltin'] ?? false,
      showAvatar: json['showAvatar'] ?? true,
      avatarSize: json['avatarSize'] ?? 30,
      avatarRound: json['avatarRound'] ?? true,
      avatarBorderColor: json['avatarBorderColor'] ?? '#e5e7eb',
      showUsername: json['showUsername'] ?? true,
      usernameFontSize: json['usernameFontSize'] ?? 0,
      usernameColor: json['usernameColor'] ?? '#111827',
      usernameBold: json['usernameBold'] ?? true,
      showOtherInfo: json['showOtherInfo'] ?? true,
      otherInfoFontSize: json['otherInfoFontSize'] ?? 0,
      otherInfoColor: json['otherInfoColor'] ?? '#6b7280',
      showFloorBadge: json['showFloorBadge'] ?? true,
      floorColor: json['floorColor'] ?? '#0369a1',
      showPostTime: json['showPostTime'] ?? true,
      postTimeColor: json['postTimeColor'] ?? '#6b7280',
      postTextColor: json['postTextColor'] ?? '#1f2937',
      postLineHeight: (json['postLineHeight'] as num?)?.toDouble() ?? 1.65,
      showSignature: json['showSignature'] ?? false,
      layoutMode: mode,
      splitAuthorWidth: json['splitAuthorWidth'] ?? 160,
      cardBorderColor: json['cardBorderColor'] ?? '#e2e8f0',
      cardBorderWidth: json['cardBorderWidth'] ?? 1,
      cardBorderRadius: json['cardBorderRadius'] ?? 10,
      cardSpacing: json['cardSpacing'] ?? 10,
      showFloorDivider: json['showFloorDivider'] ?? false,
      cardBackgroundColor: json['cardBackgroundColor'] ?? '#ffffff',
      enableAlternateBubbleColor: json['enableAlternateBubbleColor'] ?? false,
      alternateBubbleColor: json['alternateBubbleColor'] ?? '#f8fafc',
      pageBackgroundColor: json['pageBackgroundColor'] ?? (mode == 'card' ? '#f1f5f9' : '#ffffff'),
      widthConfigs: (json['widthConfigs'] is Map)
          ? Map<String, dynamic>.from(json['widthConfigs'])
          : {},
      customCss: json['customCss'] ?? '',
    );
  }

  LayoutTemplate copyWith({
    String? id,
    String? name,
    String? description,
    int? defaultWidth,
    bool? isBuiltin,
    bool? showAvatar,
    int? avatarSize,
    bool? avatarRound,
    String? avatarBorderColor,
    bool? showUsername,
    int? usernameFontSize,
    String? usernameColor,
    bool? usernameBold,
    bool? showOtherInfo,
    int? otherInfoFontSize,
    String? otherInfoColor,
    bool? showFloorBadge,
    String? floorColor,
    bool? showPostTime,
    String? postTimeColor,
    String? postTextColor,
    double? postLineHeight,
    bool? showSignature,
    String? layoutMode,
    int? splitAuthorWidth,
    String? cardBorderColor,
    int? cardBorderWidth,
    int? cardBorderRadius,
    int? cardSpacing,
    bool? showFloorDivider,
    String? cardBackgroundColor,
    bool? enableAlternateBubbleColor,
    String? alternateBubbleColor,
    String? pageBackgroundColor,
    Map<String, dynamic>? widthConfigs,
    String? customCss,
  }) {
    return LayoutTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      defaultWidth: defaultWidth ?? this.defaultWidth,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      showAvatar: showAvatar ?? this.showAvatar,
      avatarSize: avatarSize ?? this.avatarSize,
      avatarRound: avatarRound ?? this.avatarRound,
      avatarBorderColor: avatarBorderColor ?? this.avatarBorderColor,
      showUsername: showUsername ?? this.showUsername,
      usernameFontSize: usernameFontSize ?? this.usernameFontSize,
      usernameColor: usernameColor ?? this.usernameColor,
      usernameBold: usernameBold ?? this.usernameBold,
      showOtherInfo: showOtherInfo ?? this.showOtherInfo,
      otherInfoFontSize: otherInfoFontSize ?? this.otherInfoFontSize,
      otherInfoColor: otherInfoColor ?? this.otherInfoColor,
      showFloorBadge: showFloorBadge ?? this.showFloorBadge,
      floorColor: floorColor ?? this.floorColor,
      showPostTime: showPostTime ?? this.showPostTime,
      postTimeColor: postTimeColor ?? this.postTimeColor,
      postTextColor: postTextColor ?? this.postTextColor,
      postLineHeight: postLineHeight ?? this.postLineHeight,
      showSignature: showSignature ?? this.showSignature,
      layoutMode: layoutMode ?? this.layoutMode,
      splitAuthorWidth: splitAuthorWidth ?? this.splitAuthorWidth,
      cardBorderColor: cardBorderColor ?? this.cardBorderColor,
      cardBorderWidth: cardBorderWidth ?? this.cardBorderWidth,
      cardBorderRadius: cardBorderRadius ?? this.cardBorderRadius,
      cardSpacing: cardSpacing ?? this.cardSpacing,
      showFloorDivider: showFloorDivider ?? this.showFloorDivider,
      cardBackgroundColor: cardBackgroundColor ?? this.cardBackgroundColor,
      enableAlternateBubbleColor: enableAlternateBubbleColor ?? this.enableAlternateBubbleColor,
      alternateBubbleColor: alternateBubbleColor ?? this.alternateBubbleColor,
      pageBackgroundColor: pageBackgroundColor ?? this.pageBackgroundColor,
      widthConfigs: widthConfigs ?? this.widthConfigs,
      customCss: customCss ?? this.customCss,
    );
  }
}

/// 预设模板与持久化管理器
class TemplateManager {
  static const String _kStorageKey = 'd2pdf_custom_templates_v1';
  static const String _kSelectedTemplateKey = 'd2pdf_selected_template_id';

  // 1. 经典移动卡片 (每层楼独立气泡卡片，支持气泡单双交替色、边框与底色，各宽度自动填满)
  static final LayoutTemplate defaultCard = LayoutTemplate(
    id: 'builtin_card',
    name: '经典气泡卡片',
    description: '每楼独立气泡卡片，支持气泡双色交替、边框与底色，各宽度自动填满。',
    defaultWidth: 600,
    isBuiltin: true,
    showAvatar: true,
    avatarSize: 30,
    avatarRound: true,
    avatarBorderColor: '#e2e8f0',
    showUsername: true,
    usernameColor: '#111827',
    usernameBold: true,
    showOtherInfo: false,
    otherInfoColor: '#6b7280',
    showFloorBadge: true,
    floorColor: '#0369a1',
    showPostTime: true,
    postTimeColor: '#6b7280',
    postTextColor: '#1f2937',
    postLineHeight: 1.65,
    showSignature: false,
    layoutMode: 'card',
    cardBorderColor: '#e2e8f0',
    cardBorderWidth: 1,
    cardBorderRadius: 10,
    showFloorDivider: false,
    cardBackgroundColor: '#ffffff',
    enableAlternateBubbleColor: true,
    alternateBubbleColor: '#f8fafc',
    pageBackgroundColor: '#f1f5f9',
    widthConfigs: {
      '600': {'avatarSize': 30, 'borderRadius': 10},
      '800': {'avatarSize': 36, 'borderRadius': 12},
      '1000': {'avatarSize': 38, 'borderRadius': 12},
      '1280': {'avatarSize': 42, 'borderRadius': 14},
    },
  );

  // 2. 论坛全要素左右分栏版
  static final LayoutTemplate fullForum = LayoutTemplate(
    id: 'builtin_full_forum',
    name: '经典论坛左右分栏',
    description: '左侧完整展示作者头像、名字、等级星级、积分注册信息，右侧正文与签名。',
    defaultWidth: 800,
    isBuiltin: true,
    showAvatar: true,
    avatarSize: 48,
    avatarRound: false,
    avatarBorderColor: '#cbd5e1',
    showUsername: true,
    usernameColor: '#0f172a',
    usernameBold: true,
    showOtherInfo: true,
    otherInfoColor: '#64748b',
    showFloorBadge: true,
    floorColor: '#0284c7',
    showPostTime: true,
    postTimeColor: '#64748b',
    postTextColor: '#0f172a',
    postLineHeight: 1.7,
    showSignature: true,
    layoutMode: 'split',
    splitAuthorWidth: 160,
    cardBorderColor: '#e2e8f0',
    cardBorderWidth: 1,
    cardBorderRadius: 0,
    showFloorDivider: true,
    cardBackgroundColor: '#ffffff',
    enableAlternateBubbleColor: false,
    alternateBubbleColor: '#ffffff',
    pageBackgroundColor: '#ffffff',
    widthConfigs: {
      '600': {'authorWidth': 140, 'avatarSize': 40},
      '800': {'authorWidth': 160, 'avatarSize': 48},
      '1000': {'authorWidth': 170, 'avatarSize': 52},
      '1280': {'authorWidth': 180, 'avatarSize': 56},
    },
  );

  // 3. 极简纯粹阅读
  static final LayoutTemplate minimalReader = LayoutTemplate(
    id: 'builtin_minimal',
    name: '极简阅读纯享',
    description: '隐藏头像与繁杂信息，仅保留楼层与轻量用户名，专注文档与文章阅读，全宽填满。',
    defaultWidth: 600,
    isBuiltin: true,
    showAvatar: false,
    showUsername: true,
    usernameColor: '#374151',
    usernameBold: true,
    showOtherInfo: false,
    showFloorBadge: true,
    floorColor: '#4b5563',
    showPostTime: true,
    postTimeColor: '#9ca3af',
    postTextColor: '#111827',
    postLineHeight: 1.75,
    showSignature: false,
    layoutMode: 'minimal',
    cardBorderColor: '#e5e7eb',
    cardBorderWidth: 1,
    cardBorderRadius: 0,
    showFloorDivider: true,
    cardBackgroundColor: '#ffffff',
    enableAlternateBubbleColor: false,
    alternateBubbleColor: '#ffffff',
    pageBackgroundColor: '#ffffff',
  );

  // 4. 原汁原味 (原汁原味保留论坛经典排版，仅调整宽度与文字大小，去除功能按钮)
  static final LayoutTemplate rawOriginal = LayoutTemplate(
    id: 'builtin_raw',
    name: '原汁原味',
    description: '原汁原味保留论坛经典桌面排版，仅调整页面宽度与正文字号，净化冗余按钮。',
    defaultWidth: 800,
    isBuiltin: true,
    showAvatar: true,
    avatarSize: 0,
    avatarRound: false,
    avatarBorderColor: '#cbd5e1',
    showUsername: true,
    usernameColor: '#003B54',
    usernameBold: true,
    showOtherInfo: true,
    otherInfoColor: '#666666',
    showFloorBadge: true,
    floorColor: '#003B54',
    showPostTime: true,
    postTimeColor: '#666666',
    postTextColor: '#444444',
    postLineHeight: 1.6,
    showSignature: true,
    layoutMode: 'raw',
    cardBorderColor: '#efefef',
    cardBorderWidth: 1,
    cardBorderRadius: 0,
    showFloorDivider: true,
    cardBackgroundColor: '#ffffff',
    enableAlternateBubbleColor: false,
    alternateBubbleColor: '#ffffff',
    pageBackgroundColor: '#ffffff',
  );

  static List<LayoutTemplate> getBuiltinTemplates() {
    return [defaultCard, fullForum, minimalReader, rawOriginal];
  }

  /// 获取当前所有可用模板（内置 + 用户自定义）
  static Future<List<LayoutTemplate>> getAllTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final customRaw = prefs.getString(_kStorageKey);
    final List<LayoutTemplate> list = getBuiltinTemplates();

    if (customRaw != null && customRaw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(customRaw);
        for (final item in decoded) {
          list.add(LayoutTemplate.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (_) {}
    }
    return list;
  }

  /// 保存或更新自定义模板
  static Future<void> saveTemplate(LayoutTemplate template) async {
    final prefs = await SharedPreferences.getInstance();
    final customRaw = prefs.getString(_kStorageKey);
    List<Map<String, dynamic>> customList = [];
    if (customRaw != null && customRaw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(customRaw);
        customList = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    final existingIndex = customList.indexWhere((e) => e['id'] == template.id);
    if (existingIndex >= 0) {
      customList[existingIndex] = template.toJson();
    } else {
      customList.add(template.toJson());
    }

    await prefs.setString(_kStorageKey, jsonEncode(customList));
  }

  /// 删除自定义模板
  static Future<void> deleteTemplate(String templateId) async {
    final prefs = await SharedPreferences.getInstance();
    final customRaw = prefs.getString(_kStorageKey);
    if (customRaw == null) return;
    try {
      final List decoded = jsonDecode(customRaw);
      final filtered = decoded.where((e) => e['id'] != templateId).toList();
      await prefs.setString(_kStorageKey, jsonEncode(filtered));
    } catch (_) {}
  }

  /// 获取当前选中的模板 ID
  static Future<String> getSelectedTemplateId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSelectedTemplateKey) ?? defaultCard.id;
  }

  /// 设置当前选中的模板 ID
  static Future<void> setSelectedTemplateId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedTemplateKey, id);
  }

  /// 设置当前选中的模板 ID (alias)
  static Future<void> setActiveTemplate(String id) => setSelectedTemplateId(id);

  /// 获取当前生效的模板对象
  static Future<LayoutTemplate> getActiveTemplate() async {
    final activeId = await getSelectedTemplateId();
    final all = await getAllTemplates();
    return all.firstWhere((t) => t.id == activeId, orElse: () => defaultCard);
  }
}
