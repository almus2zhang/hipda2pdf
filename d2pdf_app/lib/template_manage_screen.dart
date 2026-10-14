import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'layout_template.dart';
import 'template_ai_service.dart';

/// 模板管理与 AI 创建/编辑中心
class TemplateManageScreen extends StatefulWidget {
  final LayoutTemplate? initialSelectedTemplate;
  final ValueChanged<LayoutTemplate>? onTemplateSelected;

  const TemplateManageScreen({
    super.key,
    this.initialSelectedTemplate,
    this.onTemplateSelected,
  });

  @override
  State<TemplateManageScreen> createState() => _TemplateManageScreenState();
}

class _TemplateManageScreenState extends State<TemplateManageScreen> {
  List<LayoutTemplate> _templates = [];
  String _selectedId = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    final all = await TemplateManager.getAllTemplates();
    final activeId = await TemplateManager.getSelectedTemplateId();
    setState(() {
      _templates = all;
      _selectedId = widget.initialSelectedTemplate?.id ?? activeId;
      _isLoading = false;
    });
  }

  Future<void> _selectTemplate(LayoutTemplate t) async {
    await TemplateManager.setSelectedTemplateId(t.id);
    setState(() {
      _selectedId = t.id;
    });
    widget.onTemplateSelected?.call(t);
  }

  Future<void> _deleteTemplate(LayoutTemplate t) async {
    if (t.isBuiltin) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确定要删除自定义模板「${t.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TemplateManager.deleteTemplate(t.id);
      if (_selectedId == t.id) {
        await _selectTemplate(TemplateManager.defaultCard);
      }
      await _loadTemplates();
    }
  }

  Future<void> _openAiCreateDialog() async {
    final result = await showModalBottomSheet<LayoutTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _AiCreateTemplateSheet(),
    );

    if (result != null) {
      await TemplateManager.saveTemplate(result);
      await _selectTemplate(result);
      await _loadTemplates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功生成并保存模板「${result.name}」！')),
        );
      }
    }
  }

  Future<void> _openEditTemplate(LayoutTemplate template) async {
    final edited = await Navigator.of(context).push<LayoutTemplate>(
      MaterialPageRoute(
        builder: (ctx) => TemplateEditorScreen(template: template),
      ),
    );

    if (edited != null) {
      await TemplateManager.saveTemplate(edited);
      await _loadTemplates();
      if (_selectedId == edited.id) {
        widget.onTemplateSelected?.call(edited);
      }
    }
  }

  Future<void> _openAiSettings() async {
    final baseUrlController = TextEditingController(text: await AiServiceConfig.getBaseUrl());
    final apiKeyController = TextEditingController(text: await AiServiceConfig.getApiKey());
    String selectedModel = await AiServiceConfig.getModel();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.psychology, color: Color(0xFF192D50)),
              SizedBox(width: 8),
              Text('AI 接口与模型配置', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '支持硅基流动 (SiliconFlow) 或任意 OpenAI 兼容的 API 接口：',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API 地址 (Base URL)',
                    hintText: 'https://api.siliconflow.cn/v1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key (密钥)',
                    hintText: 'sk-xxxxxxxx',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('选择模型：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: AiServiceConfig.presetModels.map((m) {
                    final isSel = m == selectedModel;
                    return ChoiceChip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      selected: isSel,
                      selectedColor: const Color(0xFF192D50),
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : Colors.black87,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (val) {
                        if (val) {
                          setDialogState(() => selectedModel = m);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '或自定义模型名称',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  controller: TextEditingController(text: selectedModel),
                  onChanged: (val) {
                    if (val.trim().isNotEmpty) {
                      selectedModel = val.trim();
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await AiServiceConfig.setBaseUrl(baseUrlController.text);
                await AiServiceConfig.setApiKey(apiKeyController.text);
                await AiServiceConfig.setModel(selectedModel);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF192D50)),
              child: const Text('保存配置'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('排版模板库', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF192D50),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'AI 接口与模型设置',
            onPressed: _openAiSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.blueGrey.shade50,
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Color(0xFF192D50)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '选择用于生成 PDF 的排版风格。支持通过 AI 识图/文字定制新模板，也可可视化微调。',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final t = _templates[i];
                      final isSelected = t.id == _selectedId;
                      return Card(
                        elevation: isSelected ? 3 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF192D50) : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _selectTemplate(t),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                      color: isSelected ? const Color(0xFF192D50) : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        t.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? const Color(0xFF192D50) : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: t.isBuiltin ? Colors.blue.shade50 : Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        t.isBuiltin ? '内置' : '自定义',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: t.isBuiltin ? Colors.blue.shade700 : Colors.purple.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  t.description.isNotEmpty ? t.description : '无描述',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                                const Divider(height: 16),
                                Row(
                                  children: [
                                    _buildBadge(t.showAvatar ? '含头像' : '隐藏头像'),
                                    const SizedBox(width: 6),
                                    _buildBadge(t.showOtherInfo ? '全用户信息' : '仅用户名'),
                                    const SizedBox(width: 6),
                                    _buildBadge(t.layoutMode == 'card' ? '卡片流' : (t.layoutMode == 'split' ? '左右分栏' : '极简阅读')),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      tooltip: '可视化微调所见即所得',
                                      onPressed: () => _openEditTemplate(t),
                                    ),
                                    if (!t.isBuiltin)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                        tooltip: '删除模板',
                                        onPressed: () => _deleteTemplate(t),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                offset: const Offset(0, -2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openEditTemplate(
                    TemplateManager.defaultCard.copyWith(
                      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: '新建自定义模板',
                      isBuiltin: false,
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('手动创建'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openAiCreateDialog,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('AI 生成新模板'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF192D50),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
      ),
    );
  }
}

/// AI 生成模板弹窗
class _AiCreateTemplateSheet extends StatefulWidget {
  const _AiCreateTemplateSheet();

  @override
  State<_AiCreateTemplateSheet> createState() => _AiCreateTemplateSheetState();
}

class _AiCreateTemplateSheetState extends State<_AiCreateTemplateSheet> {
  final TextEditingController _promptController = TextEditingController();
  File? _selectedImage;
  bool _isGenerating = false;
  String _statusMsg = '';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  Future<void> _startGenerate() async {
    final text = _promptController.text.trim();
    if (text.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请提供文字描述或上传一张参考排版图片！')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMsg = '正在调用 AI 视觉与语义分析排版结构...';
    });

    try {
      final generated = await TemplateAiGenerator.generateTemplate(
        promptText: text,
        imageFile: _selectedImage,
      );
      if (mounted) {
        Navigator.pop(context, generated);
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _statusMsg = '';
      });
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('生成失败'),
            content: Text('$e'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF192D50)),
                const SizedBox(width: 8),
                const Text(
                  'AI 智能生成排版模板',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '可上传一张你喜欢的杂志/APP排版截图，或用文字描述风格（如“日系杂志留白风，带小头像和灰色小字”）：',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                hintText: '描述排版需求，例如：简约报刊风，左右分栏，正文行高宽松，隐藏签名档...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isGenerating ? null : _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: Text(_selectedImage == null ? '上传参考图片' : '重新选择图片'),
                ),
                if (_selectedImage != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '已选图 (${_selectedImage!.path.split('/').last.split('\\').last})',
                    style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                ],
              ],
            ),
            if (_selectedImage != null) ...[
              const SizedBox(height: 8),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_selectedImage!, fit: BoxFit.cover),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_isGenerating) ...[
              Row(
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_statusMsg, style: const TextStyle(fontSize: 12, color: Color(0xFF192D50))),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isGenerating ? null : _startGenerate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('开始 AI 解析并生成模板'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF192D50),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 所见即所得可视化模板编辑器
class TemplateEditorScreen extends StatefulWidget {
  final LayoutTemplate template;

  const TemplateEditorScreen({super.key, required this.template});

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  late LayoutTemplate _current;
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _cssController;

  @override
  void initState() {
    super.initState();
    _current = widget.template.copyWith();
    if (_current.isBuiltin) {
      _current.id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      _current.name = '${_current.name} (副本)';
      _current.isBuiltin = false;
    }
    _nameController = TextEditingController(text: _current.name);
    _descController = TextEditingController(text: _current.description);
    _cssController = TextEditingController(text: _current.customCss);
  }

  void _showColorPickerSheet(String title, String currentColor, ValueChanged<String> onColorSelected) {
    final colors = [
      {'name': '黑色', 'hex': '#111827'},
      {'name': '深灰', 'hex': '#374151'},
      {'name': '中灰', 'hex': '#6b7280'},
      {'name': '浅灰', 'hex': '#9ca3af'},
      {'name': '经典蓝', 'hex': '#192D50'},
      {'name': '天蓝', 'hex': '#0369a1'},
      {'name': '红/棕', 'hex': '#b91c1c'},
      {'name': '墨绿', 'hex': '#047857'},
      {'name': '边框浅灰', 'hex': '#e5e7eb'},
      {'name': '纯白', 'hex': '#ffffff'},
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设置 $title 颜色', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors.map((c) {
                final hex = c['hex']!;
                final isCur = hex.toLowerCase() == currentColor.toLowerCase();
                return ChoiceChip(
                  label: Text('${c['name']} ($hex)'),
                  selected: isCur,
                  selectedColor: const Color(0xFF192D50),
                  labelStyle: TextStyle(
                    color: isCur ? Colors.white : Colors.black87,
                  ),
                  onSelected: (val) {
                    if (val) {
                      Navigator.pop(ctx);
                      onColorSelected(hex);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模板所见即所得编辑器', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF192D50),
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () {
              _current.name = _nameController.text.trim().isEmpty ? '未命名模板' : _nameController.text.trim();
              _current.description = _descController.text.trim();
              _current.customCss = _cssController.text.trim();
              Navigator.pop(context, _current);
            },
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('保存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '模板名称', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: '模板描述', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),

            // 所见即所得卡片模拟预览 (点击文字直接修改)
            const Text(
              '💡 交互式预览（点击下方各个元素直接修改颜色/大小/显隐）：',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF192D50)),
            ),
            const SizedBox(height: 8),
            _buildInteractiveMockCard(),

            const Divider(height: 28),

            const Text('排版架构与模式：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'card', label: Text('现代卡片流')),
                ButtonSegment(value: 'split', label: Text('经典左右分栏')),
                ButtonSegment(value: 'minimal', label: Text('极简纯享')),
              ],
              selected: {_current.layoutMode},
              onSelectionChanged: (val) {
                setState(() => _current.layoutMode = val.first);
              },
            ),

            const SizedBox(height: 16),
            const Text('用户信息三要素设置：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            SwitchListTile(
              title: const Text('1. 头像 (Avatar)'),
              subtitle: Text('尺寸: ${_current.avatarSize}px · ${_current.avatarRound ? "圆形" : "圆角方形"}'),
              value: _current.showAvatar,
              onChanged: (val) => setState(() => _current.showAvatar = val),
            ),
            if (_current.showAvatar)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('圆角:'),
                    Switch(
                      value: _current.avatarRound,
                      onChanged: (v) => setState(() => _current.avatarRound = v),
                    ),
                    const SizedBox(width: 16),
                    Text('边框: ${_current.avatarBorderColor}'),
                    IconButton(
                      icon: const Icon(Icons.color_lens, size: 18),
                      onPressed: () => _showColorPickerSheet(
                        '头像边框',
                        _current.avatarBorderColor,
                        (c) => setState(() => _current.avatarBorderColor = c),
                      ),
                    ),
                  ],
                ),
              ),

            SwitchListTile(
              title: const Text('2. 用户名 (Username)'),
              subtitle: Text('颜色: ${_current.usernameColor} · ${_current.usernameBold ? "加粗" : "常规"}'),
              value: _current.showUsername,
              onChanged: (val) => setState(() => _current.showUsername = val),
            ),

            SwitchListTile(
              title: const Text('3. 剩余其他信息 (等级、星级、UID、积分、注册日等)'),
              subtitle: Text('颜色: ${_current.otherInfoColor} · 统一字号: ${_current.otherInfoFontSize == 0 ? "随系统" : "${_current.otherInfoFontSize}px"}'),
              value: _current.showOtherInfo,
              onChanged: (val) => setState(() => _current.showOtherInfo = val),
            ),

            const Divider(height: 24),
            const Text('楼层元数据 & 签名：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            SwitchListTile(
              title: const Text('楼层序号 (楼主/沙发/2楼)'),
              value: _current.showFloorBadge,
              onChanged: (val) => setState(() => _current.showFloorBadge = val),
            ),
            SwitchListTile(
              title: const Text('发帖时间'),
              value: _current.showPostTime,
              onChanged: (val) => setState(() => _current.showPostTime = val),
            ),
            SwitchListTile(
              title: const Text('签名档 (Signature)'),
              value: _current.showSignature,
              onChanged: (val) => setState(() => _current.showSignature = val),
            ),
            SwitchListTile(
              title: const Text('楼层间分割线'),
              value: _current.showFloorDivider,
              onChanged: (val) => setState(() => _current.showFloorDivider = val),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _cssController,
              decoration: const InputDecoration(
                labelText: '高级自定义 CSS',
                hintText: '如：.d2pdf-custom-header { box-shadow: 0 1px 3px rgba(0,0,0,0.1); }',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveMockCard() {
    if (_current.layoutMode == 'split') {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧：经典论坛作者侧边栏
              Container(
                width: 130,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50.withOpacity(0.5),
                  border: Border(
                    right: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 用户名
                    if (_current.showUsername)
                      InkWell(
                        onTap: () => _showColorPickerSheet(
                          '用户名',
                          _current.usernameColor,
                          (c) => setState(() => _current.usernameColor = c),
                        ),
                        child: Text(
                          'HelloEarth',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _current.usernameBold ? FontWeight.bold : FontWeight.normal,
                            color: Color(int.parse(_current.usernameColor.replaceFirst('#', '0xFF'))),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    // 头像
                    if (_current.showAvatar)
                      InkWell(
                        onTap: () {
                          setState(() => _current.avatarRound = !_current.avatarRound);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已切换头像形态：${_current.avatarRound ? "圆形" : "方形"}')),
                          );
                        },
                        child: Container(
                          width: _current.avatarSize.toDouble().clamp(36.0, 56.0),
                          height: _current.avatarSize.toDouble().clamp(36.0, 56.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF192D50),
                            shape: _current.avatarRound ? BoxShape.circle : BoxShape.rectangle,
                            borderRadius: _current.avatarRound ? null : BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          alignment: Alignment.center,
                          child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    // 剩余其他信息（星级、UID、帖子、积分）
                    if (_current.showOtherInfo)
                      InkWell(
                        onTap: () => _showColorPickerSheet(
                          '其他信息',
                          _current.otherInfoColor,
                          (c) => setState(() => _current.otherInfoColor = c),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '金牌会员 ☀️☀️🌙',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(int.parse(_current.otherInfoColor.replaceFirst('#', '0xFF'))),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'UID: 38294\n帖子: 154\n积分: 890\n注册: 2018-5-1',
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.3,
                                color: Color(int.parse(_current.otherInfoColor.replaceFirst('#', '0xFF'))),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // 右侧：正文栏与原生顶部信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // postinfo 栏
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_current.showPostTime)
                            InkWell(
                              onTap: () => _showColorPickerSheet(
                                '发帖时间',
                                _current.postTimeColor,
                                (c) => setState(() => _current.postTimeColor = c),
                              ),
                              child: Text(
                                '发表于 2026-10-14 09:30',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF'))),
                                ),
                              ),
                            )
                          else
                            const SizedBox(),
                          if (_current.showFloorBadge)
                            InkWell(
                              onTap: () => _showColorPickerSheet(
                                '楼层号',
                                _current.floorColor,
                                (c) => setState(() => _current.floorColor = c),
                              ),
                              child: Text(
                                '1# 楼主',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(int.parse(_current.floorColor.replaceFirst('#', '0xFF'))),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 正文区
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '这是经典论坛左右分栏的楼层正文：左侧保持原汁原味的作者头像、等级星级、积分注册资料；右侧上方为发表时间与楼层序号，所有功能按钮（回复/引用/评分）均已自动去除。',
                        style: TextStyle(
                          fontSize: 13,
                          height: _current.postLineHeight,
                          color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // 签名档区
                    if (_current.showSignature)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: Colors.grey.shade100)),
                          color: Colors.grey.shade50,
                        ),
                        child: const Text(
                          '—— 原汁原味个性签名档',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部作者与楼层条 (缩窄紧凑化)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: _current.showFloorDivider ? Colors.grey.shade200 : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                // 头像
                if (_current.showAvatar)
                  InkWell(
                    onTap: () {
                      setState(() => _current.avatarRound = !_current.avatarRound);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已切换头像形态：${_current.avatarRound ? "圆形" : "圆角方形"}')),
                      );
                    },
                    child: Container(
                      width: _current.avatarSize.toDouble().clamp(24.0, 56.0),
                      height: _current.avatarSize.toDouble().clamp(24.0, 56.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF192D50),
                        shape: _current.avatarRound ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: _current.avatarRound ? null : BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户名
                      if (_current.showUsername)
                        InkWell(
                          onTap: () => _showColorPickerSheet(
                            '用户名',
                            _current.usernameColor,
                            (c) => setState(() => _current.usernameColor = c),
                          ),
                          child: Text(
                            'HelloEarth (点击调色)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: _current.usernameBold ? FontWeight.bold : FontWeight.normal,
                              color: Color(int.parse(_current.usernameColor.replaceFirst('#', '0xFF'))),
                            ),
                          ),
                        ),
                      // 剩余其他信息
                      if (_current.showOtherInfo)
                        InkWell(
                          onTap: () => _showColorPickerSheet(
                            '其他信息',
                            _current.otherInfoColor,
                            (c) => setState(() => _current.otherInfoColor = c),
                          ),
                          child: Text(
                            '☀️☀️🌙 (金牌会员) · UID: 38294 · 帖子: 154 · 积分: 890',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(int.parse(_current.otherInfoColor.replaceFirst('#', '0xFF'))),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 时间与楼层
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_current.showFloorBadge)
                      InkWell(
                        onTap: () => _showColorPickerSheet(
                          '楼层号',
                          _current.floorColor,
                          (c) => setState(() => _current.floorColor = c),
                        ),
                        child: Text(
                          '楼主 (点击调色)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(int.parse(_current.floorColor.replaceFirst('#', '0xFF'))),
                          ),
                        ),
                      ),
                    if (_current.showPostTime)
                      InkWell(
                        onTap: () => _showColorPickerSheet(
                          '发帖时间',
                          _current.postTimeColor,
                          (c) => setState(() => _current.postTimeColor = c),
                        ),
                        child: Text(
                          '2026-10-14 09:30',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF'))),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // 正文区
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '这是论坛楼层正文预览效果：文字排版紧凑适度，段落间距自然。点击可设置行高与颜色。',
              style: TextStyle(
                fontSize: 14,
                height: _current.postLineHeight,
                color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
              ),
            ),
          ),
          // 签名档区
          if (_current.showSignature)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.grey.shade50,
              child: const Text(
                '—— 这是一条个性签名档 (已开启展示)',
                style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
