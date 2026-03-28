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
  List<QuestionModel> _questions = [];
  int _currentIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _loadBatch();
  }

  Future<void> _loadBatch() async {
    setState(() {
      _isLoading = true;
      _showAnswer = false;
      _showOriginalImage = false;
      _currentIndex = 0;
    });
    
    try {
      final questions = await apiService.fetchReviewBatch(limit: 15);
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
              onPressed: _loadBatch,
              icon: const Icon(Icons.refresh),
              label: const Text('再来一组'),
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
