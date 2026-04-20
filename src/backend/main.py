from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
import os
import sys
import json
import shutil
import logging
from datetime import datetime

# 프로젝트 루트 디렉토리를 path에 추가하여 ais_cache 등의 모듈 임포트 허용
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT_DIR not in sys.path:
    sys.path.append(ROOT_DIR)

from ais_cache import get_ais_from_bbox
from backend_config import get_glider_dir, get_webdata_dir, get_archive_dir, ARCHIVE_ROOT
from src.utils.glider_utils import filter_waypoints_by_heading

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Frontend API"])

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

def get_file_response(filepath: str):
    if os.path.exists(filepath):
        return FileResponse(filepath, media_type="application/json")
    raise HTTPException(status_code=404, detail="Data file not found")

@router.get("/data/{glider}/log")
def get_log(glider: str):
    return get_file_response(os.path.join(BASE_DIR, 'gliders', glider, 'WebData', f'{glider}_log.json'))

@router.get("/data/{glider}/sensor_web")
def get_sensor_web(glider: str):
    return get_file_response(os.path.join(BASE_DIR, 'gliders', glider, 'WebData', f'{glider}_sensor_web.json'))

@router.get("/data/{glider}/performance")
def get_performance(glider: str):
    return get_file_response(os.path.join(BASE_DIR, 'gliders', glider, 'WebData', f'{glider}_performance.json'))

@router.get("/data/{glider}/waypoints")
def get_waypoints(glider: str):
    return get_file_response(os.path.join(BASE_DIR, 'gliders', glider, 'WebData', f'{glider}_waypoints.json'))

@router.get("/data/{glider}/glider_track")
def get_glider_track(glider: str):
    return get_file_response(os.path.join(BASE_DIR, 'gliders', glider, 'WebData', 'glider_track.json'))

@router.get("/data/ais")
def get_ais_data():
    return get_file_response(os.path.join(BASE_DIR, 'AIS_map', 'ais.json'))

@router.get("/api/ais/bbox")
def get_ais_bbox(glider_name: str, min_lat: float, max_lat: float, min_lon: float, max_lon: float):
    """
    지정한 BBox 영역 및 인접 버킷의 AIS 데이터를 조회합니다.
    """
    try:
        data = get_ais_from_bbox(glider_name, min_lat, max_lat, min_lon, max_lon)
        return {"status": "success", "count": len(data), "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ================================================================
# 반자동화 아카이빙 API
# ================================================================

def _extract_mission_dates(glider_name: str, source_dir: str) -> tuple[str, str]:
    """
    미션의 시작일과 종료일을 YYYYMMDD 형식으로 추출한다.

    1차: WebData/{glider}_log.json 내부 log_data의 timestamp 필드를 파싱.
    2차(Fallback): source_dir 내 파일들의 생성/수정 메타데이터 사용.
    """
    # ── 1차: JSON 기반 날짜 추출 ──
    try:
        log_json_path = os.path.join(
            get_webdata_dir(glider_name), f'{glider_name}_log.json'
        )
        if os.path.exists(log_json_path):
            with open(log_json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)

            log_entries = data.get('log_data', [])
            if log_entries:
                timestamps = []
                for entry in log_entries:
                    ts = entry.get('timestamp')
                    if ts:
                        try:
                            dt = datetime.fromisoformat(ts)
                            timestamps.append(dt)
                        except (ValueError, TypeError):
                            continue

                if timestamps:
                    first_date = min(timestamps).strftime('%Y%m%d')
                    last_date = max(timestamps).strftime('%Y%m%d')
                    logger.info(
                        f'[Archive] JSON 날짜 파싱 성공: {first_date} ~ {last_date}'
                    )
                    return first_date, last_date
    except Exception as e:
        logger.warning(f'[Archive] JSON 날짜 파싱 실패, Fallback 진행: {e}')

    # ── 2차: 파일 메타데이터 Fallback ──
    logger.info('[Archive] 파일 메타데이터 기반 날짜 추출 시도...')
    oldest_time = None
    newest_time = None

    for root, dirs, files in os.walk(source_dir):
        for fname in files:
            fpath = os.path.join(root, fname)
            try:
                mtime = os.path.getmtime(fpath)
                ctime = os.path.getctime(fpath)
                file_oldest = min(mtime, ctime)
                file_newest = max(mtime, ctime)

                if oldest_time is None or file_oldest < oldest_time:
                    oldest_time = file_oldest
                if newest_time is None or file_newest > newest_time:
                    newest_time = file_newest
            except OSError:
                continue

    if oldest_time and newest_time:
        first_date = datetime.fromtimestamp(oldest_time).strftime('%Y%m%d')
        last_date = datetime.fromtimestamp(newest_time).strftime('%Y%m%d')
        logger.info(
            f'[Archive] 메타데이터 날짜 추출 성공: {first_date} ~ {last_date}'
        )
        return first_date, last_date

    # 최종 Fallback: 오늘 날짜
    today = datetime.now().strftime('%Y%m%d')
    logger.warning(f'[Archive] 날짜 추출 완전 실패, 오늘 날짜 사용: {today}')
    return today, today


@router.post("/api/archive/{glider_name}")
def archive_glider_mission(glider_name: str):
    """
    운용 중인 글라이더 미션 데이터를 아카이브로 이관한다.

    Source: config.get_glider_dir(glider_name)  →  backend/gliders/{glider}
    Dest:   ARCHIVE_ROOT/{glider}_{start}_{end}  (Flat 구조)

    File Lock 방어를 위한 롤백 로직을 포함한다.
    """
    source_dir = get_glider_dir(glider_name)

    # ── 1. 원본 존재 검증 ──
    if not os.path.isdir(source_dir):
        raise HTTPException(
            status_code=404,
            detail=f"글라이더 데이터 디렉토리를 찾을 수 없습니다: {source_dir}"
        )

    # ── 2. 날짜 파싱 및 목적지 경로 생성 ──
    first_date, last_date = _extract_mission_dates(glider_name, source_dir)
    archive_folder_name = f'{glider_name}_{first_date}_{last_date}'
    dest_dir = os.path.join(get_archive_dir(), archive_folder_name)

    # 목적지 중복 방어
    if os.path.exists(dest_dir):
        raise HTTPException(
            status_code=409,
            detail=f"동일 이름의 아카이브가 이미 존재합니다: {archive_folder_name}"
        )

    # ── 3. 목적지 상위 디렉토리 생성 ──
    os.makedirs(get_archive_dir(), exist_ok=True)

    # ── 4. 원자적 이동 + 롤백 ──
    try:
        logger.info(
            f'[Archive] 이동 시작: {source_dir} → {dest_dir}'
        )
        shutil.move(source_dir, dest_dir)
        logger.info(f'[Archive] 이동 완료: {dest_dir}')

        # ── 5. 동기식 전처리 파이프라인 ──
        logger.info(f'[Archive] 전처리 파이프라인 시작: {glider_name}')
        
        # 5-1. WPT 압축
        waypoints_path = os.path.join(dest_dir, 'WebData', f'{glider_name}_waypoints.json')
        if os.path.exists(waypoints_path):
            with open(waypoints_path, 'r', encoding='utf-8') as f:
                wpt_data = json.load(f)
                
            comp_wpt = filter_waypoints_by_heading(wpt_data)
            
            filtered_wpt_path = os.path.join(dest_dir, 'WebData', 'filtered_waypoints.json')
            with open(filtered_wpt_path, 'w', encoding='utf-8') as f:
                json.dump(comp_wpt, f, ensure_ascii=False)
            logger.info(f'[Archive] WPT 압축 완료: {len(wpt_data)} -> {len(comp_wpt)} points')

        # 5-2. Sensor 요약본 생성
        sensor_web_path = os.path.join(dest_dir, 'WebData', f'{glider_name}_sensor_web.json')
        if os.path.exists(sensor_web_path):
            with open(sensor_web_path, 'r', encoding='utf-8') as f:
                sensor_data = json.load(f)
                
            summary_data = {}
            if 'sci_data' in sensor_data:
                for date_key, daily_data in sensor_data['sci_data'].items():
                    pres_vals = daily_data.get('pres', [])
                    den_vals = daily_data.get('density', [])
                    
                    if not isinstance(pres_vals, list):
                        pres_vals = [pres_vals]
                    if not isinstance(den_vals, list):
                        den_vals = [den_vals]
                    
                    # pres <= 5.0 인 density 추출
                    surface_densities = [
                        den for p, den in zip(pres_vals, den_vals) 
                        if p is not None and den is not None and p <= 5.0
                    ]
                    
                    if surface_densities:
                        summary_data[date_key] = {
                            'density_avg': sum(surface_densities) / len(surface_densities),
                            'density_min': min(surface_densities),
                            'density_max': max(surface_densities)
                        }
                        
            summary_path = os.path.join(dest_dir, 'WebData', 'sensor_daily_summary.json')
            with open(summary_path, 'w', encoding='utf-8') as f:
                json.dump(summary_data, f, ensure_ascii=False)
            logger.info(f'[Archive] Sensor 요약본 생성 완료: {summary_path}')
            
        logger.info('[Archive] 전처리 파이프라인 전체 과정 성공적 완료')

    except Exception as move_error:
        # 롤백: 부분적으로 복사된 목적지 찌꺼기 제거
        logger.error(
            f'[Archive] 이동 실패, 롤백 수행: {move_error}'
        )
        if os.path.exists(dest_dir):
            try:
                shutil.rmtree(dest_dir, ignore_errors=True)
                logger.info('[Archive] 롤백 완료: 목적지 찌꺼기 삭제')
            except Exception as rollback_error:
                logger.critical(
                    f'[Archive] 롤백마저 실패! 수동 개입 필요: {rollback_error}'
                )

        raise HTTPException(
            status_code=500,
            detail=(
                f"아카이브 이동 중 에러 발생 (롤백 완료). "
                f"원인: {type(move_error).__name__}: {move_error}"
            )
        )

    return {
        "status": "success",
        "message": f"{glider_name} 미션 아카이브 완료",
        "archive_path": archive_folder_name,
        "period": f"{first_date} ~ {last_date}"
    }

# ================================================================
# 아카이브 온디맨드 스냅샷 API
# ================================================================

@router.get("/api/archive/snapshot/{glider_name}/{mission_folder}")
def get_archive_snapshot_file(glider_name: str, mission_folder: str, file: str):
    """
    아카이브된 특정 미션 폴더 내의 정적 데이터(전처리/수집결과물)를 서빙한다.
    - file: 'filtered_waypoints.json', 'sensor_daily_summary.json', 'glider_track.json' 등 파일명
    """
    # 보안 강화를 위해 디렉터리 탐색(..) 등 조작 방지
    safe_filename = os.path.basename(file)
    target_path = os.path.join(get_archive_dir(), mission_folder, 'WebData', safe_filename)
    
    if os.path.exists(target_path):
        return FileResponse(target_path, media_type="application/json")
    
    raise HTTPException(status_code=404, detail=f"요청한 스냅샷 파일이 없습니다: {safe_filename}")

@router.get("/api/archive/snapshot/{glider_name}/{mission_folder}/sensor")
def get_archive_snapshot_sensor(glider_name: str, mission_folder: str, date: str):
    """
    아카이브된 특정 미션에서 특정 날짜(date)의 센서 데이터만 동적으로 로드 및 파싱하여 반환.
    - 온디맨드 메모리 컷오프 서빙
    """
    sensor_web_path = os.path.join(get_archive_dir(), mission_folder, 'WebData', f'{glider_name}_sensor_web.json')
    
    if not os.path.exists(sensor_web_path):
        raise HTTPException(status_code=404, detail="해당 글라이더 미션의 센서 데이터가 존재하지 않습니다.")
        
    try:
        with open(sensor_web_path, 'r', encoding='utf-8') as f:
            sensor_data = json.load(f)
            
        if 'sci_data' in sensor_data and date in sensor_data['sci_data']:
            return {"date": date, "data": sensor_data['sci_data'][date]}
        else:
            raise HTTPException(status_code=404, detail=f"요청한 날짜({date})의 센서 데이터가 존재하지 않습니다.")
            
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"센서 스냅샷 파싱 중 에러 발생: {str(e)}")

