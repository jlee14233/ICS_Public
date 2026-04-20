"""
맵 통합 모듈 - map_integrator.py

모든 글라이더의 GPS 이력, AIS 선박 데이터, 기상 정보를 
하나의 JSON(map_data.json)으로 통합하여 웹 프론트엔드에 제공합니다.

출력: {webdata_dir}/map_data.json
"""

import os
import sys
import json
import math
import glob
import logging
import re
from datetime import datetime, timedelta

# config 참조를 위해 backend 경로 추가
backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from backend_config import (
    GLIDER_NAME, DESKTOP_PATH, BASE_DIR, 
    AIS_DATA_PATH, MAP_DEFAULT_VIEW_DAYS, get_webdata_dir
)
from shapely.geometry import Polygon as ShapelyPolygon
from shapely.ops import unary_union
from shapely import coverage_union

logger = logging.getLogger(__name__)


class MapIntegrator:
    """
    모든 글라이더의 맵 데이터를 통합하여 JSON으로 생성합니다.
    """

    def __init__(self, output_dir=None):
        self.output_dir = output_dir or os.path.join(BASE_DIR, 'AIS_map')
        os.makedirs(self.output_dir, exist_ok=True)

    # ============================================================
    # 공개 API
    # ============================================================
    def generate_map_data(self, target_glider=None):
        """
        각 글라이더의 맵 데이터를 생성하고 분할 JSON으로 저장합니다.
        - backend/{glider}/WebData/glider_track.json
        - backend/AIS_map/ais.json
        Returns: 저장된 AIS JSON 파일 경로
        """
        all_glider_names = self._get_all_gliders()
        glider_names = [target_glider] if target_glider else all_glider_names
        
        logger.info(f"맵 데이터 분할 생성 대상 글라이더: {glider_names}")

        for name in glider_names:
            try:
                glider_data = self._build_glider_data(name)
                if glider_data:
                    from backend_config import get_webdata_dir
                    
                    # 1. glider_track.json 생성
                    glider_webdata_dir = get_webdata_dir(name)
                    os.makedirs(glider_webdata_dir, exist_ok=True)
                    track_path = os.path.join(glider_webdata_dir, "glider_track.json")
                    
                    track_data = {
                        "name": glider_data["name"],
                        "track_history": glider_data.get("track_history", []),
                        "past_track_history": glider_data.get("past_track_history", []),
                        "latest_position": glider_data.get("latest_position"),
                        "waypoints": glider_data.get("waypoints"),
                        "metadata": {
                            "generated_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
                        }
                    }
                    with open(track_path, 'w', encoding='utf-8') as f:
                        json.dump(track_data, f, ensure_ascii=False)
                    logger.info(f"  [{name}] 궤적 데이터 분할 저장: {track_path}")

            except Exception as e:
                logger.warning(f"  [{name}] 맵 데이터 분할 생성 실패: {e}")

        # 2. 전역 통합 AIS 단일 데이터 수집 (AIS는 항상 통합본 1개가 필요하므로 전체 리스트 넘김)
        ais_results = self._generate_global_ais_data(all_glider_names)

        # 3. AIS 전역 데이터 저장
        ais_dir = os.path.join(BASE_DIR, "AIS_map")
        os.makedirs(ais_dir, exist_ok=True)
        ais_path = os.path.join(ais_dir, "ais.json")
        ais_data_full = {
            "gliders": ais_results,
            "metadata": {
                "generated_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
            }
        }
        with open(ais_path, 'w', encoding='utf-8') as f:
            json.dump(ais_data_full, f, ensure_ascii=False)
        
        logger.info(f"✅ 통합 AIS 데이터 분할 저장 완료: {ais_path}")
        return ais_path

    # ============================================================
    # 글라이더 목록
    # ============================================================
    def _get_all_gliders(self):
        """
        맵에 표시할 글라이더 목록 수집.
        1) AIS_DATA_PATH 하위 폴더명
        2) backend 하위 글라이더 폴더명
        3) 기본 GLIDER_NAME 보장
        """
        gliders = set()

        # AIS 폴더에서 글라이더명 수집
        if os.path.isdir(AIS_DATA_PATH):
            for entry in os.listdir(AIS_DATA_PATH):
                entry_path = os.path.join(AIS_DATA_PATH, entry)
                if os.path.isdir(entry_path) and entry.startswith('kg_'):
                    gliders.add(entry)

        # backend 폴더에서 글라이더명 수집
        for entry in os.listdir(BASE_DIR):
            entry_path = os.path.join(BASE_DIR, entry)
            if os.path.isdir(entry_path) and entry.startswith('kg_'):
                # WebData 하위가 있으면 실제 글라이더 폴더
                if os.path.isdir(os.path.join(entry_path, 'WebData')):
                    gliders.add(entry)

        # 기본 글라이더 보장
        if isinstance(GLIDER_NAME, list):
            gliders.update(GLIDER_NAME)
        else:
            gliders.add(GLIDER_NAME)

        return sorted(gliders)

    # ============================================================
    # 글라이더별 데이터 구축
    # ============================================================
    def _build_glider_data(self, glider_name):
        """단일 글라이더의 통합 맵 데이터를 구축합니다."""
        data = {"name": glider_name}

        # 1. GPS 이력 추출 (3일 기준 분할)
        track_history, past_track_history = self._extract_gps_history(glider_name)
        data["track_history"] = track_history
        data["past_track_history"] = past_track_history

        # 2. 최신 위치 & 방향 계산
        data["latest_position"] = self._get_latest_position(track_history)

        # 3. 웨이포인트 (WPT1, WPT2 - 경도 최소/최대)
        data["waypoints"] = self._extract_waypoints(glider_name)

        return data

    # ============================================================
    # GPS 이력 추출 (AIS HTML 파일에서)
    # ============================================================
    def _extract_gps_history(self, glider_name):
        """
        글라이더 LOG 파일에서 직접 GPS 이력을 추출합니다. (HTML 스크래핑 아키텍처 완전 제거)
        파일명에서 타임스탬프(+9 KST)를 추출하고, 내부 텍스트에서 NMEA 위경도를 파싱합니다.
        
        Returns: [{"lat": ..., "lon": ..., "timestamp": "..."}]
        """
        log_dir = os.path.join(BASE_DIR, 'gliders', glider_name, 'LOG')
        if not os.path.isdir(log_dir):
            logger.warning(f"  [{glider_name}] LOG 디렉토리 없음: {log_dir}")
            return [], []

        log_files = sorted(glob.glob(os.path.join(log_dir, '*.log')))
        if not log_files:
            logger.warning(f"  [{glider_name}] LOG 파일 없음")
            return [], []

        gps_points = []
        
        # 파일명에서 날짜 부분 추출
        ts_pattern = re.compile(r'_(\d{8}T\d{6})_')
        from src.utils.glider_utils import geo2glider

        for log_file in log_files:
            basename = os.path.basename(log_file)
            
            # 파일명에서 원본 UTC 타임스탬프 추출
            ts_match = ts_pattern.search(basename)
            if not ts_match:
                continue
            
            try:
                # 추출한 문자열을 UTC datetime으로 변환
                dt_utc = datetime.strptime(ts_match.group(1), '%Y%m%dT%H%M%S')
                # KST 시간으로 +9시간 더하기 (User Requirement)
                dt_kst = dt_utc + timedelta(hours=9)
                timestamp = dt_kst.strftime('%Y-%m-%dT%H:%M:%S')
            except ValueError:
                continue

            parsed_coord = None
            try:
                with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        if line.startswith('GPS Location:'):
                            # Invalid나 TooFar 에러 데이터가 포함된 라인은 즉시 버림
                            if 'Invalid' in line or 'TooFar' in line:
                                continue
                            
                            # 정규식으로 NMEA 좌표 (예: 3450.1234 N 12845.6789 E) 숫자부 추출
                            match = re.search(r'GPS Location:\s*([0-9.]+)[^0-9.]+([0-9.]+)', line)
                            if match:
                                nmea_lat = float(match.group(1))
                                nmea_lon = float(match.group(2))
                                
                                # 강력한 예외 처리 (Validation): 실제 지구상 좌표 범위를 체크
                                if not (0.0 < nmea_lat <= 9000.0) or not (0.0 < nmea_lon <= 18000.0):
                                    continue
                                
                                # 십진수 위경도 디코딩 통과
                                loc = geo2glider(nmea_lon, nmea_lat, fmt='m')
                                
                                # geo2glider가 리턴하는 배열 형태에서 float 스칼라 추출 보장
                                dd_lat = float(loc['yd'][0])
                                dd_lon = float(loc['xd'][0])
                                
                                parsed_coord = {
                                    "lat": round(dd_lat, 6),
                                    "lon": round(dd_lon, 6),
                                    "timestamp": timestamp
                                }
                                gps_points.append(parsed_coord)
                                break # 파일당 가장 상위에 있는 성공적인 GPS 좌표만 캡처
            except Exception as e:
                logger.debug(f"  LOG GPS 파싱 오류 ({basename}): {e}")
                
        logger.info(f"  [{glider_name}] LOG 파일에서 GPS 순수 파싱 {len(gps_points)}점 수집 (KST 변환 완료)")
        
        # 시간순 정렬 (과거 -> 최신)
        gps_points.sort(key=lambda x: x['timestamp'])
        
        track_history = []
        past_track_history = []
        
        if gps_points:
            try:
                max_dt = datetime.fromisoformat(gps_points[-1]['timestamp'])
                # 기준일에 기반한 동적 분할
                cutoff_dt = max_dt - timedelta(days=MAP_DEFAULT_VIEW_DAYS)
                for p in gps_points:
                    p_dt = datetime.fromisoformat(p['timestamp'])
                    if p_dt >= cutoff_dt:
                        track_history.append(p)
                    else:
                        past_track_history.append(p)
            except ValueError:
                track_history = gps_points
                
        return track_history, past_track_history


    # ============================================================
    # 최신 위치 & 방향 계산
    # ============================================================
    def _get_latest_position(self, track_history):
        """
        GPS 이력의 마지막 좌표와 heading(방향각) 계산.
        """
        if not track_history:
            return None

        latest = track_history[-1]
        result = {
            "lat": latest["lat"],
            "lon": latest["lon"],
            "timestamp": latest["timestamp"],
            "heading": 0.0
        }

        # 마지막 2개 좌표로 heading 계산
        if len(track_history) >= 2:
            prev = track_history[-2]
            heading = self._calculate_heading(
                prev["lat"], prev["lon"],
                latest["lat"], latest["lon"]
            )
            result["heading"] = round(heading, 1)

        return result

    @staticmethod
    def _calculate_heading(lat1, lon1, lat2, lon2):
        """두 좌표 간의 방위각(degree) 계산 (0=북, 90=동, 180=남, 270=서)"""
        lat1_r = math.radians(lat1)
        lat2_r = math.radians(lat2)
        dlon = math.radians(lon2 - lon1)

        x = math.sin(dlon) * math.cos(lat2_r)
        y = math.cos(lat1_r) * math.sin(lat2_r) - \
            math.sin(lat1_r) * math.cos(lat2_r) * math.cos(dlon)

        bearing = math.degrees(math.atan2(x, y))
        return (bearing + 360) % 360

    # ============================================================
    # 웨이포인트 (WPT1 최소경도, WPT2 최대경도)
    # ============================================================
    def _extract_waypoints(self, glider_name):
        """
        waypoints JSON에서 경도 기준 최소(WPT1), 최대(WPT2)만 반환.
        """
        webdata_dir = get_webdata_dir(glider_name)
        wpt_file = os.path.join(webdata_dir, f"{glider_name}_waypoints.json")
        
        if not os.path.isfile(wpt_file):
            logger.debug(f"  [{glider_name}] waypoints 파일 없음")
            return None

        try:
            with open(wpt_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            wpts = data.get('waypoints', [])
            if len(wpts) < 2:
                return None

            # 유효한 WPT 필터 (0이 아닌 좌표)
            valid_wpts = [w for w in wpts if w.get('lat', 0) != 0 and w.get('lon', 0) != 0]
            if len(valid_wpts) < 2:
                return None

            # 경도 기준 최소/최대
            wpt_min = min(valid_wpts, key=lambda w: w['lon'])
            wpt_max = max(valid_wpts, key=lambda w: w['lon'])

            return {
                "wpt1": {"lat": round(wpt_min['lat'], 6), "lon": round(wpt_min['lon'], 6)},
                "wpt2": {"lat": round(wpt_max['lat'], 6), "lon": round(wpt_max['lon'], 6)}
            }
        except Exception as e:
            logger.warning(f"  [{glider_name}] WPT 파싱 오류: {e}")
            return None

    # ============================================================
    # AIS 최신 데이터 읽기 (HTML 파싱)
    # ============================================================
    def optimize_ais_vessels(self, vessels):
        """
        AIS 격자 폴리곤 병합 (Dissolve).
        같은 색상(vmtc 등급)이면서 서로 맞닿아 있는 폴리곤을 하나의 거대한 다각형으로 합쳐서 렌더링 랙을 줄입니다.
        """
        color_groups = {"green": [], "yellow": [], "orange": [], "red": []}
        
        for v in vessels:
            vmtc = v["vmtc"]
            poly = ShapelyPolygon(v["box"])
            
            # 소수점 오차로 인해 병합 시 빈틈이 생기는 것을 막기 위해 미세하게 영역 확장
            poly = poly.buffer(0.0001, join_style=2) 
            
            if vmtc < 8:
                color_groups["green"].append(poly)
            elif vmtc < 15:
                color_groups["yellow"].append(poly)
            elif vmtc < 22:
                color_groups["orange"].append(poly)
            else:
                color_groups["red"].append(poly)
                
        optimized_vessels = []
        # 프론트엔드의 _getVesselColor 함수가 올바른 색상을 반환하도록 유도하는 임의의 대표값
        vmtc_mapping = {"green": 1, "yellow": 10, "orange": 18, "red": 25} 
        
        # 같은 등급의 다각형들을 병합
        for color, polys in color_groups.items():
            if not polys: 
                continue

            # unary_union 대신 격자 병합에 극단적으로 최적화된 coverage_union 사용
            merged = unary_union(polys)
            merged = merged.buffer(0.0001, join_style=2).buffer(-0.0001, join_style=2)
            geoms = [merged] if merged.geom_type == 'Polygon' else merged.geoms
            
            for idx, g in enumerate(geoms):
                # 내부를 채우는 불필요한 선들을 모두 없애고 가장 바깥쪽 외곽선 좌표만 추출
                coords = list(g.exterior.coords)
                
                optimized_vessels.append({
                    "grid_id": f"merged_{color}_{idx}",
                    "lat": round(coords[0][0], 4), 
                    "lon": round(coords[0][1], 4),
                    "vmtc": vmtc_mapping[color],
                    "density": 0.0,
                    # 프론트엔드에서 읽을 수 있게 다시 이중 리스트 형태로 변환
                    "box": [[round(lat, 4), round(lon, 4)] for lat, lon in coords] 
                })
                
        return optimized_vessels

    def _generate_global_ais_data(self, glider_names):
        """
        [최적화 완료 데드코드 무력화]
        프론트엔드 BBox API 동적 호출로 렌더링을 완전히 위임하였기에,
        서버 사이드의 무거운 전체 폴리곤 병합 연산을 비활성화하고
        CPU/디스크 I/O 리소스를 극단적으로 절약합니다.
        빈 스키마만 유지하여 JSON 파이프라인 파싱 에러를 방어합니다.
        """
        logger.info("  통합 AIS는 BBox API 통신으로 전환되어 무거운 전체 병합 연산을 생략합니다.")
        
        # 생성 일시(KST 변환)
        ais_timestamp = (datetime.utcnow() + timedelta(hours=9)).strftime('%Y-%m-%dT%H:%M:%S')

        # 즉시 빈 배열의 안전한 더미 데이터 반환
        return [{
            "name": "Global_AIS_Latest",
            "ais": {
                "timestamp": ais_timestamp,
                "vessels": []
            }
        }]


# ============================================================
# 단독 실행
# ============================================================
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
    
    integrator = MapIntegrator()
    output = integrator.generate_map_data()
    print(f"\n맵 데이터 저장 완료: {output}")
    
    # 결과 요약 출력
    with open(output, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    for g in data['gliders']:
        print(f"  [{g['name']}] GPS: {len(g.get('track_history', []))}점, "
              f"WPT: {'있음' if g.get('waypoints') else '없음'}, "
              f"AIS: {len(g.get('ais', {}).get('vessels', []))}격자")

