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
      final stats = await apiService.fetchStatistics();
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
                      barTouchData: BarTouchData(enabled: false),
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
}
