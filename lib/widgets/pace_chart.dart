import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class PaceChart extends StatelessWidget {
  final List<FlSpot> pacePoints;
  final double minPace;
  final double maxPace;
  final Function(FlSpot)? onHover;
  final FlSpot? hoveredSpot;

  const PaceChart({
    super.key,
    required this.pacePoints,
    required this.minPace,
    required this.maxPace,
    this.onHover,
    this.hoveredSpot,
  });

  String formatPace(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (pacePoints.isEmpty) {
      return const Center(child: Text('No pace data available'));
    }

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          enabled: true,
          touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
            if (event is FlPointerHoverEvent && touchResponse?.lineBarSpots != null) {
              final spot = touchResponse!.lineBarSpots![0].spotIndex;
              if (spot < pacePoints.length) {
                onHover?.call(pacePoints[spot]);
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueAccent,
            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
              return touchedBarSpots.map((barSpot) {
                return LineTooltipItem(
                  '${formatPace(barSpot.y)}/km\n${barSpot.x.toStringAsFixed(1)}km',
                  const TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Text('${value.toStringAsFixed(1)}km');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(formatPace(value));
              },
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: pacePoints,
            isCurved: true,
            color: Colors.green,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withOpacity(0.2),
            ),
          ),
        ],
        minY: minPace,
        maxY: maxPace,
      ),
    );
  }
} 