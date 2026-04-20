import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WaterLevelCalendar extends StatefulWidget {
  /// 날짜별 밀도 데이터: {'ratio': 0.0~1.0, 'value': 1018.5 등}, null이면 결측치
  final Map<DateTime, Map<String, dynamic>> dailyData;
  final ValueChanged<DateTime> onDateSelected;
  final DateTime? selectedDate;
  final DateTime initialMonth;

  const WaterLevelCalendar({
    Key? key,
    required this.dailyData,
    required this.onDateSelected,
    this.selectedDate,
    required this.initialMonth,
  }) : super(key: key);

  @override
  State<WaterLevelCalendar> createState() => _WaterLevelCalendarState();
}

class _WaterLevelCalendarState extends State<WaterLevelCalendar> {
  late PageController _pageController;
  late DateTime _currentShownMonth;
  late DateTime _baseMonth; // PageView 인덱스 기준 월
  late Map<String, Map<String, dynamic>> _normalizedData;

  static const int _centerPage = 10000;

  @override
  void initState() {
    super.initState();
    _normalizeDataKeys();
    _baseMonth = DateTime(
      widget.initialMonth.year,
      widget.initialMonth.month,
    );
    _currentShownMonth = _baseMonth;
    _pageController = PageController(initialPage: _centerPage);
  }

  @override
  void didUpdateWidget(covariant WaterLevelCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 데이터가 변경되면 정규화 맵 갱신
    if (widget.dailyData != oldWidget.dailyData) {
      _normalizeDataKeys();
    }

    // initialMonth가 변경되면 (미션 변경 등) 해당 월로 즉시 점프
    final newMonth = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    final oldMonth = DateTime(oldWidget.initialMonth.year, oldWidget.initialMonth.month);
    if (newMonth != oldMonth) {
      // 베이스 월 대비 오프셋 계산
      final offset = (newMonth.year - _baseMonth.year) * 12 +
          (newMonth.month - _baseMonth.month);
      final targetPage = _centerPage + offset;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(targetPage);
          setState(() {
            _currentShownMonth = newMonth;
          });
        }
      });
    }
  }

  void _normalizeDataKeys() {
    _normalizedData = {};
    widget.dailyData.forEach((key, value) {
      final dateKey =
          '${key.year}-${key.month.toString().padLeft(2, '0')}-${key.day.toString().padLeft(2, '0')}';
      _normalizedData[dateKey] = value;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _getMonthFromIndex(int index) {
    final offset = index - _centerPage;
    return DateTime(
      _baseMonth.year,
      _baseMonth.month + offset,
    );
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 밀도 수치를 축약 (1018.5 -> '18')
  String? _abbreviateValue(double? value) {
    if (value == null) return null;
    return (value.toInt() % 100).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 달력 상단: 월 네비게이션 ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              Text(
                DateFormat('yyyy. MM').format(_currentShownMonth),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            ],
          ),
        ),
        // ── 요일 헤더 ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['일', '월', '화', '수', '목', '금', '토'].map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: day == '일'
                          ? Colors.red
                          : (day == '토' ? Colors.blue : Colors.black87),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // ── 달력 본문 (스와이프) ──
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentShownMonth = _getMonthFromIndex(index);
              });
            },
            itemBuilder: (context, index) {
              final monthToBuild = _getMonthFromIndex(index);
              return _buildMonthGrid(monthToBuild);
            },
          ),
        ),
        // ── 하단 범례(Legend) ──
        _buildLegend(),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  범례 (Legend) 위젯
  // ═══════════════════════════════════════════
  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          // 그라디언트 바
          Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                colors: [
                  Colors.blue.withOpacity(0.05),
                  Colors.blue.withOpacity(0.3),
                  Colors.blue.withOpacity(0.55),
                  Colors.blue.withOpacity(0.8),
                  Colors.blue.withOpacity(1.0),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 범례 라벨
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Low', style: TextStyle(fontSize: 10, color: Colors.grey)),
              Flexible(
                child: Text(
                  '단위: kg/m³  (축약 표기: 18 = 1018)  /  연한 색(Low) ~ 짙은 색(High)',
                  style: TextStyle(fontSize: 9, color: Colors.grey),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('High', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  월별 그리드 빌더
  // ═══════════════════════════════════════════
  Widget _buildMonthGrid(DateTime monthDate) {
    final firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1);
    final lastDayOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0);

    final firstWeekday = firstDayOfMonth.weekday == 7
        ? 0
        : firstDayOfMonth.weekday;

    final totalCells = firstWeekday + lastDayOfMonth.day;
    final totalRows = (totalCells / 7).ceil();
    final gridCells = totalRows * 7;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 0.8,
          crossAxisSpacing: 4.0,
          mainAxisSpacing: 4.0,
        ),
        itemCount: gridCells,
        itemBuilder: (context, index) {
          if (index < firstWeekday || index >= totalCells) {
            return const SizedBox();
          }

          final dayNumber = index - firstWeekday + 1;
          final cellDate = DateTime(monthDate.year, monthDate.month, dayNumber);

          return _buildDateCell(cellDate);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  날짜 셀 빌더 (색상 농도 방식)
  // ═══════════════════════════════════════════
  Widget _buildDateCell(DateTime cellDate) {
    final normalizedCellDate = _normalizeDate(cellDate);
    final isSelected =
        widget.selectedDate != null &&
        _normalizeDate(widget.selectedDate!) == normalizedCellDate;

    // O(1) 키 매칭
    final dateKey =
        '${cellDate.year}-${cellDate.month.toString().padLeft(2, '0')}-${cellDate.day.toString().padLeft(2, '0')}';
    final Map<String, dynamic>? cellData = _normalizedData[dateKey];

    final double? ratio = cellData?['ratio'] as double?;
    final double? value = cellData?['value'] as double?;

    final isMissing = ratio == null;
    final String? abbreviatedValue = _abbreviateValue(value);

    return GestureDetector(
      onTap: () => widget.onDateSelected(cellDate),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Colors.blueAccent
                : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2.0 : 1.0,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              // ── 배경: 색상 농도 (즉시 적용, 애니메이션 없음) ──
              Positioned.fill(
                child: isMissing
                    ? CustomPaint(painter: StripedHatchingPainter())
                    : Container(
                        color: Colors.blue.withOpacity(
                          ratio.clamp(0.0, 1.0) * 0.85 + 0.05,
                        ),
                      ),
              ),
              // ── 날짜 숫자 + 축약 수치 ──
              Positioned(
                top: 4,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 날짜 숫자
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isMissing
                            ? Colors.white.withOpacity(0.6)
                            : Colors.white.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${cellDate.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Colors.blueAccent
                              : Colors.black87,
                        ),
                      ),
                    ),
                    // 축약 수치 (데이터 존재 시에만)
                    if (!isMissing && abbreviatedValue != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        abbreviatedValue,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: ratio > 0.5
                              ? Colors.white.withOpacity(0.85)
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 회색 빗금 패턴을 그리는 CustomPainter (결측치 표시용)
class StripedHatchingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    double step = 8;
    for (double i = -size.height; i < size.width; i += step) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
