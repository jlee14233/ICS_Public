import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart'; // 시간 포맷팅용
import '../providers/glider_provider.dart';
import '../models/glider_log.dart';
import '../utils/chart_formatter.dart';

class FlightFrame extends StatelessWidget {
  const FlightFrame({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GliderProvider>();
    final logResponse = provider.logData;
    final logData = logResponse?.logData ?? [];
    final perfData = provider.performanceData?.performanceData ?? [];

    if (provider.isLoading) {
      return const Card(
        margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (logData.isEmpty) {
      return const Card(
        margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Center(child: Text("No Flight Data Available")),
      );
    }

    final latestLog = logData.last;
    final latestPerf = perfData.isNotEmpty ? perfData.last : null;

    // 차기 부상 시간 뱃지 포맷팅
    String nextSurfaceStr = 'N/A';
    if (logResponse?.nextSurfaceTime != null) {
      try {
        final dt = DateTime.parse(logResponse!.nextSurfaceTime!).toLocal();
        nextSurfaceStr = DateFormat('MM/dd HH:mm').format(dt);
      } catch (e) {
        nextSurfaceStr = 'Error';
      }
    }

    // 최근 부상 시간 대비 24시간 기준 필터링
    final recentLogData = logData.where((l) {
      if (l.timestamp == null || latestLog.timestamp == null) return false;
      return l.timestamp!.isAfter(
        latestLog.timestamp!.subtract(const Duration(hours: 24)),
      );
    }).toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      elevation: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.flight_takeoff, color: Colors.blueGrey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Flight & Performance (Recent 24h)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (nextSurfaceStr != 'N/A')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time_filled,
                          color: Colors.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '차기 부상 예상: $nextSurfaceStr',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 상단: 핵심 지표
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Leak 상태
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildLeakBadge('Fwd Leak', latestLog.leakForward),
                    _buildLeakBadge('Sci Leak', latestLog.leakScience),
                    _buildLeakBadge('Aft Leak', latestLog.leakAft),
                  ],
                ),
                const SizedBox(height: 16),
                // Performance 지표
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPerfMetric(
                      '상승하강비 (%)',
                      latestPerf?.glideRatio != null
                          ? latestPerf!.glideRatio! * 100.0
                          : null,
                      ' %',
                    ), // 상승하강비는 그대로 둠
                    _buildPerfMetric(
                      '글라이더 속도(VMG)',
                      latestLog.velocityCmps,
                      ' cm/s',
                    ), // ✅ latestPerf -> latestLog 로 변경!
                    _buildPerfMetric(
                      '경로 이탈 거리',
                      latestLog.offTrackDistanceM,
                      ' m',
                    ), // ✅ latestPerf -> latestLog 로 변경!
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 하단: 추세 차트 그리드
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ListView(
                children: [
                  // 미니 차트 단위(unit) 인자 추가 및 TitlesData 활성화
                  _buildMiniChartRow([
                    _buildTrendChart(
                      'Battery',
                      'Amphr',
                      recentLogData,
                      (l) => l.batteryAmphr,
                      Colors.orange,
                    ),
                    _buildTrendChart(
                      'Voltage',
                      'V',
                      recentLogData,
                      (l) => l.voltage,
                      Colors.green,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _buildMiniChartRow([
                    _buildTrendChart(
                      'Vacuum',
                      'inHg',
                      recentLogData,
                      (l) => l.vacuum,
                      Colors.blue,
                    ),
                    _buildTrendChart(
                      'veh_temp',
                      '°C',
                      recentLogData,
                      (l) => l.temperature,
                      Colors.red,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _buildMiniChartRow([
                    _buildTrendChart(
                      'Vy Velocity',
                      'm/s',
                      recentLogData,
                      (l) => l.vy,
                      Colors.indigo,
                    ),
                    _buildTrendChart(
                      'Vx Velocity',
                      'm/s',
                      recentLogData,
                      (l) => l.vx,
                      Colors.purple,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _buildErrorBarChart(recentLogData),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeakBadge(String label, double? value) {
    // 2.3 미만이면 위험(빨간색), 2.31 ~ 2.5 사이면 안전(초록색) (null 여부 보수적 체크)
    bool isWarning = false;
    if (value != null) {
      if (value < 2.3) {
        isWarning = true;
      } else if (value >= 2.31 && value <= 2.5) {
        isWarning = false;
      } else {
        // 그 외 범위는 기본적으로 경고 처리할지 여부 (요청에 명확치 않아 임의로 경고로 처리)
        isWarning = true;
      }
    }

    return Column(
      children: [
        Icon(
          isWarning ? Icons.warning_amber_rounded : Icons.check_circle,
          color: isWarning ? Colors.red : Colors.green,
          size: 28,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(
          value?.toStringAsFixed(2) ?? 'N/A',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPerfMetric(String label, double? value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value != null ? '${value.toStringAsFixed(2)}$unit' : 'N/A',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMiniChartRow(List<Widget> charts) {
    return Row(children: charts.map((c) => Expanded(child: c)).toList());
  }

  Widget _buildTrendChart(
    String title,
    String unit,
    List<LogEntry> logs,
    double? Function(LogEntry) extractor,
    Color color,
  ) {
    List<FlSpot> spots = [];
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;

    // 1. timestamp 기준으로 오름차순 정렬 (차트 선 꼬임 방지)
    final sortedLogs = List<LogEntry>.from(logs);
    sortedLogs.sort((a, b) {
      if (a.timestamp == null || b.timestamp == null) return 0;
      return a.timestamp!.compareTo(b.timestamp!);
    });

    // 2. Map 데이터 추출 후 바로 FlSpot에 적재 (인덱싱 및 그룹핑 완전 제거, Chronological Sync)
    double? prevT;
    for (var log in sortedLogs) {
      final val = extractor(log);
      if (val != null && !val.isNaN && log.timestamp != null) {
        final t = log.timestamp!.millisecondsSinceEpoch.toDouble();

        // [프론트엔드 방어] 중복된 X축 혹은 시간 역행 방지 (차트 수직 꺾임 및 왜곡 차단)
        if (prevT != null && t <= prevT) continue;
        prevT = t;

        if (val < minVal) minVal = val;
        if (val > maxVal) maxVal = val;
        spots.add(FlSpot(t, val));
      }
    }

    if (spots.isEmpty) {
      return Container(
        height: 120, // 높이 고정 및 약간 확장
        margin: const EdgeInsets.symmetric(horizontal: 4.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text('No Data: $title', style: const TextStyle(fontSize: 10)),
        ),
      );
    }

    // ChartFormatter 헬퍼를 호출하여 스마트하게 X축(시간) 및 Y축(값) 여백과 간격을 가져옵니다.
    final xAxis = ChartFormatter.getSmartTimeAxis(
      sortedLogs.first.timestamp!.millisecondsSinceEpoch.toDouble(),
      sortedLogs.last.timestamp!.millisecondsSinceEpoch.toDouble(),
    );
    final yAxis = ChartFormatter.getSmartAxis(minVal, maxVal, targetTicks: 4);

    return Container(
      height: 120, // 전체 차트 높이 통일
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.only(top: 8, right: 16, bottom: 4, left: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            // 타이틀과 단위를 함께 표시
            child: Text(
              '$title ($unit)',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                LineChart(
                  LineChartData(
                    minX: xAxis.min,
                    maxX: xAxis.max,
                    minY: yAxis.min,
                    maxY: yAxis.max,
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: false, // 곡선 유지
                        color: color,
                        barWidth: 2.0,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withOpacity(0.1), // 하단 영역 색상 채우기
                        ),
                      ),
                    ],
                    // Tick 표기 (좌측 축, 하단 축 시각 표시)
                    titlesData: FlTitlesData(
                      show: true,
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          // 데이터 유효 폭에 따라 10분/30분/2시간/6시간 단위로 고정 렌더
                          interval: xAxis.interval,
                          getTitlesWidget: (value, meta) {
                            final date = DateTime.fromMillisecondsSinceEpoch(
                              value.toInt(),
                            );
                            if (value < xAxis.min || value > xAxis.max) {
                              return const SizedBox.shrink();
                            }

                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                ChartFormatter.formatTimeOnly(value),
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval: yAxis.interval,
                          getTitlesWidget: (value, meta) {
                            // 스마트 포맷터가 결정해준 자릿수(yAxis.decimalPlaces) 구문 활용
                            if (value < yAxis.min || value > yAxis.max) {
                              return const SizedBox.shrink();
                            }

                            return Text(
                              value.toStringAsFixed(yAxis.decimalPlaces),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      drawHorizontalLine: true,
                      horizontalInterval: yAxis.interval,
                      verticalInterval: xAxis.interval,
                      getDrawingHorizontalLine: (val) => FlLine(
                        color: Colors.black.withOpacity(0.3),
                        strokeWidth: 1.5,
                      ),
                      getDrawingVerticalLine: (val) => FlLine(
                        color: Colors.black.withOpacity(0.3),
                        strokeWidth: 1.5,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((FlSpot spot) {
                            return LineTooltipItem(
                              spot.y.toStringAsFixed(2),
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
                if (spots.isNotEmpty)
                  Positioned(
                    bottom: 24,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        border: Border.all(color: Colors.blueGrey, width: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        logs.isNotEmpty && logs.last.timestamp != null
                            ? ChartFormatter.formatShortDateOnly(
                                logs.last.timestamp!.millisecondsSinceEpoch
                                    .toDouble(),
                              )
                            : 'N/A',
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
    );
  }

  Widget _buildErrorBarChart(List<LogEntry> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();

    List<BarChartGroupData> barGroups = [];
    List<DateTime> groupTimes = [];
    double maxY = 4;

    final sortedLogs = List<LogEntry>.from(logs);
    sortedLogs.sort((a, b) {
      if (a.timestamp == null || b.timestamp == null) return 0;
      return a.timestamp!.compareTo(b.timestamp!);
    });

    final firstMs = sortedLogs.first.timestamp!.millisecondsSinceEpoch
        .toDouble();
    final lastMs = sortedLogs.last.timestamp!.millisecondsSinceEpoch.toDouble();

    // 차트 레이아웃 동기화를 위한 시간 간격 단위(30분 = 1,800,000 ms)
    double gridMs = 1800000.0;
    int minIndex = (firstMs / gridMs).floor();
    int maxIndex = (lastMs / gridMs).ceil();
    int totalSlots = maxIndex - minIndex + 1;

    // Time-Slot 초기화 (Dummy 투명 막대로 전체 영역 비율 1:1 고정)
    List<Map<String, double>> slotErrors = List.generate(
      totalSlots,
      (i) => {'odd': 0, 'warn': 0, 'err': 0},
    );

    for (var log in sortedLogs) {
      if (log.timestamp != null) {
        int slotIdx =
            (log.timestamp!.millisecondsSinceEpoch.toDouble() / gridMs)
                .floor() -
            minIndex;
        if (slotIdx >= 0 && slotIdx < totalSlots) {
          slotErrors[slotIdx]['odd'] =
              (slotErrors[slotIdx]['odd']! + (log.odd ?? 0));
          slotErrors[slotIdx]['warn'] =
              (slotErrors[slotIdx]['warn']! + (log.warn ?? 0));
          slotErrors[slotIdx]['err'] =
              (slotErrors[slotIdx]['err']! + (log.err ?? 0));
        }
      }
    }

    int index = 0;
    for (int i = 0; i < totalSlots; i++) {
      double oddVal = slotErrors[i]['odd']!;
      double warnVal = slotErrors[i]['warn']!;
      double errVal = slotErrors[i]['err']!;

      if (oddVal > maxY) maxY = oddVal;
      if (errVal > maxY) maxY = errVal;
      if (warnVal > maxY) maxY = warnVal;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 1.5,
          barRods: [
            BarChartRodData(
              toY: oddVal,
              width: 4,
              color: Colors.blue,
              borderRadius: BorderRadius.zero,
            ),
            BarChartRodData(
              toY: warnVal,
              width: 4,
              color: Colors.orange,
              borderRadius: BorderRadius.zero,
            ),
            BarChartRodData(
              toY: errVal,
              width: 4,
              color: Colors.red,
              borderRadius: BorderRadius.zero,
            ),
          ],
        ),
      );
      // groupTimes 매핑: 각 슬롯의 대표 시간(시작 시간)을 DateTime으로 복원
      groupTimes.add(
        DateTime.fromMillisecondsSinceEpoch(
          ((minIndex + i) * gridMs).toInt(),
        ).toLocal(),
      );
    }

    if (barGroups.isEmpty) {
      return Container(
        height: 150,
        margin: const EdgeInsets.symmetric(horizontal: 4.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('No Error Logs', style: TextStyle(fontSize: 10)),
        ),
      );
    }

    // Determine interval for X-axis labels to avoid crowding (Max 8 labels logic)
    double interval = 1;
    if (barGroups.length > 10) {
      interval = (barGroups.length / 8).floorToDouble();
    }

    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.only(top: 8, right: 16, bottom: 4, left: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4.0),
            child: Text(
              'Error / Warn / Odd (Segment)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (maxY + 1).ceilToDouble(),
                    barGroups: barGroups,
                    titlesData: FlTitlesData(
                      show: true,
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: interval,
                          getTitlesWidget: (value, meta) {
                            int idx = value.toInt();
                            if (idx < 0 || idx >= groupTimes.length) {
                              return const SizedBox.shrink();
                            }

                            // 간격 체크 (물리적인 텍스트 겹침 완벽 차단)
                            if (idx % interval.toInt() != 0) {
                              return const SizedBox.shrink();
                            }

                            final date = groupTimes[idx];
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                ChartFormatter.formatTimeOnly(
                                  date.millisecondsSinceEpoch.toDouble(),
                                ),
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) {
                            if (value % 1 != 0) return const SizedBox.shrink();
                            return Text(
                              value.toInt().toString(),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (val) => FlLine(
                        color: Colors.black.withOpacity(0.3),
                        strokeWidth: 1.5,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => Colors.blueGrey,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          String label = '';
                          if (rodIndex == 0) {
                            label = 'Odd';
                          } else if (rodIndex == 1)
                            label = 'Warn';
                          else if (rodIndex == 2)
                            label = 'Err';

                          return BarTooltipItem(
                            '$label: ${rod.toY.toInt()}',
                            const TextStyle(
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
                if (groupTimes.isNotEmpty)
                  Positioned(
                    bottom: 28,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        border: Border.all(color: Colors.blueGrey, width: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ChartFormatter.formatShortDateOnly(
                          groupTimes.last.millisecondsSinceEpoch.toDouble(),
                        ),
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
          // 범례(Legend) 추가
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(Colors.blue, 'Odd'),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.orange, 'Warn'),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.red, 'Err'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
