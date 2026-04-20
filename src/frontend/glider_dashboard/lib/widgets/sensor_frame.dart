import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart'; // 추가됨
import '../providers/glider_provider.dart';
import '../providers/archive_glider_provider.dart';
import '../models/sensor_data.dart';
import '../utils/chart_formatter.dart';

class SensorFrame extends StatefulWidget {
  final bool isArchiveMode;
  const SensorFrame({Key? key, this.isArchiveMode = false}) : super(key: key);

  @override
  State<SensorFrame> createState() => _SensorFrameState();
}

class _SensorFrameState extends State<SensorFrame> {
  // false: 기본 모드 (X: 센서값, Y: 수심) - 과거/현재 모두 비교
  // true: Colormap 모드 (X: 시간, Y: 수심, Color: 센서값) - 가장 최근 1yo 시계열
  bool _showTimeDepthScatter = false;

  Color _getJetColor(double value, double min, double max) {
    if (max <= min) return Colors.green;
    double v = ((value - min) / (max - min)).clamp(0.0, 1.0);
    double r = (-4.0 * (v - 0.75).abs() + 1.5).clamp(0.0, 1.0);
    double g = (-4.0 * (v - 0.50).abs() + 1.5).clamp(0.0, 1.0);
    double b = (-4.0 * (v - 0.25).abs() + 1.5).clamp(0.0, 1.0);
    return Color.fromRGBO(
      (r * 255).toInt(),
      (g * 255).toInt(),
      (b * 255).toInt(),
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dynamic provider = widget.isArchiveMode 
        ? context.watch<ArchiveGliderProvider>() 
        : context.watch<GliderProvider>();
    final sensorData = provider.sensorData;

    if (provider.isLoading) {
      return const Card(
        margin: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (sensorData == null || sensorData.sciData.isEmpty) {
      return const Card(
        margin: EdgeInsets.all(8.0),
        child: Center(child: Text("No Sensor Data Available")),
      );
    }

    // 최신 날짜 찾기 (가장 최근 테이터 기준으로 1yo 프로필 작성)
    final sortedDates = sensorData.sciData.keys.toList()..sort();
    final latestDate = sortedDates.isNotEmpty ? sortedDates.last : null;

    final sensors = [
      {
        'key': 'temperature',
        'title': 'Temperature (°C)',
        'color': Colors.redAccent,
      },
      {
        'key': 'salinity',
        'title': 'Salinity (psu)',
        'color': Colors.blueAccent,
      },
      {
        'key': 'density',
        'title': 'Density (kg/m³)',
        'color': Colors.purpleAccent,
      },
      {'key': 'oxygen', 'title': 'Oxygen (uM)', 'color': Colors.cyan},
      {
        'key': 'chlorophyll',
        'title': 'Chlorophyll (mg/m³)',
        'color': Colors.green,
      },
      {'key': 'par', 'title': 'PAR', 'color': Colors.orange},
    ];

    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${provider.currentGlider} Sensor Profiles${widget.isArchiveMode ? " (Archive)" : ""}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showTimeDepthScatter = !_showTimeDepthScatter;
                        });
                      },
                      icon: Icon(
                        _showTimeDepthScatter
                            ? Icons.scatter_plot
                            : Icons.timeline,
                        size: 16,
                      ),
                      label: Text(
                        _showTimeDepthScatter
                            ? 'Show Value-Depth'
                            : 'Show Time-Depth (1yo)',
                      ),
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (!_showTimeDepthScatter) ...[
                      Container(
                        width: 12,
                        height: 12,
                        color: Colors.grey.withOpacity(0.3),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Past History',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 12,
                        height: 12,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.isArchiveMode ? 'Selected ($latestDate)' : 'Latest ($latestDate)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ] else ...[
                      // Colormap 안내 (간이 범례)
                      Container(
                        width: 60,
                        height: 12,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue,
                              Colors.cyan,
                              Colors.yellow,
                              Colors.red,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Value (Low \u2192 High)',
                        style: TextStyle(fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 한 줄에 3개씩, 총 2줄 (3x2 그리드)
                  final itemWidth = constraints.maxWidth / 3;
                  final itemHeight = constraints.maxHeight / 2;
                  final aspectRatio = itemWidth / itemHeight;

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: aspectRatio,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: sensors.length,
                    itemBuilder: (context, index) {
                      final s = sensors[index];
                      return _buildChartWidget(
                        sensorData,
                        s['key'] as String,
                        s['title'] as String,
                        s['color'] as Color,
                        latestDate,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartWidget(
    SensorWebResponse data,
    String sensorKey,
    String title,
    Color mainColor,
    String? latestDate,
  ) {
    List<ScatterSpot> pastSpots = [];
    List<ScatterSpot> latestSpots = [];
    List<double> latestSpotValues = [];

    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    double minDep = double.infinity;
    double maxDep = double.negativeInfinity;
    double minTime = double.infinity;
    double maxTime = double.negativeInfinity;

    // First pass: find min/max
    data.sciData.forEach((dateStr, dailyData) {
      SensorValues? sv;
      switch (sensorKey) {
        case 'temperature':
          sv = dailyData.temperature;
          break;
        case 'salinity':
          sv = dailyData.salinity;
          break;
        case 'density':
          sv = dailyData.density;
          break;
        case 'oxygen':
          sv = dailyData.oxygen;
          break;
        case 'chlorophyll':
          sv = dailyData.chlorophyll;
          break;
        case 'par':
          sv = dailyData.par;
          break;
      }

      if (sv != null) {
        final isLatest = (dateStr == latestDate);
        for (int i = 0; i < sv.value.length; i++) {
          final val = sv.value[i];
          final pres = sv.pres[i];
          final t = (sv.time.length > i) ? sv.time[i].toDouble() : 0.0;
          if (val.isNaN || pres.isNaN) continue;

          final invPres = -pres; // Y축 수심
          if (val < minVal) minVal = val;
          if (val > maxVal) maxVal = val;
          if (invPres < minDep) minDep = invPres;
          if (invPres > maxDep) maxDep = invPres;

          if (isLatest) {
            if (t < minTime) minTime = t;
            if (t > maxTime) maxTime = t;
          }
        }
      }
    });

    if (minVal == double.infinity) {
      return Card(
        color: Colors.grey[50],
        child: Center(child: Text('No Data: $title')),
      );
    }

    // Second pass: fill spots
    data.sciData.forEach((dateStr, dailyData) {
      SensorValues? sv;
      switch (sensorKey) {
        case 'temperature':
          sv = dailyData.temperature;
          break;
        case 'salinity':
          sv = dailyData.salinity;
          break;
        case 'density':
          sv = dailyData.density;
          break;
        case 'oxygen':
          sv = dailyData.oxygen;
          break;
        case 'chlorophyll':
          sv = dailyData.chlorophyll;
          break;
        case 'par':
          sv = dailyData.par;
          break;
      }

      if (sv != null) {
        final isLatest = (dateStr == latestDate);
        if (_showTimeDepthScatter && !isLatest) return; // 1yo(최근) 데이터만 그리기

        for (int i = 0; i < sv.value.length; i++) {
          final val = sv.value[i];
          final pres = sv.pres[i];
          final t = (sv.time.length > i) ? sv.time[i].toDouble() : 0.0;
          if (val.isNaN || pres.isNaN) continue;

          final invPres = -pres;

          if (_showTimeDepthScatter) {
            // Colormap 모드 (X: 타임스탬프, Y: 수심, 컬러: val)
            latestSpots.add(
              ScatterSpot(
                t,
                invPres,
                dotPainter: FlDotCirclePainter(
                  color: _getJetColor(val, minVal, maxVal),
                  radius: 2.0,
                  strokeWidth: 0,
                ),
              ),
            );
            latestSpotValues.add(val);
          } else {
            // 기본 모드 (X: val, Y: 수심)
            final spot = ScatterSpot(
              val,
              invPres,
              dotPainter: FlDotCirclePainter(
                color: isLatest ? mainColor : Colors.grey.withOpacity(0.3),
                radius: isLatest ? 2.5 : 1.5,
                strokeWidth: 0,
              ),
            );
            if (isLatest) {
              latestSpots.add(spot);
            } else {
              pastSpots.add(spot);
            }
          }
        }
      }
    });

    double finalMinX = _showTimeDepthScatter ? minTime : minVal;
    double finalMaxX = _showTimeDepthScatter ? maxTime : maxVal;

    // 데이터가 부재하거나 모두 NaN 처리되어 범위가 정상적이지 않을 때의 에러 방어망
    if (finalMinX == double.infinity ||
        finalMaxX == double.negativeInfinity ||
        finalMinX.isNaN ||
        finalMaxX.isNaN) {
      return Card(
        color: Colors.grey[50],
        child: Center(
          child: Text(
            'No Data: $title',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }

    // 간혹 X값이 하나인 경우 마진을 줍니다
    if (finalMinX == finalMaxX) {
      finalMinX -= 10;
      finalMaxX += 10;
    }

    // ChartFormatter 헬퍼 활용 (시간축 vs 센서값축)
    final xAxis = _showTimeDepthScatter
        ? ChartFormatter.getSmartTimeAxis(finalMinX, finalMaxX, tightFit: true)
        : ChartFormatter.getSmartAxis(finalMinX, finalMaxX, targetTicks: 4);

    // 날짜 범위 문자열 산출 (axisNameWidget 용)
    String dateRangeString = 'Value';
    if (_showTimeDepthScatter) {
      if (finalMinX != double.infinity &&
          finalMaxX != double.negativeInfinity &&
          !finalMinX.isNaN &&
          !finalMaxX.isNaN) {
        final minVInt = finalMinX.toInt();
        final maxVInt = finalMaxX.toInt();
        if (minVInt >= 0 && maxVInt >= 0) {
          final isMinSec = (minVInt < 10000000000);
          final isMaxSec = (maxVInt < 10000000000);
          final minDate = DateTime.fromMillisecondsSinceEpoch(
            minVInt * (isMinSec ? 1000 : 1),
          ).toLocal();
          final maxDate = DateTime.fromMillisecondsSinceEpoch(
            maxVInt * (isMaxSec ? 1000 : 1),
          ).toLocal();

          final minDateStr = DateFormat('MM/dd').format(minDate);
          final maxDateStr = DateFormat('MM/dd').format(maxDate);

          if (minDateStr == maxDateStr) {
            dateRangeString = minDateStr;
          } else {
            dateRangeString = '$minDateStr - $maxDateStr';
          }
        }
      } else {
        dateRangeString = 'Time';
      }
    }

    int valDecimals = 1;
    String displayTitle = title;
    if (minVal != double.infinity &&
        maxVal != double.negativeInfinity &&
        !minVal.isNaN &&
        !maxVal.isNaN) {
      valDecimals = ChartFormatter.getSmartAxis(minVal, maxVal).decimalPlaces;
      if (_showTimeDepthScatter) {
        displayTitle =
            '$title [ ${minVal.toStringAsFixed(valDecimals)} ~ ${maxVal.toStringAsFixed(valDecimals)} ]';
      }
    }

    return Card(
      color: widget.isArchiveMode ? Colors.grey[50] : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          top: 12.0,
          right: 16.0,
          left: 8.0,
          bottom: 8.0,
        ),
        child: Column(
          children: [
            Text(
              displayTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                children: [
                  ScatterChart(
                    ScatterChartData(
                      scatterSpots: _showTimeDepthScatter
                          ? latestSpots
                          : [...pastSpots, ...latestSpots],
                      minX: xAxis.min,
                      maxX: xAxis.max,
                      // 수심 그래프는 위아래 50m 여백으로 고정
                      minY: minDep - 50,
                      maxY: 50,
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          axisNameWidget: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              dateRangeString,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.blueGrey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          axisNameSize: 16,
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: _showTimeDepthScatter
                                ? xAxis.interval
                                : (xAxis.max - xAxis.min) / 2,
                            getTitlesWidget: (value, meta) {
                              if (value < xAxis.min || value > xAxis.max) {
                                return const SizedBox.shrink();
                              }

                              if (_showTimeDepthScatter) {
                                if (value < 0) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    ChartFormatter.formatTimeOnly(value),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.blueGrey,
                                      letterSpacing: -0.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }

                              final double min = xAxis.min;
                              final double max = xAxis.max;
                              final double mid = min + (max - min) / 2;
                              if ((value - min).abs() < 0.001 ||
                                  (value - max).abs() < 0.001 ||
                                  (value - mid).abs() < 0.001) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    value.toStringAsFixed(xAxis.decimalPlaces),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget: const Text(
                            'Depth(m)',
                            style: TextStyle(fontSize: 10),
                          ),
                          axisNameSize: 16,
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: 200,
                            getTitlesWidget: (value, meta) => Text(
                              (-value).toStringAsFixed(0),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: true,
                        horizontalInterval: 200,
                        verticalInterval: _showTimeDepthScatter
                            ? xAxis.interval
                            : (xAxis.max - xAxis.min) / 2,
                        getDrawingHorizontalLine: (val) => FlLine(
                          color: Colors.grey.withOpacity(0.2),
                          strokeWidth: 1,
                        ),
                        getDrawingVerticalLine: (val) => FlLine(
                          color: Colors.grey.withOpacity(0.2),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      scatterTouchData: ScatterTouchData(
                        enabled: true,
                        touchTooltipData: ScatterTouchTooltipData(
                          getTooltipColor: (ScatterSpot touchedSpot) =>
                              Colors.blueGrey.withOpacity(0.85),
                          getTooltipItems: (ScatterSpot touchedSpot) {
                            // ✅ 핵심 수정: Value-Depth 모드일 때, 터치된 점이 최신 데이터가 아니면 툴팁을 띄우지 않음 (null 반환)
                            if (!_showTimeDepthScatter &&
                                !latestSpots.contains(touchedSpot)) {
                              return null;
                            }
                            return ScatterTooltipItem(
                              _showTimeDepthScatter
                                  ? 'Time: ${ChartFormatter.formatTimeOnly(touchedSpot.x)}\nDepth: ${(-touchedSpot.y).toStringAsFixed(1)}m\nVal: ${latestSpotValues.isNotEmpty && latestSpots.contains(touchedSpot) ? latestSpotValues[latestSpots.indexOf(touchedSpot)].toStringAsFixed(valDecimals) : '?/A'}'
                                  : 'Val: ${touchedSpot.x.toStringAsFixed(valDecimals)}\nDepth: ${(-touchedSpot.y).toStringAsFixed(1)}m',
                              textStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_showTimeDepthScatter)
                    Positioned(
                      top: 4,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          border: Border.all(
                            color: Colors.blueGrey,
                            width: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          latestDate ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
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
    );
  }
}
