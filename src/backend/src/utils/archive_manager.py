"""
archive_manager.py
==================
글라이더 과거 임무(Archive) 보관 시, 프론트엔드 '수위 조절 달력(Water Level Calendar)' UI에
렌더링할 초경량 요약 JSON 파일(archive_calendar_summary.json)을 생성하는 모듈.

파이프라인:
  _sensor.json 로딩
  → 표층 데이터 추출 (pres ≤ 5.0)
  → 이상치 하드 컷오프 (복소수/NaN, 1015~1027 범위 외)
  → 일별 평균 산출
  → 선형 보간 (limit=3)
  → Min-Max 정규화 (1015→0.0, 1027→1.0) + 클리핑
  → archive_calendar_summary.json 원자적 저장
"""

import os
import sys
import json
import math

# backend 폴더를 PYTHON PATH에 추가 (기존 프로젝트 패턴 동일하게 적용)
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import pandas as pd
import numpy as np


# ============================================================
# 상수 정의
# ============================================================
SURFACE_PRES_THRESHOLD = 5.0   # 표층 기준 수심 (dbar)
DENSITY_MIN = 1015.0            # 물리적 유효 밀도 하한
DENSITY_MAX = 1027.0            # 물리적 유효 밀도 상한
INTERP_LIMIT = 3                # 선형 보간 최대 연속 결측일 수


# ============================================================
# 유틸리티: 원자적 JSON 저장 (기존 atomic_write_json 패턴 채용)
# ============================================================
def _atomic_write_json(filepath: str, data: dict) -> None:
    """임시 파일(.tmp)에 먼저 쓴 뒤 os.replace()로 원자적 교체."""
    tmp_path = filepath + '.tmp'
    with open(tmp_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp_path, filepath)


# ============================================================
# 메인 함수
# ============================================================
def generate_calendar_summary(
    sensor_json_path: str,
    output_dir: str,
    glider_name: str
) -> str:
    """
    _sensor.json에서 밀도(density) 데이터를 읽어
    달력 렌더링용 archive_calendar_summary.json을 생성한다.

    Args:
        sensor_json_path: {glider_name}_sensor.json 의 절대 경로
        output_dir:        결과 JSON을 저장할 디렉터리 경로
        glider_name:       글라이더 이름 (로그 출력용)

    Returns:
        생성된 archive_calendar_summary.json 의 절대 경로
    """

    # ----------------------------------------------------------
    # Step 2: _sensor.json 로딩 및 표층 데이터 추출
    # ----------------------------------------------------------
    print(f"[archive_manager] {glider_name}: {sensor_json_path} 로딩 중...")
    with open(sensor_json_path, 'r', encoding='utf-8') as f:
        raw = json.load(f)

    sci_data = raw.get('sci_data', {})
    if not sci_data:
        print(f"[archive_manager] 경고: sci_data가 비어 있습니다. 종료.")
        return None

    # 날짜별 (time, pres, value) 레코드 수집
    records = []
    for date_str, daily in sci_data.items():
        density = daily.get('density', {})
        pres_list  = density.get('pres',  [])
        value_list = density.get('value', [])

        # pres와 value 길이가 일치하는 경우만 처리
        if not pres_list or not value_list:
            continue
        if len(pres_list) != len(value_list):
            n = min(len(pres_list), len(value_list))
            pres_list  = pres_list[:n]
            value_list = value_list[:n]

        for pres, value in zip(pres_list, value_list):
            # 표층 필터: pres ≤ 5.0 인 데이터만 추출
            try:
                pres_f = float(pres)
            except (TypeError, ValueError):
                continue
            if pres_f > SURFACE_PRES_THRESHOLD:
                continue
            records.append({'date': date_str, 'value': value})

    if not records:
        print(f"[archive_manager] 경고: 표층 데이터(pres ≤ {SURFACE_PRES_THRESHOLD})가 없습니다.")
        return None

    df = pd.DataFrame(records)
    df['date'] = pd.to_datetime(df['date'])

    # ----------------------------------------------------------
    # Step 3: 이상치 하드 컷오프
    # ----------------------------------------------------------
    # 복소수 문자열(예: 998+0.001i), 비수치, NaN → NaN으로 강제 변환 후 제거
    df['value'] = pd.to_numeric(df['value'], errors='coerce')
    df.dropna(subset=['value'], inplace=True)

    # 물리적 유효 범위(1015 ~ 1025) 외 데이터 제거
    df = df[(df['value'] >= DENSITY_MIN) & (df['value'] <= DENSITY_MAX)]

    if df.empty:
        print(f"[archive_manager] 경고: 이상치 제거 후 유효 데이터가 없습니다.")
        return None

    # ----------------------------------------------------------
    # Step 4: 일별 대푯값(평균) 산출
    # ----------------------------------------------------------
    daily_mean = df.groupby('date')['value'].mean()

    # ----------------------------------------------------------
    # Step 5: 결측치 선형 보간 (Safety Interpolation)
    # ----------------------------------------------------------
    mission_start = daily_mean.index.min()
    mission_end   = daily_mean.index.max()
    full_range    = pd.date_range(start=mission_start, end=mission_end, freq='D')

    # 전체 날짜 범위로 reindex → 누락된 날짜에 NaN 삽입
    daily_mean = daily_mean.reindex(full_range)

    # 선형 보간: 최대 3일 연속까지만 보간, 4일 이상 공백은 NaN 유지
    daily_mean = daily_mean.interpolate(method='linear', limit=INTERP_LIMIT)

    # ----------------------------------------------------------
    # Step 6: Min-Max 정규화 및 클리핑
    # ----------------------------------------------------------
    # 1015 → 0.0, 1027 → 1.0 기준
    ratio_series = (daily_mean - DENSITY_MIN) / (DENSITY_MAX - DENSITY_MIN)
    ratio_series = ratio_series.clip(lower=0.0, upper=1.0)

    # ----------------------------------------------------------
    # Step 7: JSON 출력
    # ----------------------------------------------------------
    result = {}
    for date, ratio in ratio_series.items():
        date_str = date.strftime('%Y-%m-%d')
        if pd.isna(ratio) or (isinstance(ratio, float) and math.isnan(ratio)):
            result[date_str] = {"ratio": None}
        else:
            result[date_str] = {"ratio": round(float(ratio), 3)}

    # 원자적 저장
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, 'archive_calendar_summary.json')
    _atomic_write_json(output_path, result)

    print(f"[archive_manager] 완료: {output_path}")
    print(f"  → 총 {len(result)}일 | 유효 데이터 {ratio_series.notna().sum()}일 | null {ratio_series.isna().sum()}일")
    return output_path


# ============================================================
# __main__ CLI 진입점
# ============================================================
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="글라이더 _sensor.json → archive_calendar_summary.json 생성"
    )
    parser.add_argument(
        '--glider',
        type=str,
        required=True,
        help='글라이더 이름'
    )
    parser.add_argument(
        '--sensor_path',
        type=str,
        default=None,
        help='_sensor.json 의 절대 경로 (미지정 시 자동 추론)'
    )
    parser.add_argument(
        '--output',
        type=str,
        default=None,
        help='결과 JSON 저장 디렉터리 (미지정 시 sensor_path 기준 자동 설정)'
    )
    args = parser.parse_args()

    # 경로 자동 추론
    backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    sensor_path = args.sensor_path or os.path.join(
        backend_dir, 'gliders', args.glider, 'WebData', f'{args.glider}_sensor.json'
    )
    output_dir = args.output or os.path.join(
        backend_dir, 'gliders', args.glider, 'WebData'
    )

    generate_calendar_summary(
        sensor_json_path=sensor_path,
        output_dir=output_dir,
        glider_name=args.glider
    )
