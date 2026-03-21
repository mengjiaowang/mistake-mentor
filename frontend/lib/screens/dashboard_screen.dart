import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../models/question_model.dart';
import '../services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_screen.dart';
import 'recycle_bin_screen.dart';
import 'package:flutter_math_fork/flutter_math.dart'; // 导入公式渲染包

// ==========================================
// 自定义混合文本渲染控件 (支持行内 $...$ 公式)
// ==========================================
class MathText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const MathText(this.text, {this.style, Key? key}) : super(key: key);

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
      final data = await apiService.fetchQuestions(tag: fetchTag);
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MistakeMentor - 错题笔记本'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '回收站',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const RecycleBinScreen())
              ).then((_) => _loadData()); // 返回后自动重载列表
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
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
      ),
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

  Widget _buildCard(QuestionModel item) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showDetailModal(item),
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
                  ),
                ],
              ),
            )
          ],
        ),
      ),
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📝 题目正文：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                MathText(item.questionText, style: const TextStyle(fontSize: 16)),
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
                if (item.similarQuestion != null)
                   MathText(item.similarQuestion!['question_text'] ?? '暂无')
                else
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
      padding: const EdgeInsets.only(top: 8, bottom: 4),
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
