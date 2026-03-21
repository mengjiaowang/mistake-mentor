import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../models/question_model.dart';
import '../services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({Key? key}) : super(key: key);

  @override
  _RecycleBinScreenState createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<QuestionModel> _deletedQuestions = [];
  bool _isLoading = true;
  bool _isSelectionMode = false; // 新增：是否开启管理多选模式
  final Set<String> _selectedQuestionIds = {}; // 新增：选中项 ID 集合

  @override
  void initState() {
    super.initState();
    _loadDeletedItems();
  }

  Future<void> _loadDeletedItems() async {
    setState(() => _isLoading = true);
    final data = await apiService.fetchQuestions(isDeleted: true);
    
    // 按时间降序排序 (后上传的排在前面)
    data.sort((a, b) {
      try {
        final dtA = DateTime.parse(a.createdAt);
        final dtB = DateTime.parse(b.createdAt);
        return dtB.compareTo(dtA);
      } catch (_) {
        return 0;
      }
    });

    setState(() {
      _deletedQuestions = data;
      _isLoading = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        actions: [
          if (_deletedQuestions.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  _isSelectionMode = !_isSelectionMode;
                  if (!_isSelectionMode) {
                    _selectedQuestionIds.clear();
                  }
                });
              },
              child: Text(
                _isSelectionMode ? '取消' : '管理',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          if (_isSelectionMode)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedQuestionIds.length == _deletedQuestions.length) {
                    _selectedQuestionIds.clear();
                  } else {
                    _selectedQuestionIds.addAll(_deletedQuestions.map((e) => e.id));
                  }
                });
              },
              child: Text(
                _selectedQuestionIds.length == _deletedQuestions.length ? '全不选' : '全选',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: SpinKitFadingCircle(color: Colors.indigo, size: 50))
          : _deletedQuestions.isEmpty
              ? const Center(child: Text('回收站空空如也~', style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _deletedQuestions.length,
                  itemBuilder: (context, index) {
                    final item = _deletedQuestions[index];
                    final isSelected = _selectedQuestionIds.contains(item.id);

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
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
                            : null,
                        leading: _isSelectionMode
                            ? Checkbox(
                                value: isSelected,
                                activeColor: Colors.red,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedQuestionIds.add(item.id);
                                    } else {
                                      _selectedQuestionIds.remove(item.id);
                                    }
                                  });
                                },
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: item.imageOriginal.startsWith('/') 
                                      ? '${ApiService.baseUrl}${item.imageOriginal}' 
                                      : item.imageOriginal,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const SpinKitWave(color: Colors.indigo, size: 10),
                                  errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported),
                                ),
                              ),
                        title: Text(
                          item.knowledgePoint.isNotEmpty ? item.knowledgePoint : '未知考点',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(item.questionText, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: _isSelectionMode
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.restore_from_trash, color: Colors.green),
                                    tooltip: '恢复',
                                    onPressed: () => _restoreItem(item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                                    tooltip: '永久删除',
                                    onPressed: () => _confirmPermanentDelete(item),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _isSelectionMode && _selectedQuestionIds.isNotEmpty
          ? BottomAppBar(
              height: 65,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('已选择 ${_selectedQuestionIds.length} 项', style: const TextStyle(fontWeight: FontWeight.bold)),
                   Row(
                     children: [
                       TextButton.icon(
                         icon: const Icon(Icons.restore_from_trash, color: Colors.green),
                         label: const Text('批量恢复', style: TextStyle(color: Colors.green)),
                         onPressed: _batchRestore,
                       ),
                       const SizedBox(width: 8),
                       ElevatedButton.icon(
                         style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red, elevation: 0),
                         icon: const Icon(Icons.delete_forever),
                         label: const Text('批量粉碎'),
                         onPressed: _confirmBatchPermanentDelete,
                       ),
                     ],
                   )
                ],
              ),
            )
          : null,
    );
  }

  Future<void> _batchRestore() async {
    final ids = _selectedQuestionIds.toList();
    final ok = await apiService.batchRestoreQuestions(ids);
    if (ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功恢复 ${ids.length} 道错题到错题本！')));
      }
      setState(() {
        _isSelectionMode = false;
        _selectedQuestionIds.clear();
      });
      _loadDeletedItems(); // 刷新回收站
    }
  }

  Future<void> _confirmBatchPermanentDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 批量永久粉碎警告'),
        content: Text('确定要永久删除选中的 ${_selectedQuestionIds.length} 道错题吗？该操作不可逆！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定粉碎'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ids = _selectedQuestionIds.toList();
      final ok = await apiService.batchPermanentDeleteQuestions(ids);
      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已成功永久粉碎 ${ids.length} 道错题！')));
        }
        setState(() {
          _isSelectionMode = false;
          _selectedQuestionIds.clear();
        });
        _loadDeletedItems(); // 刷新回收站
      }
    }
  }

  Future<void> _restoreItem(QuestionModel item) async {
    final ok = await apiService.restoreQuestion(item.id);
    if (ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('错题已成功恢复至错题本！')));
      }
      _loadDeletedItems(); // 刷新回收站
    }
  }

  Future<void> _confirmPermanentDelete(QuestionModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 永久粉碎警告'),
        content: const Text('确定要从云端删除此错题吗？该操作不可逆，粉碎后无法找回！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定粉碎'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await apiService.permanentDeleteQuestion(item.id);
      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('错题已永久粉碎！')));
        }
        _loadDeletedItems(); // 刷新回收站
      }
    }
  }
}
