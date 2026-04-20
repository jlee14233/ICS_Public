import 'package:flutter/material.dart';

/// 아카이브 미션 데이터 모델.
/// archived_missions/{glider}/ 하위의 개별 미션 폴더를 구조화된 객체로 표현한다.
///
/// 폴더명 규칙: {gliderName}_{startDate}_{endDate}
/// 예: 
class ArchiveMissionModel {
  /// 원본 디렉토리 이름 
  final String folderName;

  /// 파싱된 글라이더 식별자 
  final String gliderName;

  /// 미션 시작일 (파싱 실패 시 null)
  final DateTime? startDate;

  /// 미션 종료일 (파싱 실패 시 null)
  final DateTime? endDate;

  /// 로컬 디렉토리의 메타데이터 기반 보관 시각
  final DateTime archivedDate;

  const ArchiveMissionModel({
    required this.folderName,
    required this.gliderName,
    this.startDate,
    this.endDate,
    required this.archivedDate,
  });

  /// 폴더명 문자열과 파일시스템 메타데이터로부터 모델 객체를 생성한다.
  ///
  /// [folderName] — 디렉토리 이름
  /// [archivedDate] — Directory.stat() 에서 추출한 수정/생성 시각
  ///
  /// 파싱 실패 시 크래시를 방지하고 안전한 Fallback 값을 적용한다.
  factory ArchiveMissionModel.fromFolderName(
    String folderName, {
    required DateTime archivedDate,
  }) {
    String parsedGliderName = folderName; // Fallback: 폴더명 전체
    DateTime? parsedStartDate;
    DateTime? parsedEndDate;

    try {
      // 폴더명을 '_' 기준으로 분리
      final parts = folderName.split('_');

      // 최소 4개 파트 필요: {prefix}_{id}_{startDate}_{endDate}
      if (parts.length >= 4) {
        // 글라이더명: 마지막 2개(날짜)를 제외한 앞쪽 파트를 결합
        final dateParts = parts.sublist(parts.length - 2);
        final nameParts = parts.sublist(0, parts.length - 2);
        parsedGliderName = nameParts.join('_');

        // 시작일 파싱 (yyyyMMdd)
        parsedStartDate = _parseDate(dateParts[0]);

        // 종료일 파싱 (yyyyMMdd)
        parsedEndDate = _parseDate(dateParts[1]);
      } else {
        debugPrint(
          '[ArchiveMissionModel] 비표준 폴더명 형식 (파트 < 4): $folderName → Fallback 적용',
        );
      }
    } catch (e) {
      debugPrint(
        '[ArchiveMissionModel] 폴더명 파싱 에러: $folderName → $e → Fallback 적용',
      );
      // Fallback: 이미 초기값으로 설정되어 있으므로 추가 작업 불필요
    }

    return ArchiveMissionModel(
      folderName: folderName,
      gliderName: parsedGliderName,
      startDate: parsedStartDate,
      endDate: parsedEndDate,
      archivedDate: archivedDate,
    );
  }

  /// yyyyMMdd 형식의 문자열을 DateTime으로 변환한다.
  /// 파싱 실패 시 null을 반환한다.
  static DateTime? _parseDate(String raw) {
    try {
      if (raw.length != 8) return null;
      final year = int.parse(raw.substring(0, 4));
      final month = int.parse(raw.substring(4, 6));
      final day = int.parse(raw.substring(6, 8));

      // 유효성 검증: 비정상 날짜 방어
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;

      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'ArchiveMissionModel(folder: $folderName, glider: $gliderName, '
      'start: $startDate, end: $endDate, archived: $archivedDate)';
}
