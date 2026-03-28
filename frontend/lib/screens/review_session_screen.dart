import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/question_model.dart';
import '../services/api_service.dart';
import 'dashboard_screen.dart'; // Using the MathText from here

class ReviewSessionScreen extends StatefulWidget {
  final ValueNotifier<bool>? refreshNotifier;

  const ReviewSessionScreen({this.refreshNotifier, Key? key}) : super(key: key);

  @override
  _ReviewSessionScreenState createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  bool _isLoading = true;
  bool _showAnswer = false;
  bool _showOriginalImage = false;
  bool _showSimilarQuestion = false;
  bool _showSimilarAnalysis = false;
  bool _showSimilarAnswer = false;
  List<QuestionModel> _questions = [];
  int _currentIndex = 0;

  // 新增：科目配置状态
  bool _isConfiguring = true;
  List<String> _availableTags = [];
  List<String> _selectedSubjects = [];
  bool _isFreeMode = false;
  
  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final tags = await apiService.fetchTags();
      setState(() {
        _availableTags = tags;
        _isConfiguring = true; // 停留配置页
        _isLoading = false;
      });
    } catch (e) {
      print('Load tags error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBatch({bool isFree = false}) async {
    setState(() {
      _isLoading = true;
      _showAnswer = false;
      _showOriginalImage = false;
      _showSimilarQuestion = false;
      _showSimilarAnalysis = false;
      _showSimilarAnswer = false;
      _currentIndex = 0;
      _isFreeMode = isFree; // 状态模式下坠
      _isConfiguring = false; // 进入主页复习
    });
    
    try {
      final questions = isFree
          ? await apiService.fetchFreeBatch(_selectedSubjects)
          : await apiService.fetchReviewBatch(subjects: _selectedSubjects, limit: 15);
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading review batch: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('加载复习题库失败')));
      }
      setState(() => _isLoading = false);
    }
  }

  void _submitReview(String feedback) async {
    final currentQ = _questions[_currentIndex];
    
    // Optimistic UI update
    setState(() {
      if (_currentIndex < _questions.length - 1) {
        _currentIndex++;
        _showAnswer = false;
        _showOriginalImage = false;
        _showSimilarQuestion = false;
        _showSimilarAnalysis = false;
        _showSimilarAnswer = false;
      } else {
        _questions = [];
      }
    });

    try {
      await apiService.submitReview(currentQ.id, feedback);
      // Notify dashboard/home that data changed
      if (widget.refreshNotifier != null) {
        widget.refreshNotifier!.value = !widget.refreshNotifier!.value;
      }
    } catch (e) {
      print("Failed to submit review: $e");
    }
  }

  void _skipQuestion() {
    setState(() {
      if (_currentIndex < _questions.length - 1) {
        _currentIndex++;
        _showAnswer = false;
        _showOriginalImage = false;
        _showSimilarQuestion = false;
        _showSimilarAnalysis = false;
        _showSimilarAnswer = false;
      } else {
        _questions = []; // Finished batch
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: SpinKitFadingCircle(color: Theme.of(context).primaryColor, size: 50),
      );
    }

    if (_isConfiguring) {
      return _buildConfigView();
    }

    if (_questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            const Text('太棒了！今日复习任务已全部完成 🎉', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadBatch(isFree: _isFreeMode),
              icon: const Icon(Icons.refresh),
              label: const Text('按当前模式再来一组'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() => _isConfiguring = true),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回重选科目/模式'),
            )
          ],
        ),
      );
    }

    final item = _questions[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text('复习进度: ${_currentIndex + 1} / ${_questions.length}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_next_rounded),
            tooltip: '跳过此题',
            onPressed: _skipQuestion,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 卡片区域
            Expanded(
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 正面：题目
                      Center(
                        child: Text('题干', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey[500])),
                      ),
                      const Divider(),
                      if (item.imageBlank.isNotEmpty || item.imageOriginal.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _showOriginalImage = !_showOriginalImage),
                            icon: Icon(_showOriginalImage ? Icons.auto_fix_high : Icons.history, color: Theme.of(context).primaryColor, size: 16),
                            label: Text(_showOriginalImage ? '查看智能擦除' : '查看原图', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 13)),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ] else
                        const SizedBox(height: 16),
                      if (item.imageBlank.isNotEmpty || item.imageOriginal.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: _showOriginalImage
                                ? (item.imageOriginal.startsWith('/') ? '${ApiService.baseUrl}${item.imageOriginal}' : item.imageOriginal)
                                : (item.imageBlank.isNotEmpty 
                                    ? (item.imageBlank.startsWith('/') ? '${ApiService.baseUrl}${item.imageBlank}' : item.imageBlank)
                                    : (item.imageOriginal.startsWith('/') ? '${ApiService.baseUrl}${item.imageOriginal}' : item.imageOriginal)),
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 50),
                          ),
                        ),
                      const SizedBox(height: 16),
                      MathText(item.questionText, style: const TextStyle(fontSize: 18)),

                      // 背面：答案和解析
                      if (_showAnswer) ...[
                        const SizedBox(height: 30),
                        Center(
                          child: Text('详细解析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[600])),
                        ),
                        const Divider(color: Colors.green),
                        const SizedBox(height: 16),
                        Text('💡 考点: ${item.knowledgePoint}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ...item.analysisSteps.map((step) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: MathText('• $step', style: const TextStyle(fontSize: 16, height: 1.5)),
                            )),
                        if (item.trapWarning.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                const SizedBox(width: 8),
                                Expanded(child: MathText('易错警示：${item.trapWarning}', style: const TextStyle(color: Colors.deepOrange))),
                              ],
                            ),
                          )
                        ],
                        if (item.similarQuestion != null) ...[
                          const Divider(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('🧠 举一反三变式题', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
                              TextButton.icon(
                                onPressed: () => setState(() => _showSimilarQuestion = !_showSimilarQuestion),
                                icon: Icon(_showSimilarQuestion ? Icons.expand_less : Icons.expand_more, color: Colors.purple),
                                label: Text(_showSimilarQuestion ? '收起' : '查看变式题', style: const TextStyle(color: Colors.purple, fontSize: 13)),
                              ),
                            ],
                          ),
                          if (_showSimilarQuestion) ...[
                            const SizedBox(height: 8),
                            MathText(item.similarQuestion!['question_text'] ?? '暂无变式题内容'),
                            const SizedBox(height: 12),
                            if (item.similarQuestion!['analysis'] != null && item.similarQuestion!['analysis'].toString().isNotEmpty) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('📝 变式解析：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
                                  TextButton.icon(
                                    onPressed: () => setState(() => _showSimilarAnalysis = !_showSimilarAnalysis),
                                    icon: Icon(_showSimilarAnalysis ? Icons.expand_less : Icons.expand_more, color: Colors.blueGrey, size: 16),
                                    label: Text(_showSimilarAnalysis ? '隐藏' : '展开解析', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                                  ),
                                ],
                              ),
                              if (_showSimilarAnalysis) ...[
                                const SizedBox(height: 4),
                                MathText(item.similarQuestion!['analysis'].toString()),
                              ],
                              const SizedBox(height: 12),
                            ],
                            if (item.similarQuestion!['answer'] != null && item.similarQuestion!['answer'].toString().isNotEmpty) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('✅ 参考答案：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                                  TextButton.icon(
                                    onPressed: () => setState(() => _showSimilarAnswer = !_showSimilarAnswer),
                                    icon: Icon(_showSimilarAnswer ? Icons.expand_less : Icons.expand_more, color: Colors.green, size: 16),
                                    label: Text(_showSimilarAnswer ? '隐藏' : '展开答案', style: const TextStyle(color: Colors.green, fontSize: 12)),
                                  ),
                                ],
                              ),
                              if (_showSimilarAnswer) ...[
                                const SizedBox(height: 4),
                                MathText(item.similarQuestion!['answer'].toString()),
                              ],
                            ],
                          ],
                        ]
                      ],
                      const Divider(height: 30),
                      const Text('🕒 复习历史轨迹：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.add_circle_outline, color: Colors.blue, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_formatTimestamp(item.createdAt), style: const TextStyle(fontSize: 14))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                              child: const Text('录入题目', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      if (item.reviewHistory != null && item.reviewHistory!.isNotEmpty)
                        ...item.reviewHistory!.map((entry) {
                          final ts = entry['timestamp'] ?? '';
                          final feedback = entry['feedback'] ?? '未知';
                          Color feedbackColor = Colors.grey;
                          String feedbackName = '未知';
                          if (feedback == 'mastered') { feedbackColor = Colors.green; feedbackName = '完全掌握'; }
                          else if (feedback == 'blurry') { feedbackColor = Colors.orange; feedbackName = '仍然模糊'; }
                          else if (feedback == 'unmastered') { feedbackColor = Colors.red; feedbackName = '完全忘记'; }
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.history, color: feedbackColor, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_formatTimestamp(ts), style: const TextStyle(fontSize: 14))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: feedbackColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                  child: Text(feedbackName, style: TextStyle(color: feedbackColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 底部操作区
            if (!_showAnswer)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: () => setState(() => _showAnswer = true),
                  child: const Text('思考完毕，查看答案', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                   _buildFeedbackButton('完全忘记', Icons.sentiment_very_dissatisfied, Colors.red, () => _submitReview('unmastered')),
                   _buildFeedbackButton('仍然模糊', Icons.sentiment_neutral, Colors.orange, () => _submitReview('blurry')),
                   _buildFeedbackButton('完全掌握', Icons.sentiment_very_satisfied, Colors.green, () => _submitReview('mastered')),
                ],
              )
          ],
        ),
      ),
    );
  }

  Widget _buildConfigView() {
    return Scaffold(
      appBar: AppBar(title: const Text('科目与模式配置'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📚 请选择要复习的科目（多选）', 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).primaryColor)),
            const SizedBox(height: 16),
            if (_availableTags.isEmpty)
              const Text('暂无可用科目标签，请先去首页录入题目并打标。', style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _availableTags.map((tag) {
                  final isSelected = _selectedSubjects.contains(tag);
                  return FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSubjects.add(tag);
                        } else {
                          _selectedSubjects.remove(tag);
                        }
                      });
                    },
                    selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                    checkmarkColor: Theme.of(context).primaryColor,
                  );
                }).toList(),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.psychology),
                label: const Text('开启智能复习 (各科目最多15道)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _loadBatch(isFree: false),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flash_on),
                label: const Text('开启自由刷题 (无限制)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                ),
                onPressed: () => _loadBatch(isFree: true),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackButton(String text, IconData icon, MaterialColor color, VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: color[50],
            foregroundColor: color[800],
            padding: const EdgeInsets.all(20),
            elevation: 0,
          ),
          onPressed: onPressed,
          child: Icon(icon, size: 36),
        ),
        const SizedBox(height: 8),
        Text(text, style: TextStyle(color: color[800], fontWeight: FontWeight.bold, fontSize: 13)),
      ],
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
}
