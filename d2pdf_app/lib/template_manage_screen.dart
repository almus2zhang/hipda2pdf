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
    final customModelController = TextEditingController(text: selectedModel);
    bool isTesting = false;
    String? testResult;
    bool testSuccess = false;

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
                          setDialogState(() {
                            selectedModel = m;
                            customModelController.text = m;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customModelController,
                  decoration: const InputDecoration(
                    labelText: '当前使用模型名称 (可自定义)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    if (val.trim().isNotEmpty) {
                      setDialogState(() {
                        selectedModel = val.trim();
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: isTesting
                          ? null
                          : () async {
                              final key = apiKeyController.text.trim();
                              if (key.isEmpty) {
                                setDialogState(() {
                                  testResult = '请先填写 API Key (密钥)！';
                                  testSuccess = false;
                                });
                                return;
                              }
                              setDialogState(() {
                                isTesting = true;
                                testResult = '正在连接并测试模型 $selectedModel ...';
                                testSuccess = false;
                              });
                              try {
                                final res = await TemplateAiGenerator.testConnection(
                                  baseUrl: baseUrlController.text,
                                  apiKey: key,
                                  model: selectedModel,
                                );
                                setDialogState(() {
                                  isTesting = false;
                                  testResult = res;
                                  testSuccess = true;
                                });
                              } catch (e) {
                                setDialogState(() {
                                  isTesting = false;
                                  testResult = '测试失败：${e.toString().replaceFirst('Exception: ', '')}';
                                  testSuccess = false;
                                });
                              }
                            },
                      icon: isTesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check, size: 16),
                      label: Text(isTesting ? '正在测试...' : '测试模型连接'),
                    ),
                  ],
                ),
                if (testResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: testSuccess ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: testSuccess ? Colors.green.shade300 : Colors.red.shade300,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          testSuccess ? Icons.check_circle : Icons.error_outline,
                          size: 18,
                          color: testSuccess ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            testResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: testSuccess ? Colors.green.shade900 : Colors.red.shade900,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await AiServiceConfig.setBaseUrl(baseUrlController.text);
                await AiServiceConfig.setApiKey(apiKeyController.text);
                await AiServiceConfig.setModel(selectedModel);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.save, size: 16),
              label: const Text('保存配置'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF192D50)),
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
                                    _buildBadge(_getLayoutModeBadgeText(t.layoutMode)),
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

  static String _getLayoutModeBadgeText(String mode) {
    switch (mode) {
      case 'card':
        return '现代气泡';
      case 'split':
        return '左右分栏';
      case 'minimal':
        return '极简纯享';
      case 'raw':
        return '原汁原味';
      case 'magazine':
        return '杂志画报';
      case 'timeline':
        return '时间轴流';
      case 'novel':
        return '典雅书卷';
      default:
        return '核心: $mode';
    }
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
  String _currentModel = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentModel();
  }

  Future<void> _loadCurrentModel() async {
    final m = await AiServiceConfig.getModel();
    if (mounted) {
      setState(() {
        _currentModel = m;
      });
    }
  }

  bool get _isVisionModel {
    final m = _currentModel.toLowerCase();
    return m.contains('vl') || m.contains('vision') || m.contains('4v') || m.contains('omni');
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
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
              if (!_isVisionModel) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '当前配置的模型 ($_currentModel) 为纯文本模型，AI 将依据您的文字描述与现代排版规则生成模板。若希望 AI 直接识别图片像素色彩与排版细节，请在右上角 AI 设置中选用支持视觉的多模态模型。',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  late int _editingWidth;
  bool _previewFitScreen = true; // 预览模式：true 为缩放适应屏幕，false 为 1:1 真实宽度滑动

  @override
  void initState() {
    super.initState();
    _current = widget.template.copyWith();
    if (_current.isBuiltin) {
      _current.id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      _current.name = '${_current.name} (副本)';
      _current.isBuiltin = false;
    }
    _editingWidth = _current.defaultWidth;
    _nameController = TextEditingController(text: _current.name);
    _descController = TextEditingController(text: _current.description);
    _cssController = TextEditingController(text: _current.customCss);
  }

  void _showColorPickerSheet(String title, String currentColor, ValueChanged<String> onColorSelected) {
    final colors = [
      {'name': '纯白', 'hex': '#ffffff'},
      {'name': '淡蓝气泡', 'hex': '#f0f7ff'},
      {'name': '淡青气泡', 'hex': '#f0fdf4'},
      {'name': '淡紫气泡', 'hex': '#faf5ff'},
      {'name': '浅米气泡', 'hex': '#fefce8'},
      {'name': '极淡灰', 'hex': '#f8fafc'},
      {'name': '页面底灰', 'hex': '#f1f5f9'},
      {'name': '边框浅灰', 'hex': '#e2e8f0'},
      {'name': '边框中灰', 'hex': '#cbd5e1'},
      {'name': '经典蓝', 'hex': '#192D50'},
      {'name': '天蓝', 'hex': '#0369a1'},
      {'name': '黑色', 'hex': '#111827'},
      {'name': '深灰', 'hex': '#374151'},
      {'name': '中灰', 'hex': '#6b7280'},
      {'name': '浅灰', 'hex': '#9ca3af'},
      {'name': '红/棕', 'hex': '#b91c1c'},
      {'name': '墨绿', 'hex': '#047857'},
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

  void _showAddCustomCoreDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加新排版核心架构', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在原有 4 种基础核心与拓展核心上直接追加新架构标识（如 grid, retro, compact 等）。系统将自动注入结构化 DOM，您可直接微调或通过下方自定义 CSS 精修。',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新核心架构标识',
                hintText: '如: retro 或 grid',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx);
                setState(() {
                  _current.layoutMode = val;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已成功切换并追加新核心架构: $val')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF192D50)),
            child: const Text('确定追加'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLayoutModeChips() {
    final List<Map<String, dynamic>> baseCores = [
      {'id': 'card', 'label': '现代气泡卡片', 'icon': Icons.chat_bubble_outline},
      {'id': 'split', 'label': '经典左右分栏', 'icon': Icons.view_column_outlined},
      {'id': 'minimal', 'label': '极简纯享', 'icon': Icons.format_align_left},
      {'id': 'raw', 'label': '原汁原味', 'icon': Icons.history_edu},
      {'id': 'magazine', 'label': '杂志画报', 'icon': Icons.auto_stories},
      {'id': 'timeline', 'label': '时间轴流', 'icon': Icons.timeline},
      {'id': 'novel', 'label': '典雅书卷', 'icon': Icons.menu_book},
    ];

    final hasCurrent = baseCores.any((c) => c['id'] == _current.layoutMode);
    final allCores = List<Map<String, dynamic>>.from(baseCores);
    if (!hasCurrent) {
      allCores.add({
        'id': _current.layoutMode,
        'label': '新核心: ${_current.layoutMode}',
        'icon': Icons.dashboard_customize,
      });
    }

    return allCores.map((c) {
      final String id = c['id'] as String;
      final String label = c['label'] as String;
      final IconData icon = c['icon'] as IconData;
      final bool isSel = _current.layoutMode == id;

      return ChoiceChip(
        avatar: Icon(icon, size: 16, color: isSel ? Colors.white : const Color(0xFF192D50)),
        label: Text(label),
        selected: isSel,
        selectedColor: const Color(0xFF192D50),
        labelStyle: TextStyle(
          color: isSel ? Colors.white : Colors.black87,
          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        onSelected: (val) {
          if (val) {
            setState(() => _current.layoutMode = id);
          }
        },
      );
    }).toList();
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
      body: Column(
        children: [
          // 顶部固定展示区 (Sticky Header: 宽度条 + 实时所见即所得预览，向下滚动时不被顶出窗口)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWidthBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF192D50)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '实时预览 (${_editingWidth}px · ${_previewFitScreen ? "缩放适应" : "1:1真实"}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF192D50)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            child: SegmentedButton<bool>(
                              style: ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 6, vertical: 0)),
                              ),
                              segments: const [
                                ButtonSegment<bool>(
                                  value: true,
                                  label: Text('缩放适应', style: TextStyle(fontSize: 10)),
                                  icon: Icon(Icons.fit_screen, size: 12),
                                ),
                                ButtonSegment<bool>(
                                  value: false,
                                  label: Text('1:1 真实', style: TextStyle(fontSize: 10)),
                                  icon: Icon(Icons.aspect_ratio, size: 12),
                                ),
                              ],
                              selected: {_previewFitScreen},
                              onSelectionChanged: (val) {
                                setState(() => _previewFitScreen = val.first);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: _previewFitScreen
                            ? SingleChildScrollView(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    width: _editingWidth.toDouble(),
                                    child: _buildInteractiveMockCard(),
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  child: SizedBox(
                                    width: _editingWidth.toDouble(),
                                    child: _buildInteractiveMockCard(),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 下方滚动配置区 (用户任意向下滚动，顶部的预览窗口始终固定在最上方)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

                Row(
                  children: [
                    const Text('排版架构与模式：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _showAddCustomCoreDialog,
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('添加新核心', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _buildLayoutModeChips(),
                ),

                if (_current.layoutMode == 'card' ||
                    _current.layoutMode == 'magazine' ||
                    _current.layoutMode == 'timeline' ||
                    _current.layoutMode == 'novel' ||
                    (_current.layoutMode != 'split' && _current.layoutMode != 'raw' && _current.layoutMode != 'minimal')) ...[
                  const Divider(height: 24),
                  Text(
                    _current.layoutMode == 'card'
                        ? '气泡卡片样式与背景设置：'
                        : (_current.layoutMode == 'magazine'
                            ? '画报卡片样式与背景设置：'
                            : (_current.layoutMode == 'timeline'
                                ? '时间轴卡片与背景设置：'
                                : (_current.layoutMode == 'novel'
                                    ? '书卷装帧与版面底色设置：'
                                    : '核心卡片样式与背景设置：'))),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),

                  // 气泡主颜色
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(int.parse(_current.cardBackgroundColor.replaceFirst('#', '0xFF'))),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                    ),
                    title: const Text('气泡主颜色 (单数楼层)'),
                    subtitle: Text(_current.cardBackgroundColor),
                    trailing: const Icon(Icons.color_lens, size: 20),
                    onTap: () => _showColorPickerSheet(
                      '气泡主颜色',
                      _current.cardBackgroundColor,
                      (c) => setState(() => _current.cardBackgroundColor = c),
                    ),
                  ),

                  // 交替双色开关
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开启气泡交替双色'),
                    subtitle: const Text('偶数楼层显示交替副颜色，增强阅读层次'),
                    value: _current.enableAlternateBubbleColor,
                    onChanged: (val) => setState(() => _current.enableAlternateBubbleColor = val),
                  ),

                  // 气泡副颜色
                  if (_current.enableAlternateBubbleColor)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(int.parse(_current.alternateBubbleColor.replaceFirst('#', '0xFF'))),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                      ),
                      title: const Text('气泡交替副颜色 (双数楼层)'),
                      subtitle: Text(_current.alternateBubbleColor),
                      trailing: const Icon(Icons.color_lens, size: 20),
                      onTap: () => _showColorPickerSheet(
                        '气泡交替副颜色',
                        _current.alternateBubbleColor,
                        (c) => setState(() => _current.alternateBubbleColor = c),
                      ),
                    ),

                  // 页面底色背景
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(int.parse(_current.pageBackgroundColor.replaceFirst('#', '0xFF'))),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                    ),
                    title: const Text('页面背景底色'),
                    subtitle: Text(_current.pageBackgroundColor),
                    trailing: const Icon(Icons.color_lens, size: 20),
                    onTap: () => _showColorPickerSheet(
                      '页面背景底色',
                      _current.pageBackgroundColor,
                      (c) => setState(() => _current.pageBackgroundColor = c),
                    ),
                  ),

                  // 气泡边框粗细与颜色
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(int.parse(_current.cardBorderColor.replaceFirst('#', '0xFF'))),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                    ),
                    title: const Text('气泡边框颜色'),
                    subtitle: Text(_current.cardBorderColor),
                    trailing: const Icon(Icons.color_lens, size: 20),
                    onTap: () => _showColorPickerSheet(
                      '边框颜色',
                      _current.cardBorderColor,
                      (c) => setState(() => _current.cardBorderColor = c),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Text('边框大小:'),
                        const SizedBox(width: 12),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('无')),
                            ButtonSegment(value: 1, label: Text('1px')),
                            ButtonSegment(value: 2, label: Text('2px')),
                            ButtonSegment(value: 3, label: Text('3px')),
                          ],
                          selected: {_current.cardBorderWidth},
                          onSelectionChanged: (val) => setState(() => _current.cardBorderWidth = val.first),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Text('气泡边角:'),
                        const SizedBox(width: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('直角 (0px)')),
                            ButtonSegment(value: true, label: Text('圆角')),
                          ],
                          selected: {_current.cardBorderRadius > 0},
                          onSelectionChanged: (val) {
                            setState(() {
                              if (!val.first) {
                                _current.cardBorderRadius = 0;
                              } else {
                                _current.cardBorderRadius = 10;
                              }
                            });
                          },
                        ),
                        if (_current.cardBorderRadius > 0) ...[
                          const SizedBox(width: 8),
                          Text('${_current.cardBorderRadius}px', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            onPressed: _current.cardBorderRadius > 2
                                ? () => setState(() => _current.cardBorderRadius -= 2)
                                : null,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            onPressed: _current.cardBorderRadius < 30
                                ? () => setState(() => _current.cardBorderRadius += 2)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Text('气泡间距:'),
                        const SizedBox(width: 8),
                        Text('${_current.cardSpacing}px', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline, size: 18),
                          onPressed: _current.cardSpacing > 2
                              ? () => setState(() => _current.cardSpacing -= 2)
                              : null,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          onPressed: _current.cardSpacing < 30
                              ? () => setState(() => _current.cardSpacing += 2)
                              : null,
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 4,
                          children: [6, 8, 10, 14, 18].map((s) {
                            final isSel = _current.cardSpacing == s;
                            return ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text('${s}px', style: const TextStyle(fontSize: 10)),
                              selected: isSel,
                              onSelected: (val) {
                                if (val) setState(() => _current.cardSpacing = s);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_current.layoutMode == 'split') ...[
                  const Divider(height: 24),
                  const Text('经典左右分栏设置：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Text('基准左侧栏宽:'),
                        const SizedBox(width: 8),
                        Text('${_current.splitAuthorWidth}px', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline, size: 18),
                          onPressed: _current.splitAuthorWidth > 80
                              ? () => setState(() => _current.splitAuthorWidth -= 10)
                              : null,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          onPressed: _current.splitAuthorWidth < 260
                              ? () => setState(() => _current.splitAuthorWidth += 10)
                              : null,
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 4,
                          children: [120, 140, 160, 180].map((w) {
                            final isSel = _current.splitAuthorWidth == w;
                            return ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text('${w}px', style: const TextStyle(fontSize: 10)),
                              selected: isSel,
                              onSelected: (val) {
                                if (val) setState(() => _current.splitAuthorWidth = w);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_current.layoutMode == 'raw') ...[
                  const Divider(height: 24),
                  const Text('原汁原味设置：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF192D50).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF192D50).withOpacity(0.15)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Color(0xFF192D50)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '原汁原味模式：100% 保留 Discuz 经典原生左右分栏与边框排版，不添加现代气泡卡片装饰。可通过上方宽度设定条微调各宽度的阅读尺寸与字体排版。',
                            style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF192D50)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Text('用户信息三要素设置：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                SwitchListTile(
                  title: const Text('1. 头像 (Avatar)'),
                  subtitle: Text('通用基准尺寸: ${_current.avatarSize}px · ${_current.avatarRound ? "圆形" : "圆角方形"}'),
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
                  title: const Text('楼层作者下方分割线'),
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
        ],
      ),
    );
  }

  Widget _buildWidthBar() {
    final curAvatar = _current.getAvatarSizeForWidth(_editingWidth);
    final curRadius = _current.getBorderRadiusForWidth(_editingWidth);
    final curSpacing = _current.getCardSpacingForWidth(_editingWidth);
    final curAuthorWidth = _current.getAuthorWidthForWidth(_editingWidth);

    final showAvatar = _current.getShowAvatarForWidth(_editingWidth);
    final showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final showOtherInfo = _current.getShowOtherInfoForWidth(_editingWidth);
    final showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final showPostTime = _current.getShowPostTimeForWidth(_editingWidth);
    final showSignature = _current.getShowSignatureForWidth(_editingWidth);
    final showFloorDivider = _current.getShowFloorDividerForWidth(_editingWidth);

    final bool hasWidthCustomization = _current.widthConfigs.containsKey(_editingWidth.toString());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 16, color: Color(0xFF192D50)),
              const SizedBox(width: 4),
              Text(
                '排版宽度设定条 (${_editingWidth}px)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF192D50)),
              ),
              const Spacer(),
              if (hasWidthCustomization)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () {
                    setState(() {
                      _current.widthConfigs.remove(_editingWidth.toString());
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已恢复 ${_editingWidth}px 的设置为跟随模板默认值')),
                    );
                  },
                  child: const Text('重置此宽度', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                ),
              InkWell(
                onTap: () {
                  setState(() => _current.defaultWidth = _editingWidth);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已将 ${_editingWidth}px 设为此模板的默认宽度')),
                  );
                },
                child: Row(
                  children: [
                    Icon(
                      _current.defaultWidth == _editingWidth ? Icons.star : Icons.star_outline,
                      size: 15,
                      color: _current.defaultWidth == _editingWidth ? Colors.amber.shade800 : Colors.blueGrey,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _current.defaultWidth == _editingWidth ? '默认宽度' : '设为默认',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _current.defaultWidth == _editingWidth ? Colors.amber.shade800 : Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [600, 800, 1000, 1280, 1440, 1920].map((w) {
                final bool isSel = (_editingWidth == w);
                final String label = (w == 600)
                    ? '600px 手机'
                    : (w == 800)
                        ? '800px 标准'
                        : (w == 1280)
                            ? '1280px 超宽'
                            : '${w}px';
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(label),
                    selected: isSel,
                    selectedColor: const Color(0xFF192D50),
                    labelStyle: TextStyle(
                      color: isSel ? Colors.white : const Color(0xFF192D50),
                      fontSize: 11,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _editingWidth = w);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text('针对 ${_editingWidth}px 头像: ${curAvatar}px', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  onPressed: curAvatar > 20
                      ? () {
                          setState(() {
                            _current.setWidthConfig(_editingWidth, 'avatarSize', curAvatar - 2);
                          });
                        }
                      : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  onPressed: curAvatar < 64
                      ? () {
                          setState(() {
                            _current.setWidthConfig(_editingWidth, 'avatarSize', curAvatar + 2);
                          });
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                if (_current.layoutMode == 'card') ...[
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    label: const Text('直角', style: TextStyle(fontSize: 10)),
                    selected: curRadius == 0,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _current.setWidthConfig(_editingWidth, 'borderRadius', 0);
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    label: Text(curRadius > 0 ? '圆角 ${curRadius}px' : '圆角', style: const TextStyle(fontSize: 10)),
                    selected: curRadius > 0,
                    onSelected: (val) {
                      if (val) {
                        final target = _current.cardBorderRadius > 0 ? _current.cardBorderRadius : 10;
                        setState(() {
                          _current.setWidthConfig(_editingWidth, 'borderRadius', target);
                        });
                      }
                    },
                  ),
                  if (curRadius > 0) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                      onPressed: curRadius > 2
                          ? () => setState(() => _current.setWidthConfig(_editingWidth, 'borderRadius', curRadius - 2))
                          : null,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      onPressed: curRadius < 30
                          ? () => setState(() => _current.setWidthConfig(_editingWidth, 'borderRadius', curRadius + 2))
                          : null,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text('间距: ${curSpacing}px', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    onPressed: curSpacing > 2
                        ? () => setState(() => _current.setWidthConfig(_editingWidth, 'cardSpacing', curSpacing - 2))
                        : null,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    onPressed: curSpacing < 30
                        ? () => setState(() => _current.setWidthConfig(_editingWidth, 'cardSpacing', curSpacing + 2))
                        : null,
                  ),
                ],
                if (_current.layoutMode == 'split') ...[
                  Text('左栏宽: ${curAuthorWidth}px', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    onPressed: curAuthorWidth > 80
                        ? () => setState(() => _current.setWidthConfig(_editingWidth, 'authorWidth', curAuthorWidth - 10))
                        : null,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    onPressed: curAuthorWidth < 260
                        ? () => setState(() => _current.setWidthConfig(_editingWidth, 'authorWidth', curAuthorWidth + 10))
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 针对当前宽度定制元素显示（增加或减少某些元素显示）
          Row(
            children: [
              Text('此宽度元素: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildElementToggleChip('头像', 'showAvatar', showAvatar),
                      _buildElementToggleChip('用户名', 'showUsername', showUsername),
                      _buildElementToggleChip('附加信息', 'showOtherInfo', showOtherInfo),
                      _buildElementToggleChip('楼层', 'showFloorBadge', showFloorBadge),
                      _buildElementToggleChip('时间', 'showPostTime', showPostTime),
                      _buildElementToggleChip('签名', 'showSignature', showSignature),
                      _buildElementToggleChip('分割线', 'showFloorDivider', showFloorDivider),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildElementToggleChip(String label, String key, bool isActive) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        label: Text(label, style: TextStyle(fontSize: 10, color: isActive ? Colors.white : Colors.black87)),
        selected: isActive,
        selectedColor: const Color(0xFF192D50),
        checkmarkColor: Colors.white,
        showCheckmark: false,
        avatar: Icon(
          isActive ? Icons.check_circle : Icons.remove_circle_outline,
          size: 12,
          color: isActive ? Colors.white : Colors.grey,
        ),
        onSelected: (val) {
          setState(() {
            _current.setElementVisibleForWidth(_editingWidth, key, val);
          });
        },
      ),
    );
  }

  Widget _buildInteractiveMockCard() {
    Widget card;
    if (_current.layoutMode == 'split') {
      card = _buildSplitMock();
    } else if (_current.layoutMode == 'minimal') {
      card = _buildMinimalMock();
    } else if (_current.layoutMode == 'raw') {
      card = _buildRawMock();
    } else if (_current.layoutMode == 'magazine') {
      card = _buildMagazineMock();
    } else if (_current.layoutMode == 'timeline') {
      card = _buildTimelineMock();
    } else if (_current.layoutMode == 'novel') {
      card = _buildNovelMock();
    } else if (_current.layoutMode == 'card') {
      card = _buildBubbleCardMock();
    } else {
      card = _buildCustomCoreMock();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: const Text(
            '帖子标题演示示例 - Hi!PDA D2PDF',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        card,
      ],
    );
  }

  Widget _buildBubbleCardMock() {
    final curAvatar = _current.getAvatarSizeForWidth(_editingWidth).toDouble().clamp(20.0, 56.0);
    final curRadius = _current.getBorderRadiusForWidth(_editingWidth).toDouble();
    final curSpacing = _current.getCardSpacingForWidth(_editingWidth).toDouble();
    final borderColor = Color(int.parse(_current.cardBorderColor.replaceFirst('#', '0xFF')));
    final cardBg1 = Color(int.parse(_current.cardBackgroundColor.replaceFirst('#', '0xFF')));
    final cardBg2 = Color(int.parse((_current.enableAlternateBubbleColor ? _current.alternateBubbleColor : _current.cardBackgroundColor).replaceFirst('#', '0xFF')));
    final pageBg = Color(int.parse(_current.pageBackgroundColor.replaceFirst('#', '0xFF')));

    final bool showAvatar = _current.getShowAvatarForWidth(_editingWidth);
    final bool showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final bool showOtherInfo = _current.getShowOtherInfoForWidth(_editingWidth);
    final bool showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final bool showPostTime = _current.getShowPostTimeForWidth(_editingWidth);
    final bool showFloorDivider = _current.getShowFloorDividerForWidth(_editingWidth);
    final bool showSignature = _current.getShowSignatureForWidth(_editingWidth);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '页面底色: ${_current.pageBackgroundColor}',
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showColorPickerSheet(
                  '页面背景底色',
                  _current.pageBackgroundColor,
                  (c) => setState(() => _current.pageBackgroundColor = c),
                ),
                child: const Text('点击更换底色', style: TextStyle(fontSize: 11, color: Color(0xFF0369a1), decoration: TextDecoration.underline)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 气泡 1 (楼主)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cardBg1,
              borderRadius: BorderRadius.circular(curRadius),
              border: _current.cardBorderWidth == 0 ? null : Border.all(color: borderColor, width: _current.cardBorderWidth.toDouble()),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: showFloorDivider ? Colors.black.withOpacity(0.06) : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (showAvatar)
                        InkWell(
                          onTap: () {
                            setState(() => _current.avatarRound = !_current.avatarRound);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已切换头像形态：${_current.avatarRound ? "圆形" : "圆角方形"}')),
                            );
                          },
                          child: Container(
                            width: curAvatar,
                            height: curAvatar,
                            decoration: BoxDecoration(
                              color: const Color(0xFF192D50),
                              shape: _current.avatarRound ? BoxShape.circle : BoxShape.rectangle,
                              borderRadius: _current.avatarRound ? null : BorderRadius.circular(4),
                              border: Border.all(color: Color(int.parse(_current.avatarBorderColor.replaceFirst('#', '0xFF')))),
                            ),
                            alignment: Alignment.center,
                            child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      if (showAvatar) const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showUsername)
                              InkWell(
                                onTap: () => _showColorPickerSheet('用户名', _current.usernameColor, (c) => setState(() => _current.usernameColor = c)),
                                child: Text(
                                  'HelloEarth (点击调色)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _current.usernameBold ? FontWeight.bold : FontWeight.normal,
                                    color: Color(int.parse(_current.usernameColor.replaceFirst('#', '0xFF'))),
                                  ),
                                ),
                              ),
                            if (showOtherInfo)
                              Text('金牌会员 · UID: 38294', style: TextStyle(fontSize: 10, color: Color(int.parse(_current.otherInfoColor.replaceFirst('#', '0xFF'))))),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (showFloorBadge)
                            Text('1# 楼主', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(int.parse(_current.floorColor.replaceFirst('#', '0xFF'))))),
                          if (showPostTime)
                            Text('2026-10-14 09:30', style: TextStyle(fontSize: 10, color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF'))))),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '这是第一楼气泡卡片：每楼独立气泡包裹，宽度填满，支持调整气泡颜色与圆角边框。',
                    style: TextStyle(
                      fontSize: 13,
                      height: _current.postLineHeight,
                      color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
                    ),
                  ),
                ),
                if (showSignature)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06))),
                    ),
                    child: const Text(
                      '—— 个性签名档：越过山丘，才发现无人等候',
                      style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),

          SizedBox(height: curSpacing),

          // 气泡 2 (沙发 - 展现交替双色)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cardBg2,
              borderRadius: BorderRadius.circular(curRadius),
              border: _current.cardBorderWidth == 0 ? null : Border.all(color: borderColor, width: _current.cardBorderWidth.toDouble()),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(
                    children: [
                      if (showAvatar)
                        Container(
                          width: curAvatar,
                          height: curAvatar,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0369A1),
                            shape: _current.avatarRound ? BoxShape.circle : BoxShape.rectangle,
                            borderRadius: _current.avatarRound ? null : BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: const Text('B', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      if (showAvatar) const SizedBox(width: 6),
                      if (showUsername)
                        const Expanded(
                          child: Text('沙发回复者', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        )
                      else
                        const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (showFloorBadge)
                            Text('2# 沙发', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(int.parse(_current.floorColor.replaceFirst('#', '0xFF'))))),
                          if (showPostTime)
                            Text('2026-10-14 09:35', style: TextStyle(fontSize: 10, color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF'))))),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    _current.enableAlternateBubbleColor
                        ? '这里是第二楼（偶数楼），已开启气泡交替双色 (${_current.alternateBubbleColor})！'
                        : '这里是第二楼（偶数楼），当前使用统一单色气泡。',
                    style: TextStyle(
                      fontSize: 13,
                      height: _current.postLineHeight,
                      color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
                    ),
                  ),
                ),
                if (showSignature)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.black.withOpacity(0.06))),
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
    );
  }

  Widget _buildMinimalMock() {
    final curAvatar = _current.getAvatarSizeForWidth(_editingWidth).toDouble().clamp(16.0, 48.0);
    final bool showAvatar = _current.getShowAvatarForWidth(_editingWidth);
    final bool showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final bool showPostTime = _current.getShowPostTimeForWidth(_editingWidth);
    final bool showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final bool showDivider = _current.getShowFloorDividerForWidth(_editingWidth);
    final bool showSignature = _current.getShowSignatureForWidth(_editingWidth);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          left: BorderSide(color: Colors.grey.shade300),
          right: BorderSide(color: Colors.grey.shade300),
          bottom: const BorderSide(color: Color(0xFFE9E9E9), width: 4),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: showDivider ? Colors.grey.shade200 : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (showAvatar) ...[
                      InkWell(
                        onTap: () {
                          setState(() => _current.avatarRound = !_current.avatarRound);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已切换头像形态：${_current.avatarRound ? "圆形" : "圆角方形"}')),
                          );
                        },
                        child: Container(
                          width: curAvatar,
                          height: curAvatar,
                          decoration: BoxDecoration(
                            color: const Color(0xFF192D50),
                            shape: _current.avatarRound ? BoxShape.circle : BoxShape.rectangle,
                            borderRadius: _current.avatarRound ? null : BorderRadius.circular(4),
                            border: Border.all(color: Color(int.parse(_current.avatarBorderColor.replaceFirst('#', '0xFF')))),
                          ),
                          alignment: Alignment.center,
                          child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (showUsername)
                      InkWell(
                        onTap: () => _showColorPickerSheet('用户名', _current.usernameColor, (c) => setState(() => _current.usernameColor = c)),
                        child: Text(
                          'HelloEarth',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _current.usernameBold ? FontWeight.bold : FontWeight.normal,
                            color: Color(int.parse(_current.usernameColor.replaceFirst('#', '0xFF'))),
                          ),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    if (showPostTime)
                      Text(
                        '2026-10-14 09:30',
                        style: TextStyle(fontSize: 11, color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF')))),
                      ),
                    const SizedBox(width: 8),
                    if (showFloorBadge)
                      Text(
                        '1# 楼主',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(int.parse(_current.floorColor.replaceFirst('#', '0xFF'))),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '这是极简纯享排版预览：宽度填满整个页面，无多余边框与气泡阴影，专注于文档纯粹阅读。',
              style: TextStyle(
                fontSize: 13,
                height: _current.postLineHeight,
                color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
              ),
            ),
          ),
          if (showSignature)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: const Text(
                '—— 原汁原味个性签名档',
                style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSplitMock() {
    final curAvatar = _current.getAvatarSizeForWidth(_editingWidth).toDouble().clamp(24.0, 56.0);
    final curAuthorWidth = _current.getAuthorWidthForWidth(_editingWidth).toDouble();
    final bool showAvatar = _current.getShowAvatarForWidth(_editingWidth);
    final bool showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final bool showOtherInfo = _current.getShowOtherInfoForWidth(_editingWidth);
    final bool showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final bool showPostTime = _current.getShowPostTimeForWidth(_editingWidth);
    final bool showSignature = _current.getShowSignatureForWidth(_editingWidth);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          left: BorderSide(color: Colors.grey.shade300),
          right: BorderSide(color: Colors.grey.shade300),
          bottom: const BorderSide(color: Color(0xFFE9E9E9), width: 4),
        ),
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
              width: curAuthorWidth,
              padding: EdgeInsets.all(curAuthorWidth <= 120 ? 6 : 10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50.withOpacity(0.5),
                border: Border(
                  right: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showUsername)
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
                  if (showUsername && showAvatar) const SizedBox(height: 8),
                  if (showAvatar)
                    InkWell(
                      onTap: () {
                        setState(() => _current.avatarRound = !_current.avatarRound);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已切换头像形态：${_current.avatarRound ? "圆形" : "方形"}')),
                        );
                      },
                      child: Container(
                        width: curAvatar,
                        height: curAvatar,
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
                  if (showOtherInfo) ...[
                    const SizedBox(height: 8),
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
                            curAuthorWidth <= 140
                                ? 'UID: 38294\n帖子: 154\n积分: 890\n注册: 2018-5-1'
                                : 'UID: 38294\n帖子: 154\n积分: 890\n注册时间: 2018-5-1',
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
                ],
              ),
            ),

            // 右侧：正文栏与原生顶部信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (showPostTime)
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
                        if (showFloorBadge)
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
                  if (showSignature)
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

  Widget _buildRawMock() {
    final curAuthorWidth = _current.getAuthorWidthForWidth(_editingWidth).toDouble();
    final bool showAvatar = _current.getShowAvatarForWidth(_editingWidth);
    final bool showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final bool showOtherInfo = _current.getShowOtherInfoForWidth(_editingWidth);
    final bool showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final bool showPostTime = _current.getShowPostTimeForWidth(_editingWidth);
    final bool showSignature = _current.getShowSignatureForWidth(_editingWidth);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFD9D9D9)),
          left: BorderSide(color: Color(0xFFD9D9D9)),
          right: BorderSide(color: Color(0xFFD9D9D9)),
          bottom: BorderSide(color: Color(0xFFE9E9E9), width: 4),
        ),
        borderRadius: BorderRadius.zero,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：Discuz 论坛经典原生作者栏
            Container(
              width: curAuthorWidth,
              padding: EdgeInsets.all(curAuthorWidth <= 120 ? 6 : 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FA),
                border: Border(
                  right: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showUsername)
                    Text(
                      'HelloEarth',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(int.parse(_current.usernameColor.replaceFirst('#', '0xFF'))),
                      ),
                    ),
                  if (showUsername && showAvatar) const SizedBox(height: 6),
                  if (showAvatar)
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF192D50),
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      alignment: Alignment.center,
                      child: const Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  if (showOtherInfo) ...[
                    const SizedBox(height: 8),
                    Text('级别: 论坛元老', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade700)),
                    const SizedBox(height: 2),
                    Text('精华: 12  帖子: 388', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade700)),
                    const SizedBox(height: 2),
                    Text('UID: 575606', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade700)),
                    const SizedBox(height: 2),
                    Text('注册: 2008-6-1', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade700)),
                  ],
                ],
              ),
            ),

            // 右侧：Discuz 经典原生正文栏
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (showPostTime)
                          Text(
                            '发表于 2026-10-14 09:30',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF'))),
                            ),
                          )
                        else
                          const SizedBox(),
                        if (showFloorBadge)
                          Text(
                            '1# 楼主',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(int.parse(_current.floorColor.replaceFirst('#', '0xFF'))),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '这是原汁原味排版预览：100% 忠实保留 Discuz 经典左右分栏原生布局与论坛风貌，仅优化页面宽度与阅读字号，去除多余打印与无用控制按钮。',
                      style: TextStyle(
                        fontSize: 13,
                        height: _current.postLineHeight,
                        color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (showSignature)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                        color: Colors.white,
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

  Widget _buildMagazineMock() {
    final curAvatar = _current.getAvatarSizeForWidth(_editingWidth).toDouble().clamp(20.0, 56.0);
    final curRadius = _current.getBorderRadiusForWidth(_editingWidth).toDouble();
    final borderColor = Color(int.parse(_current.cardBorderColor.replaceFirst('#', '0xFF')));
    final cardBg = Color(int.parse(_current.cardBackgroundColor.replaceFirst('#', '0xFF')));

    final bool showAvatar = _current.getShowAvatarForWidth(_editingWidth);
    final bool showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final bool showOtherInfo = _current.getShowOtherInfoForWidth(_editingWidth);
    final bool showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final bool showPostTime = _current.getShowPostTimeForWidth(_editingWidth);
    final bool showSignature = _current.getShowSignatureForWidth(_editingWidth);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(curRadius > 0 ? curRadius : 6),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 杂志画报顶部横幅 (Editorial Banner)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 2)),
            ),
            child: Row(
              children: [
                if (showAvatar)
                  Container(
                    width: curAvatar,
                    height: curAvatar,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      shape: _current.avatarRound ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: _current.avatarRound ? null : BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: const Text('M', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                if (showAvatar) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showUsername)
                        Text(
                          'MAGAZINE FEATURE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: Color(int.parse(_current.usernameColor.replaceFirst('#', '0xFF'))),
                          ),
                        ),
                      if (showOtherInfo)
                        Text(
                          '特刊主编 · 深度专栏',
                          style: TextStyle(fontSize: 10, color: Color(int.parse(_current.otherInfoColor.replaceFirst('#', '0xFF')))),
                        ),
                    ],
                  ),
                ),
                if (showPostTime)
                  Text(
                    'OCT 2026',
                    style: TextStyle(fontSize: 10, color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF')))),
                  ),
                if (showPostTime && showFloorBadge) const SizedBox(width: 8),
                if (showFloorBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '1# 楼主',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '这是杂志画报排版架构：以全宽精制作者条为视觉重心，采用杂志式粗黑分割线与高定版心比例，适合图文集锦与精华帖特刊导出。',
              style: TextStyle(
                fontSize: 13,
                height: 1.75,
                color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
              ),
            ),
          ),
          if (showSignature)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
              child: const Text('—— 杂志专栏个性寄语', style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineMock() {
    final curAvatar = _current.getAvatarSizeForWidth(_editingWidth).toDouble().clamp(20.0, 48.0);
    final borderColor = Color(int.parse(_current.cardBorderColor.replaceFirst('#', '0xFF')));
    final cardBg = Color(int.parse(_current.cardBackgroundColor.replaceFirst('#', '0xFF')));

    final bool showAvatar = _current.getShowAvatarForWidth(_editingWidth);
    final bool showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final bool showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final bool showPostTime = _current.getShowPostTimeForWidth(_editingWidth);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 时间轴贯穿竖线
          Positioned(
            left: 12,
            top: 10,
            bottom: 0,
            child: Container(width: 2, color: const Color(0xFFCBD5E1)),
          ),
          // 楼层卡片
          Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 8),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        if (showAvatar)
                          Container(
                            width: curAvatar,
                            height: curAvatar,
                            decoration: BoxDecoration(
                              color: const Color(0xFF192D50),
                              shape: _current.avatarRound ? BoxShape.circle : BoxShape.rectangle,
                              borderRadius: _current.avatarRound ? null : BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: const Text('T', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        if (showAvatar) const SizedBox(width: 6),
                        if (showUsername)
                          Text('记录者', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(int.parse(_current.usernameColor.replaceFirst('#', '0xFF'))))),
                        const Spacer(),
                        if (showPostTime)
                          Text('09:30', style: TextStyle(fontSize: 10, color: Color(int.parse(_current.postTimeColor.replaceFirst('#', '0xFF'))))),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '这是时间轴流排版架构：左侧以竖向时序轴线贯穿各楼层，各楼序号作为时间轴圆点徽章，右侧内容随时间推移向下推进。',
                      style: TextStyle(fontSize: 12, height: 1.5, color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF')))),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 时间轴圆点节点
          Positioned(
            left: 2,
            top: 10,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Color(int.parse(_current.floorColor.replaceFirst('#', '0xFF'))),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 2),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                showFloorBadge ? '1' : '•',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNovelMock() {
    final bool showUsername = _current.getShowUsernameForWidth(_editingWidth);
    final bool showFloorBadge = _current.getShowFloorBadgeForWidth(_editingWidth);
    final bool showPostTime = _current.getShowPostTimeForWidth(_editingWidth);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F5),
        border: Border(bottom: BorderSide(color: Colors.brown.shade200, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showFloorBadge)
            const Text(
              '— 第一章 · 楼主 —',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF44403C), letterSpacing: 2),
            ),
          if (showUsername || showPostTime) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showUsername)
                  const Text('著者: 墨客', style: TextStyle(fontSize: 10, color: Color(0xFF78716C))),
                if (showUsername && showPostTime) const SizedBox(width: 8),
                if (showPostTime)
                  const Text('2026-10-14', style: TextStyle(fontSize: 10, color: Color(0xFF78716C))),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '这是典雅书卷排版架构：去除干扰读者的非文本构件，以章节名形式呈现楼层，搭配柔和书籍底色与典雅版心，提供纯粹沉浸的纸质书籍阅读质感。',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 13,
              height: 1.85,
              color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomCoreMock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF192D50), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF192D50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('自定义核心: ${_current.layoutMode}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text('通用结构化容器', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '此排版属于新扩展的核心架构 (${_current.layoutMode})。系统已自动生成包含头像、作者名、楼层、时间的结构化 DOM 容器。您可在下方自定义 CSS 框中添加针对此模式的专属样式。',
            style: TextStyle(
              fontSize: 12,
              height: _current.postLineHeight,
              color: Color(int.parse(_current.postTextColor.replaceFirst('#', '0xFF'))),
            ),
          ),
        ],
      ),
    );
  }
}
