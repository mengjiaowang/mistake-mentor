import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';

class StatisticsScreen extends StatefulWidget {
  final ValueNotifier<bool>? refreshNotifier;
  
  const StatisticsScreen({this.refreshNotifier, Key? key}) : super(key: key);

  @override
  _StatisticsScreenState createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _statsData;
  String _timeRange = 'all'; // 'all', '7days', '30days', 'custom'
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadStats();
    widget.refreshNotifier?.addListener(_loadStats);
  }
  
  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      String? startStr;
      String? endStr;

      if (_timeRange == '7days') {
        final now = DateTime.now();
        startStr = now.subtract(const Duration(days: 6)).toIso8601String().split('T')[0];
        endStr = now.toIso8601String().split('T')[0];
      } else if (_timeRange == '30days') {
        final now = DateTime.now();
        startStr = now.subtract(const Duration(days: 29)).toIso8601String().split('T')[0];
        endStr = now.toIso8601String().split('T')[0];
      } else if (_timeRange == 'custom') {
        final sDate = _startDate; // 局部快照防竞跑
        final eDate = _endDate;
        if (sDate != null && eDate != null) {
          startStr = sDate.toIso8601String().split('T')[0];
          endStr = eDate.toIso8601String().split('T')[0];
        }
      }

      final stats = await apiService.fetchStatistics(startDate: startStr, endDate: endStr);
      setState(() {
        _statsData = stats;
        _isLoading = false;
      });
    } catch (e) {
      print("Failed to load statistics: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('数据看板')),
        body: Center(child: SpinKitFadingCircle(color: Theme.of(context).primaryColor, size: 50))
      );
    }

    if (_statsData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('数据看板')),
        body: const Center(child: Text('未能拉取统计数据'))
      );
    }

    final overview = _statsData!["overview"];
    final subjects = _statsData!["subjects"] as Map<String, dynamic>;
    final trends = _statsData!["trends"] as List<dynamic>;

    // Setup colors
    final masteredColor = Colors.green;
    final blurryColor = Colors.orange;
    final unmasteredColor = Colors.red;
    final unreviewedColor = Colors.grey;

    return Scaffold(
      appBar: AppBar(title: const Text('智能数据看板')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('全部', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('最近7天', '7days'),
                  const SizedBox(width: 8),
                  _buildFilterChip('最近30天', '30days'),
                  const SizedBox(width: 8),
                  _buildFilterChip('自定义', 'custom'),
                  if (_timeRange == 'custom' && _startDate != null && _endDate != null) ...[
                    const SizedBox(width: 8),
                    Text('${_startDate!.toString().substring(5,10)} 至 ${_endDate!.toString().substring(5,10)}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('🔥 全局进度比', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                   height: 200,
                   child: Row(
                     children: [
                       Expanded(
                         child: overview['total'] == 0 ? const Center(child: Text('暂无数据')) : PieChart(
                           PieChartData(
                             sectionsSpace: 2,
                             centerSpaceRadius: 40,
                             sections: [
                               if ((overview['mastered'] ?? 0) > 0)
                                 PieChartSectionData(color: masteredColor, value: overview['mastered'].toDouble(), title: '${overview['mastered']}', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                               if ((overview['blurry'] ?? 0) > 0)
                                 PieChartSectionData(color: blurryColor, value: overview['blurry'].toDouble(), title: '${overview['blurry']}', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                               if ((overview['unmastered'] ?? 0) > 0)
                                 PieChartSectionData(color: unmasteredColor, value: overview['unmastered'].toDouble(), title: '${overview['unmastered']}', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                               if ((overview['unreviewed'] ?? 0) > 0)
                                 PieChartSectionData(color: unreviewedColor, value: overview['unreviewed'].toDouble(), title: '${overview['unreviewed']}', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                             ]
                           )
                         ),
                       ),
                       Column(
                         mainAxisAlignment: MainAxisAlignment.center,
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           _buildLegendItem('完全掌握', masteredColor, overview['mastered'] ?? 0),
                           _buildLegendItem('仍然模糊', blurryColor, overview['blurry'] ?? 0),
                           _buildLegendItem('未掌握', unmasteredColor, overview['unmastered'] ?? 0),
                           _buildLegendItem('待复习', unreviewedColor, overview['unreviewed'] ?? 0),
                         ],
                       )
                     ],
                   )
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text('📈 勤奋度折线图', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.only(top: 30.0, right: 30, left: 20, bottom: 20),
                child: SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (touchedSpot) => Colors.blueGrey[900]?.withOpacity(0.9) ?? Colors.black87,
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              return LineTooltipItem(
                                '${spot.y.toInt()} 次',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= 0 && value.toInt() < trends.length) {
                                String dateStr = trends[value.toInt()]['date'];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(dateStr.substring(5), style: const TextStyle(fontSize: 10)),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: trends.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value['count'].toDouble())).toList(),
                          isCurved: true,
                          color: Theme.of(context).primaryColor,
                          barWidth: 4,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Theme.of(context).primaryColor.withOpacity(0.2),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ),
            ),
            
            const SizedBox(height: 32),
            const Text('📚 各科攻坚战况', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.only(top: 30, bottom: 20, left: 10, right: 10),
                child: SizedBox(
                  height: 250,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => Colors.blueGrey[900]?.withOpacity(0.9) ?? Colors.black87,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            // Extract values from stack items
                            final items = rod.rodStackItems;
                            if (items.length >= 3) {
                              final unmastered = items[0].toY - items[0].fromY;
                              final blurry = items[1].toY - items[1].fromY;
                              final mastered = items[2].toY - items[2].fromY;
                              return BarTooltipItem(
                                '未掌握: ${unmastered.toInt()}\n模糊: ${blurry.toInt()}\n完全掌握: ${mastered.toInt()}',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            }
                            return BarTooltipItem('${rod.toY.toInt()}', const TextStyle(color: Colors.white));
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final keys = subjects.keys.toList();
                              if (value.toInt() >= 0 && value.toInt() < keys.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(keys[value.toInt()], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: subjects.entries.toList().asMap().entries.map((entry) {
                        int i = entry.key;
                        var counts = entry.value.value;
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: (counts['mastered'] + counts['blurry'] + counts['unmastered']).toDouble(),
                              rodStackItems: [
                                BarChartRodStackItem(0, counts['unmastered'].toDouble(), unmasteredColor),
                                BarChartRodStackItem(counts['unmastered'].toDouble(), (counts['unmastered'] + counts['blurry']).toDouble(), blurryColor),
                                BarChartRodStackItem((counts['unmastered'] + counts['blurry']).toDouble(), (counts['mastered'] + counts['blurry'] + counts['unmastered']).toDouble(), masteredColor),
                              ],
                              width: 30,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                )
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label ($count)'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    bool isSelected = _timeRange == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          if (value == 'custom') {
            _selectCustomDateRange();
          } else {
            setState(() {
              _timeRange = value;
              _startDate = null;
              _endDate = null;
            });
            _loadStats();
          }
        }
      },
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      backgroundColor: Colors.grey[200],
      labelStyle: TextStyle(
        color: isSelected ? Theme.of(context).primaryColor : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
      ),
    );
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
    );
    if (picked != null) {
      setState(() {
        _timeRange = 'custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadStats();
    }
  }
}
