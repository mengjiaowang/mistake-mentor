import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../models/question_model.dart';
import '../services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart';
import 'recycle_bin_screen.dart';
import 'package:flutter_math_fork/flutter_math.dart'; // 导入公式渲染包
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// 自定义混合文本渲染控件 (支持行内 $...$ 公式)
// ==========================================
class MathText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines; // 新增
  final TextOverflow? overflow; // 新增

  const MathText(this.text, {this.style, this.maxLines, this.overflow, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    // 正则切分 $...$ 公式样式
    final RegExp regExp = RegExp(r'\$(.*?)\$');
    final List<String> parts = text.split(regExp);
    final Iterable<RegExpMatch> matches = regExp.allMatches(text);

    List<InlineSpan> spans = [];
    int matchIndex = 0;

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(TextSpan(text: parts[i], style: style));
      }
      if (matchIndex < matches.length) {
        final formula = matches.elementAt(matchIndex).group(1) ?? '';
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Math.tex(
              formula,
              textStyle: style?.copyWith(fontWeight: FontWeight.normal) ?? const TextStyle(fontSize: 16),
            ),
          ),
        ));
        matchIndex++;
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines, // 新增
      overflow: overflow, // 新增
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final ValueNotifier<bool>? refreshNotifier; // 新增：刷新信号源

  const DashboardScreen({this.refreshNotifier, Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<QuestionModel> _questions = [];
  bool _isLoading = true;
  
  // 新增科目过滤状态
  List<String> _allTags = ["全部"];
  String _selectedTag = "全部";

  // --- 新增：试卷导出与多选状态 ---
  bool _isSelectionMode = false;
  final Set<String> _selectedQuestionIds = {};
  DateTimeRange? _selectedDateRange = null;

  @override
  void initState() {
    super.initState();
    _loadData();
    widget.refreshNotifier?.addListener(_loadData); // 添加流监听
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadData); // 销毁监听
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 同时拉取标签列表
      final tags = await apiService.fetchTags();
      
      // 拉法支持过滤项
      final fetchTag = _selectedTag == '全部' ? null : _selectedTag;
      List<QuestionModel> data = await apiService.fetchQuestions(tag: fetchTag);
      
      // 时间跨度本地过滤
      if (_selectedDateRange != null) {
        data = data.where((q) {
          try {
            final ct = DateTime.parse(q.createdAt);
            final start = _selectedDateRange!.start;
            // 截至时间设置为当天 23:59:59 确保全天覆盖
            final end = _selectedDateRange!.end.add(const Duration(days: 1)); 
            return ct.isAfter(start) && ct.isBefore(end);
          } catch (_) {
            return true;
          }
        }).toList();
      }

      setState(() {
         _allTags = ["全部", ...tags];
         _questions = data;
         _isLoading = false;
      });
    } catch (e) {
      print('Load dashboard error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _exportPaper() async {
    if (_selectedQuestionIds.isEmpty) return;
    final ids = _selectedQuestionIds.join(',');
    
    bool? includeAnswers = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('试卷生成选项'),
        content: const Text('是否在新标签页生成的试卷中，一并渲染 “参考答案与解析”？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('仅出题目')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('附带答案详解')),
        ],
      ),
    );

    if (includeAnswers == null) return;

    // 1. 获取一次性免密安全票据
    final ticketId = await apiService.createPaperTicket(ids, includeAnswers);
    if (ticketId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('生成打印凭证失败，请重试')));
      return;
    }

    // 2. 使用票据打开新页面
    final url = '${ApiService.baseUrl}/api/v1/questions/paper/export?ticket_id=$ticketId';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开试卷导出页面')));
    }

    setState(() {
      _isSelectionMode = false;
      _selectedQuestionIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('王铮的错题本'), // 已更新
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新列表',
            onPressed: _loadData,
          ),
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: '生成试卷并打印',
              onPressed: () => setState(() => _isSelectionMode = true),
            ),
          if (_isSelectionMode)
            TextButton(
              onPressed: () => setState(() {
                _isSelectionMode = false;
                _selectedQuestionIds.clear();
              }),
              child: const Text('取消选择', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          if (!_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '回收站',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const RecycleBinScreen())
                ).then((_) => _loadData());
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '登出',
              onPressed: () async {
                const storage = FlutterSecureStorage();
                await storage.delete(key: 'jwt_token');
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ],
      ),
      bottomNavigationBar: _isSelectionMode && _selectedQuestionIds.isNotEmpty
          ? BottomAppBar(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('已选择 ${_selectedQuestionIds.length} 道错题', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   ElevatedButton.icon(
                     style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
                     icon: const Icon(Icons.picture_as_pdf),
                     label: const Text('预览 A/B 试卷视图'),
                     onPressed: _exportPaper,
                   ),
                ],
              ),
            )
          : null,
      body: _isLoading
          ? const Center(
              child: SpinKitFadingCircle(color: Colors.indigo, size: 50),
            )
          : Column(
              children: [
                _buildFilterBar(), // 新增：排版过滤 Chips 状态栏
                Expanded(
                  child: _questions.isEmpty
                      ? const Center(child: Text('暂无相关错题，快去拍照录入吧！'))
                      : Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, // 适合平板
                              childAspectRatio: 3 / 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _questions.length,
                            itemBuilder: (context, index) {
                              final item = _questions[index];
                              return _buildCard(item);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  String _formatTimestamp(String ts) {
    if (ts.isEmpty) return '未知';
    try {
      final dt = DateTime.parse(ts).toLocal(); 
      final date = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
      final time = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
      return '$date $time';
    } catch (e) {
      if (ts.contains('T')) {
        final parts = ts.split('T');
        final date = parts[0];
        final time = parts[1].split('.').first;
        return '$date $time';
      }
      return ts;
    }
  }

  Widget _buildCard(QuestionModel item) {
    bool isSelected = _selectedQuestionIds.contains(item.id);

    return Stack(
      children: [
        Card(
          elevation: isSelected ? 8 : 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected ? const BorderSide(color: Colors.indigo, width: 2) : BorderSide.none,
          ),
          child: InkWell(
            onTap: _isSelectionMode
                ? () {
                    setState(() {
                      if (isSelected) {
                        _selectedQuestionIds.remove(item.id);
                      } else {
                        _selectedQuestionIds.add(item.id);
                      }
                    });
                  }
                : () => _showDetailModal(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: CachedNetworkImage(
                      imageUrl: item.imageBlank.startsWith('/') 
                          ? '${ApiService.baseUrl}${item.imageBlank}' 
                          : (item.imageBlank.isNotEmpty ? item.imageBlank : item.imageOriginal),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(child: SpinKitWave(color: Colors.indigo, size: 20)),
                      errorWidget: (context, url, error) => Container(color: Colors.grey[200], child: const Icon(Icons.image_not_supported)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.knowledgePoint,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                      const SizedBox(height: 4),
                      if (item.tags.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: item.tags.map((tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getTagColor(tag).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _getTagColor(tag).withOpacity(0.5), width: 0.5),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(fontSize: 10, color: _getTagColor(tag), fontWeight: FontWeight.bold),
                            ),
                          )).toList(),
                        ),
                      const SizedBox(height: 4),
                      MathText(
                        item.questionText,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatTimestamp(item.createdAt).split(' ').first,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
        if (_isSelectionMode)
          Positioned(
            top: 4,
            right: 4,
            child: Checkbox(
              value: isSelected,
              activeColor: Colors.indigo,
              checkColor: Colors.white,
              shape: const CircleBorder(),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedQuestionIds.add(item.id);
                  } else {
                    _selectedQuestionIds.remove(item.id);
                  }
                });
              },
            ),
          ),
      ],
    );
  }

  void _showDetailModal(QuestionModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 固定头部 (关闭按钮 + 标题)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📌 题目详情', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.indigo)),
                        const SizedBox(height: 4),
                        Text('录入时间: ${_formatTimestamp(item.createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const Divider(height: 16),
              
              // 2. 可滚动的主体内容
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📝 题目正文：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 8),
                      MathText(item.questionText, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 12),
                      if (item.imageOriginal.isNotEmpty) ...[
                        const Text('🖼️ 题目原图：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: '${ApiService.baseUrl}${item.imageOriginal}',
                            width: double.infinity,
                            fit: BoxFit.contain, // 详情使用 contain 完整查看
                            placeholder: (context, url) => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 40),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Divider(height: 20),
                      
                      const Text('🏷️ 所属科目/标签：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                      const SizedBox(height: 8),
                      StatefulBuilder(  // 局部刷新标签勾选状态
                        builder: (context, setModalState) {
                          return Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              ...item.tags.map((tag) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getTagColor(tag).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _getTagColor(tag).withOpacity(0.5)),
                                ),
                                child: Text(tag, style: TextStyle(color: _getTagColor(tag), fontSize: 13, fontWeight: FontWeight.bold)),
                              )),
                              ActionChip(
                                label: const Text('+ 管理科目', style: TextStyle(fontSize: 12)),
                                backgroundColor: Colors.grey[100],
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onPressed: () => _showTagSelectionDialog(context, item, setModalState),
                              ),
                            ],
                          );
                        }
                      ),
                      const Divider(height: 30),
                      
                      const Text('🔍 AI 详解与步骤：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                      const SizedBox(height: 8),
                      if (item.analysisSteps.isEmpty) const Text('暂无解析'),
                      ...item.analysisSteps.map((step) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: MathText('• $step', style: const TextStyle(height: 1.4, fontSize: 15)),
                          )),
                      const Divider(height: 30),

                      const Text('💡 易错点警示：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange)),
                      const SizedBox(height: 8),
                      MathText(item.trapWarning.isNotEmpty ? item.trapWarning : '暂无', style: const TextStyle(fontStyle: FontStyle.italic)),
                      const Divider(height: 30),

                      const Text('🧠 举一反三变式题：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.purple)),
                      const SizedBox(height: 8),
                      if (item.similarQuestion != null) ...[
                         MathText(item.similarQuestion!['question_text'] ?? '暂无'),
                         if (item.similarQuestion!['answer'] != null && item.similarQuestion!['answer'].toString().isNotEmpty) ...[
                           const SizedBox(height: 12),
                           const Text('✅ 参考答案：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                           const SizedBox(height: 4),
                           MathText(item.similarQuestion!['answer'].toString()),
                         ],
                         if (item.similarQuestion!['analysis'] != null && item.similarQuestion!['analysis'].toString().isNotEmpty) ...[
                           const SizedBox(height: 12),
                           const Text('📝 解析过程：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                           const SizedBox(height: 4),
                           MathText(item.similarQuestion!['analysis'].toString()),
                         ],
                      ] else
                         const Text('生成中...'),
                      const Divider(height: 30),

                      // ==========================================
                      // 底部删除行动项
                      // ==========================================
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[50], // 淡红背景
                            foregroundColor: Colors.red,
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('移入回收站'),
                          onPressed: () async {
                            final ok = await apiService.deleteQuestion(item.id);
                            if (ok) {
                              if (mounted) Navigator.pop(context); // 关闭详情底栏
                              _loadData(); // 重新拉取
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getTagColor(String tag) {
    const Map<String, Color> colorMap = {
      '语文': Colors.red,
      '数学': Colors.blue,
      '英语': Colors.green,
    };
    return colorMap[tag] ?? Colors.indigo; 
  }

  Widget _buildFilterBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(top: 8, bottom: 4, right: 8),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _allTags.length,
              itemBuilder: (context, index) {
                final tag = _allTags[index];
                final isSelected = tag == _selectedTag;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    selectedColor: _getTagColor(tag).withOpacity(0.1),
                    checkmarkColor: _getTagColor(tag),
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? _getTagColor(tag) : Colors.grey[300]!),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? _getTagColor(tag) : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _selectedTag = tag;
                        _loadData(); // 重新按标拉取
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          IconButton(
            icon: Icon(
              _selectedDateRange != null ? Icons.today_rounded : Icons.calendar_month_outlined,
              color: _selectedDateRange != null ? Colors.indigo : Colors.grey[600],
            ),
            tooltip: '按入库时间筛选',
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2025),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: _selectedDateRange,
              );
              if (range != null) {
                setState(() {
                  _selectedDateRange = range;
                  _loadData(); // 触发本地时间过滤
                });
              }
            },
          ),
          if (_selectedDateRange != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.grey),
              tooltip: '清空时间',
              onPressed: () {
                setState(() {
                  _selectedDateRange = null;
                  _loadData();
                });
              },
            ),
        ],
      ),
    );
  }

  void _showTagSelectionDialog(BuildContext context, QuestionModel item, StateSetter setModalState) {
    final currentTags = List<String>.from(item.tags);
    final availableTags = List<String>.from(_allTags)..remove("全部");

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('管理所属科目'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('选择科目 (支持多选)：', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: availableTags.map((tag) {
                        final isSelected = currentTags.contains(tag);
                        return FilterChip(
                          label: Text(tag),
                          selected: isSelected,
                          selectedColor: _getTagColor(tag).withOpacity(0.1),
                          checkmarkColor: _getTagColor(tag),
                          labelStyle: TextStyle(color: isSelected ? _getTagColor(tag) : Colors.black87),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                currentTags.add(tag);
                              } else {
                                currentTags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const Divider(height: 30),
                    TextButton.icon(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      label: const Text('新增自定义科目类别'),
                      onPressed: () => _showAddTagSubDialog(context, availableTags, currentTags, setDialogState),
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                TextButton(
                  onPressed: () async {
                    final ok = await apiService.updateQuestionTags(item.id, currentTags);
                    if (ok) {
                      setModalState(() {
                        item.tags.clear();
                        item.tags.addAll(currentTags);
                      });
                      if (context.mounted) Navigator.pop(context); // 关闭详情底栏
                      _loadData(); // 全局刷新
                    }
                  },
                  child: const Text('保存确认', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showAddTagSubDialog(BuildContext context, List<String> availableTags, List<String> currentTags, StateSetter setDialogState) {
     final controller = TextEditingController();
     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text('新增科目'),
         content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '如：物理、政治、错题A集')),
         actions: [
           TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
           TextButton(
             onPressed: () async {
               final name = controller.text.trim();
               if (name.isNotEmpty) {
                  await apiService.addTag(name);
                  setDialogState(() {
                      availableTags.add(name);
                      currentTags.add(name);
                  });
                  if (context.mounted) Navigator.pop(context); // 关闭二级
               }
             },
             child: const Text('添加'),
           ),
         ],
       )
     );
  }
}