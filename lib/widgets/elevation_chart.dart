import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ElevationChart extends StatelessWidget {
  final List<FlSpot> elevationPoints;
  final double? maxElevation;
  final double? minElevation;
  final Function(FlSpot)? onHover;
  final FlSpot? hoveredSpot;

  const ElevationChart({
    super.key,
    required this.elevationPoints,
    this.maxElevation,
    this.minElevation,
    this.onHover,
    this.hoveredSpot,
  });

  @override
  Widget build(BuildContext context) {
    if (elevationPoints.isEmpty) {
      return const Center(child: Text('No elevation data available'));
    }

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          enabled: true,
          touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
            if (event is FlPointerHoverEvent && touchResponse?.lineBarSpots != null) {
              final spot = touchResponse!.lineBarSpots![0].spotIndex;
              if (spot < elevationPoints.length) {
                onHover?.call(elevationPoints[spot]);
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueAccent,
            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
              return touchedBarSpots.map((barSpot) {
                return LineTooltipItem(
                  '${barSpot.y.toStringAsFixed(1)}m\n${barSpot.x.toStringAsFixed(1)}km',
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
                return Text('${value.toStringAsFixed(0)}m');
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
            spots: elevationPoints,
            isCurved: true,
            color: Colors.blue,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withOpacity(0.2),
            ),
          ),
        ],
        minY: minElevation,
        maxY: maxElevation,
      ),
    );
  }
} 