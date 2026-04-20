import os
import asyncio
import logging
from datetime import datetime
from playwright.async_api import async_playwright

import sys, os
root_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if root_path not in sys.path:
    sys.path.append(root_path)

import config
# ==============================================================================
# [보안 처리됨] 포트폴리오 최적화로 인해 아래 시각화 및 항해용 핵심 모듈들은 제외되었습니다.
# 각 모듈이 아키텍처 상 수행하는 역할은 다음과 같습니다:
#
# 1. AIS_map_generator: 폴리곤 그래픽 엔진 기반 선박 자동 식별 장치 충돌 회피 알고리즘 시각화
# 2. weather_api: 해상 기상(open-meteo 등) 실시간 연동 모듈 (비독점적이나 내부 연동 규칙 보호)
# 3. compass (glider_GPS_point): WGS84 좌표계에서의 글라이더 진방향 추정 및 웨이포인트(WPT) 렌더링 로직
# ==============================================================================
# import AIS_map_generator
# import weather_api
# from compass import glider_GPS_point

logger = logging.getLogger(__name__)

def get_region(lat, lon):
    """
    위도, 경도를 기반으로 영역을 반환합니다.
    Jeju: N 30.5 ~ 33.5, E 123.5 ~ 128.5
    Eastsea: N 35.5 ~ 38.5, E 128.5 ~ 133.5
    Others: 그 외
    """
    if lat is None or lon is None:
        return "Others"

    if 30.5 <= lat <= 33.5 and 123.5 <= lon <= 128.5:
        return "Jeju"
    elif 35.5 <= lat <= 38.5 and 128.5 <= lon <= 133.5:
        return "Eastsea"
    else:
        return "Others"

async def capture_screenshot(html_path, output_path):
    """
    HTML 파일을 열어 스크린샷을 찍습니다.
    """
    try:
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()
            
            # 로컬 파일 URL
            file_url = f"file://{os.path.abspath(html_path)}"
            await page.goto(file_url, wait_until="load", timeout=60000)
            
            # 지도가 완전히 로드될 때까지 대기 (필요시 조정)
            await page.wait_for_timeout(3000) 
            
            await page.screenshot(path=output_path, full_page=True)
            await browser.close()
            return True
    except Exception as e:
        logger.error(f"스크린샷 캡처 중 오류: {e}")
        return False

async def process_glider_ais(glider_name):
    """
    글라이더의 AIS 지도를 생성하고 스크린샷을 찍습니다.
    1. GPS 조회
    2. Windy API 기상 데이터 조회
    3. 폴더 생성
    4. HTML 지도 생성 (기상 정보 포함)
    5. 스크린샷 생성
    6. 결과 반환 (HTML 경로, 이미지 경로)
    """
    logger.info(f"[{glider_name}] AIS 지도 처리 시작")

    # 1. GPS 조회
    lat, lon = await glider_GPS_point(glider_name)
    if lat is None or lon is None:
        logger.warning(f"[{glider_name}] GPS 정보를 가져올 수 없습니다.")
        return None, None

    # 2. weather data 호출 (활성화)
    weather_info = {
        'lat': lat,
        'lon': lon,
        'ts': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    
    success_weather, data = await weather_api.get_point_forecast(lat, lon)
    if success_weather:
        weather_info.update(data)
        logger.info(f"[{glider_name}] Weather API 데이터 수신 성공: {data}")
    else:
        logger.warning(f"[{glider_name}] Weather API 데이터 수신 실패: {data}")
        weather_info['error'] = "Weather API Fail"

    # 3. 영역 결정 및 폴더 생성
    region = get_region(lat, lon)
    
    # AIS 폴더
    ais_root = os.path.join(config.DESKTOP_PATH, "AIS")
    if not os.path.exists(ais_root):
        os.makedirs(ais_root)
        
    # 영역 폴더
    region_folder = os.path.join(ais_root, region)
    if not os.path.exists(region_folder):
        os.makedirs(region_folder)
        
    # 글라이더 폴더
    glider_folder = os.path.join(region_folder, glider_name)
    if not os.path.exists(glider_folder):
        os.makedirs(glider_folder)

    # 4. HTML 지도 생성
    now = datetime.now()
    timestamp = now.strftime("%y%m%d_%H%M%S") # YYMMDD_HHMMSS
    html_filename = f"{timestamp}_{region}_{glider_name}_AIS_map.html"
    html_path = os.path.join(glider_folder, html_filename)
    
    # 지도 생성 실행 (glider_info 전달)
    success = AIS_map_generator.AIS_map_generator(
        save_path=html_path,
        center_lat=lat,
        center_lon=lon,
        zoom=10,
        glider_pos=(lat, lon),
        glider_name=glider_name,
        glider_info=weather_info
    )
    
    if not success:
        logger.error(f"[{glider_name}] 지도 생성 실패")
        return None, None

    # 5. 스크린샷 생성
    image_filename = f"{timestamp}_{region}_{glider_name}_AIS_map.png"
    image_path = os.path.join(glider_folder, image_filename)
    
    screenshot_success = await capture_screenshot(html_path, image_path)
    
    if not screenshot_success:
        logger.error(f"[{glider_name}] 스크린샷 생성 실패")
        return html_path, None

    logger.info(f"[{glider_name}] AIS 처리 완료. HTML: {html_path}, IMG: {image_path}")
    return html_path, image_path

if __name__ == "__main__":
    asyncio.run(process_glider_ais("kg_1167"))