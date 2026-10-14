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
  // 'card': 现代移动卡片流式（原600px卡片风格，上下结构，支持各宽度自适应）
  // 'split': 经典论坛左右分栏（左侧作者栏，右侧正文栏）
  // 'minimal': 极简阅读（去掉多余修饰，纯净阅读）
  String layoutMode; 

  // 卡片外框/分割线样式
  String cardBorderColor; // 如 "#e5e7eb"
  bool showFloorDivider; // 楼层之间是否有分割线/卡片阴影
  String cardBackgroundColor; // 如 "#ffffff"

  // 额外自定义 CSS (AI分析生成或高级微调时使用)
  String customCss;

  LayoutTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.defaultWidth = 600,
    this.isBuiltin = false,
    this.showAvatar = true,
    this.avatarSize = 42,
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
    this.cardBorderColor = '#e5e7eb',
    this.showFloorDivider = true,
    this.cardBackgroundColor = '#ffffff',
    this.customCss = '',
  });

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
    'cardBorderColor': cardBorderColor,
    'showFloorDivider': showFloorDivider,
    'cardBackgroundColor': cardBackgroundColor,
    'customCss': customCss,
  };

  factory LayoutTemplate.fromJson(Map<String, dynamic> json) {
    return LayoutTemplate(
      id: json['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] ?? '自定义模板',
      description: json['description'] ?? '',
      defaultWidth: json['defaultWidth'] ?? 600,
      isBuiltin: json['isBuiltin'] ?? false,
      showAvatar: json['showAvatar'] ?? true,
      avatarSize: json['avatarSize'] ?? 42,
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
      layoutMode: json['layoutMode'] ?? 'card',
      cardBorderColor: json['cardBorderColor'] ?? '#e5e7eb',
      showFloorDivider: json['showFloorDivider'] ?? true,
      cardBackgroundColor: json['cardBackgroundColor'] ?? '#ffffff',
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
    String? cardBorderColor,
    bool? showFloorDivider,
    String? cardBackgroundColor,
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
      cardBorderColor: cardBorderColor ?? this.cardBorderColor,
      showFloorDivider: showFloorDivider ?? this.showFloorDivider,
      cardBackgroundColor: cardBackgroundColor ?? this.cardBackgroundColor,
      customCss: customCss ?? this.customCss,
    );
  }
}

/// 预设模板与持久化管理器
class TemplateManager {
  static const String _kStorageKey = 'd2pdf_custom_templates_v1';
  static const String _kSelectedTemplateKey = 'd2pdf_selected_template_id';

  // 1. 经典移动卡片 (原600px默认卡片，现在解耦支持全宽度)
  static final LayoutTemplate defaultCard = LayoutTemplate(
    id: 'builtin_card',
    name: '经典移动卡片',
    description: '42px圆形头像，顶部用户名与时间楼层紧凑排版，支持任意宽度自适应。',
    defaultWidth: 600,
    isBuiltin: true,
    showAvatar: true,
    avatarSize: 42,
    avatarRound: true,
    avatarBorderColor: '#e5e7eb',
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
    cardBorderColor: '#e5e7eb',
    showFloorDivider: true,
    cardBackgroundColor: '#ffffff',
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
    cardBorderColor: '#e2e8f0',
    showFloorDivider: true,
    cardBackgroundColor: '#ffffff',
  );

  // 3. 极简纯粹阅读
  static final LayoutTemplate minimalReader = LayoutTemplate(
    id: 'builtin_minimal',
    name: '极简阅读纯享',
    description: '隐藏头像与繁杂信息，仅保留楼层与轻量用户名，专注文档与文章阅读。',
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
    cardBorderColor: '#f3f4f6',
    showFloorDivider: true,
    cardBackgroundColor: '#ffffff',
  );

  static List<LayoutTemplate> getBuiltinTemplates() {
    return [defaultCard, fullForum, minimalReader];
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

  /// 获取当前生效的模板对象
  static Future<LayoutTemplate> getActiveTemplate() async {
    final activeId = await getSelectedTemplateId();
    final all = await getAllTemplates();
    return all.firstWhere((t) => t.id == activeId, orElse: () => defaultCard);
  }
}
