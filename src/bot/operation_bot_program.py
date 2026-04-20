import asyncio
import os
import sys
import discord
from discord.ext import tasks
import subprocess
import signal
import platform
import logging
import threading
import websockets
import json

# 루트 환경설정 파일(config.py) 참조를 위해 상위 두 단계 폴더(ICS_Public) 추가
root_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if root_path not in sys.path:
    sys.path.append(root_path)

import config
from log_manager import download_logs_for_glider, new_glider_sensing, log_update, download_from_glider_files, sync_files_to_nas, archive_old_nas_mission
import api_map_manager as ais_manager

# ==============================================================================
# [보안 처리됨] 실행 제어 봇 내에서 동적으로 로드되는 일부 스크립트는 
# 내부 보안 규정에 따라 포트폴리오(Public)에서 제외되었습니다.
# - glider_wake_time: 부상 예상 로직 등
# - log_manager 내 일부 내부망 종속 함수 등
# ==============================================================================

# 백엔드 환경 설정 (src/backend) 참조용
_backend_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'backend')
if _backend_path not in sys.path:
    sys.path.append(_backend_path)

import backend_config
BACKEND_ACTIVE_GLIDERS = backend_config.ACTIVE_GLIDERS

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(config.LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Discord 봇 설정
intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)

# 대기 중인 작업 관리용 딕셔너리
pending_tasks = {}

# 이중 실행 방어 (Race Condition Guard)
_processing_gliders = set()   # 현재 파싱 중인 글라이더 추적
_processing_lock = threading.Lock()  # set 접근 보호용 락

async def cleanup_chrome_processes():
    """남아있는 Chrome 프로세스를 정리하는 함수"""
    try:
        if platform.system() == "Windows":
            # Windows에서 Chrome 프로세스 종료
            result = subprocess.run(
                ["taskkill", "/f", "/im", "chrome.exe"], 
                capture_output=True, 
                text=True
            )
        else:
            # Linux/Mac에서 Chrome 프로세스 종료
            result = subprocess.run(
                ["pkill", "-f", "chrome"], 
                capture_output=True, 
                text=True
            )
            
        if result.returncode == 0:
            logger.info("✅ Chrome 프로세스 정리 완료")
        else:
            logger.debug("ℹ️ 종료할 Chrome 프로세스가 없습니다.")
                
    except Exception as e:
        logger.error(f"❌ Chrome 프로세스 정리 중 오류: {e}")

async def schedule_log_update(glider_name, event_type='submerged'):
    """
    Submerged 이벤트 발생 5분 후 로그 업데이트 실행
    - 모든 글라이더: SFMC에서 로그 다운로드 → 통합관제시스템 업로드
    - NAS 대상 글라이더: 추가로 from-glider 파일 다운로드 및 NAS 동기화
      (config.NAS_TARGET_SERVER에 지정된 서버의 글라이더)
    """
    try:
        await asyncio.sleep(5 * 60)  # 5분 대기
        logger.info(f"[SCHEDULE] {glider_name} 로그 업데이트 실행 ({event_type})")
        
        # is_nas_target_glider 함수가 config.NAS_TARGET_SERVER를 참조하여 판단
        from log_manager import is_nas_target_glider
        
        # 1. SFMC에서 LOG 파일 다운로드 (모든 글라이더)
        await download_logs_for_glider(glider_name, config.DESKTOP_PATH, config.BOT_PATH)
        
        # 2. 모든 다운로드 대상 글라이더의 from-glider 파일도 다운로드 (최신 파일만)
        await download_from_glider_files(glider_name, config.DESKTOP_PATH)
        
        # 3. 모든 글라이더: 통합관제시스템 업로드
        new_glider_sensing()
        log_update()
        
        # 4. NAS 대상 글라이더: 과거 미션 확인 및 압축 → NAS 동기화
        if is_nas_target_glider(glider_name):
            await archive_old_nas_mission(glider_name)
            await sync_files_to_nas(glider_name, event_type)
            
        # 5. control-room 파이프라인 연계 실행 (glider_processor가 전체 처리)
        #    Race Condition Guard: 이미 파싱 중이면 스킵
        with _processing_lock:
            if glider_name in _processing_gliders:
                logger.warning(f"[PIPELINE] {glider_name} 이미 파싱 중 → 파이프라인 스킵")
                return
            _processing_gliders.add(glider_name)
        
        try:
            current_dir = os.path.dirname(os.path.abspath(__file__))
            backend_dir = os.path.join(os.path.dirname(current_dir), 'backend')
            processor_script = os.path.join(backend_dir, 'glider_processor.py')
            
            logger.info(f"[PIPELINE] {glider_name} 데이터 처리 파이프라인 시작...")
            
            # glider_processor가 sync → convert → summary → figures → map_data 전체 실행
            subprocess.run(["python", processor_script, "--glider", glider_name], check=True, timeout=300)
                            
            logger.info(f"[PIPELINE] {glider_name} 데이터 처리 완료.")
            
            # ── 후처리 1: 부상 예상 시간 업데이트 (파싱 완료 후 최신 사이클 타임 반영) ──
            try:
                import datetime as dt_module
                from glider_wake_time import update_wake_time_prediction
                update_wake_time_prediction(glider_name, event_type, dt_module.datetime.now())
                logger.info(f"[PIPELINE] {glider_name} 부상 예상 시간 업데이트 완료.")
            except Exception as wt_err:
                logger.error(f"[PIPELINE] {glider_name} 부상 예상 시간 업데이트 실패: {wt_err}")
            
            # ── 후처리 2: 프론트엔드 새로고침 (DATA_UPDATED 이벤트 전파) ──
            try:
                import requests
                requests.post(
                    "http://localhost:8000/api/notify-data-updated",
                    json={"glider": glider_name},
                    timeout=5
                )
                logger.info(f"[PIPELINE] {glider_name} 프론트엔드 DATA_UPDATED 알림 전송 완료.")
            except Exception as notify_err:
                logger.error(f"[PIPELINE] {glider_name} DATA_UPDATED 알림 전송 실패: {notify_err}")
            
        except subprocess.TimeoutExpired:
            logger.error(f"[PIPELINE] {glider_name} 파이프라인 타임아웃 (300초 초과) → 강제 종료")
        except subprocess.CalledProcessError as e:
            logger.error(f"[PIPELINE] {glider_name} 연동 스크립트 실행 중 에러 발생: {e}")
        except Exception as e:
            logger.error(f"[PIPELINE] {glider_name} 연동 예측 외 에러 발생: {e}")
        finally:
            with _processing_lock:
                _processing_gliders.discard(glider_name)
        
        # Discord 알림
        channel = client.get_channel(config.CHANNEL_ID_LOGS)
        if channel:
            msg = f"📦 {glider_name} 로그가 업로드 및 control-room 분석 파이프라인 처리가 완료되었습니다."
            if is_nas_target_glider(glider_name):
                msg += f" (NAS 동기화 포함)"
            await channel.send(msg)
            
    except asyncio.CancelledError:
        logger.info(f"[CANCEL] {glider_name} 로그 업데이트 취소")
    except Exception as e:
        logger.error(f"[ERROR] {glider_name} 로그 업데이트 중 오류: {e}")

async def schedule_image_update(glider_name, delay=60):
    try:
        await asyncio.sleep(delay)
        # ais_manager를 사용하여 지도 생성 및 스크린샷 캡처
        html_path, image_path = await ais_manager.process_glider_ais(glider_name)
        
        
        if not html_path and not image_path:
            logger.warning(f"❌ {glider_name} AIS 처리 실패 (파일 없음)")
            return
        
        channel = client.get_channel(config.CHANNEL_ID_IMAGES)
        if channel:
            files_to_send = []
            if html_path and os.path.exists(html_path):
                files_to_send.append(discord.File(html_path))
            if image_path and os.path.exists(image_path):
                files_to_send.append(discord.File(image_path))
                
            if files_to_send:
                await channel.send(files=files_to_send)
                logger.info(f"[SUCCESS] {glider_name} AIS 데이터 업로드 완료")
            else:
                logger.error("[ERROR] 전송할 파일이 존재하지 않습니다.")
        else:
            logger.error("[ERROR] CHANNEL_ID_IMAGES 채널 찾기 실패")
    except asyncio.CancelledError:
        logger.info(f"[CANCEL] {glider_name} 이미지 업데이트 취소됨")
    except Exception as e:
        logger.error(f"[ERROR] {glider_name} 이미지 업데이트 중 오류: {e}")

async def monitor_submerged_events():
    """WebSocket 연결을 모니터링하고 자동 재연결하는 함수"""
    uri = config.WS_URI
    current_retry = 0
    
    while True:
        try:
            logger.info(f"🔄 WebSocket 연결 시도 중... (시도 {current_retry + 1}/{config.MAX_RETRIES})")
            async with websockets.connect(uri, ping_interval=30, ping_timeout=10) as websocket:
                logger.info("✅ WebSocket 연결 성공")
                current_retry = 0  # 성공 시 재시도 카운터 리셋
                
                async for message in websocket:
                    try:
                        event = json.loads(message)
                        glider = event.get("glider")
                        ip = event.get("ip")
                        event_type = event.get("type")
                        
                        if event_type == "submerged":
                            if ip and (ip.endswith(".com") or "webbresearch" in ip):
                                continue
                            if glider not in pending_tasks:
                                logger.info(f"[SUBMERGED] {glider} @ {ip} → Not Connected")
                                log_task = asyncio.create_task(schedule_log_update(glider, 'submerged'))
                                pending_tasks[glider] = {"log": log_task}
                                
                        elif event_type == "surfaced":
                            if glider in pending_tasks:
                                logger.info(f"[SURFACED] {glider} @ {ip} → Connected (예약된 작업 취소)")
                                for task in pending_tasks[glider].values():
                                    task.cancel()
                                del pending_tasks[glider]
                            
                            # is_nas_target_glider 함수 import
                            from log_manager import is_nas_target_glider
                            
                            # Secondary 연결이 아닐 경우에만 AIS 지도 업데이트 실행
                            is_secondary = ip and (ip.endswith(".com") or "webbresearch" in ip)
                            if not is_secondary:
                                logger.info(f"[SURFACED] {glider} Primary Connection → AIS 지도 업데이트")
                                
                                # AIS 지도 업데이트 (30초 후)
                                # NAS 동기화는 이미 Submerged 시점(5분 후)에 처리됨
                                asyncio.create_task(schedule_image_update(glider, delay=30))
                            else:
                                logger.info(f"[SURFACED] {glider} Secondary 연결 → AIS 업데이트 건너뜀")
                                
                    except json.JSONDecodeError as e:
                        logger.error(f"❌ JSON 파싱 오류: {e}")
                        continue
                    except Exception as e:
                        logger.error(f"❌ 메시지 처리 오류: {e}")
                        continue
                        
        except websockets.exceptions.ConnectionClosedError as e:
            logger.error(f"❌ WebSocket 연결이 끊어졌습니다: {e}")
            current_retry += 1
            if current_retry >= config.MAX_RETRIES:
                logger.error(f"❌ 최대 재시도 횟수({config.MAX_RETRIES})에 도달했습니다. 프로그램을 종료합니다.")
                break
            logger.info(f"⏳ {config.RETRY_DELAY}초 후 재연결을 시도합니다...")
            await asyncio.sleep(config.RETRY_DELAY)
            
        except websockets.exceptions.InvalidURI as e:
            logger.error(f"❌ 잘못된 WebSocket URI: {e}")
            break
            
        except Exception as e:
            logger.error(f"❌ 예상치 못한 오류: {e}")
            current_retry += 1
            if current_retry >= config.MAX_RETRIES:
                logger.error(f"❌ 최대 재시도 횟수({config.MAX_RETRIES})에 도달했습니다. 프로그램을 종료합니다.")
                break
            logger.info(f"⏳ {config.RETRY_DELAY}초 후 재연결을 시도합니다...")
            await asyncio.sleep(config.RETRY_DELAY)

async def periodic_cleanup():
    """정기적인 Chrome 프로세스 정리 (1시간마다)"""
    while True:
        try:
            await asyncio.sleep(3600)  # 1시간 대기
            await cleanup_chrome_processes()
        except asyncio.CancelledError:
            logger.info("정기 정리 작업이 취소되었습니다.")
            break
        except Exception as e:
            logger.error(f"정기 정리 작업 중 오류: {e}")

async def shutdown(signal_name, loop):
    """프로그램 종료 시 정리 작업"""
    logger.info(f"🛑 종료 신호 수신: {signal_name}")
    
    # Chrome 프로세스 정리
    await cleanup_chrome_processes()
    
    # 대기 중인 태스크들 취소
    if hasattr(client, 'websocket_task'):
        client.websocket_task.cancel()
    if hasattr(client, 'cleanup_task'):
        client.cleanup_task.cancel()
    
    # pending_tasks 정리
    for glider, tasks in pending_tasks.items():
        for task in tasks.values():
            task.cancel()
    pending_tasks.clear()
    
    logger.info("✅ 정리 작업 완료")
    loop.stop()

def setup_signal_handlers(loop):
    """시그널 핸들러 설정"""
    try:
        if platform.system() != "Windows":
            # Unix/Linux 시스템에서만 시그널 핸들러 설정
            for sig in (signal.SIGINT, signal.SIGTERM):
                loop.add_signal_handler(
                    sig,
                    lambda s=sig: asyncio.create_task(shutdown(signal.Signals(s).name, loop))
                )
        else:
            # Windows에서는 기본 시그널 핸들러 사용
            def signal_handler(signum, frame):
                asyncio.create_task(shutdown("SIGTERM", loop))
            
            signal.signal(signal.SIGINT, signal_handler)
            signal.signal(signal.SIGTERM, signal_handler)
    except NotImplementedError:
        logger.warning("시그널 핸들러 설정이 지원되지 않습니다. 기본 종료 처리만 사용합니다.")
    except Exception as e:
        logger.warning(f"시그널 핸들러 설정 중 오류: {e}")

@client.event
async def on_ready():
    logger.info(f'Logged on as {client.user}')
    
    # 시작 시 Chrome 프로세스 정리
    await cleanup_chrome_processes()
    
    # WebSocket 모니터링 태스크 시작
    websocket_task = client.loop.create_task(monitor_submerged_events())
    
    # 정기적인 Chrome 프로세스 정리 태스크 시작
    cleanup_task = client.loop.create_task(periodic_cleanup())
    
    # 태스크들을 저장하여 나중에 정리할 수 있도록 함
    client.websocket_task = websocket_task
    client.cleanup_task = cleanup_task

@client.event
async def on_message(message):
    if message.content == "!j":
        if message.channel.id == config.CHANNEL_ID_IMAGES:
            await message.channel.send("🌊 AIS 지도 및 이미지 수동 업데이트를 시작합니다... (Target: kg_1221)")
            # 기본값 kg_1221 사용
            glider_name = 'kg_1221'
            html_path, image_path = await ais_manager.process_glider_ais(glider_name)
            
            if not html_path and not image_path:
                await message.channel.send("❌ AIS 데이터 생성 실패.")
                return
            
            files_to_send = []
            if html_path and os.path.exists(html_path):
                files_to_send.append(discord.File(html_path))
            if image_path and os.path.exists(image_path):
                files_to_send.append(discord.File(image_path))
                
            if files_to_send:
                await message.channel.send(files=files_to_send)
            else:
                await message.channel.send("❌ 전송할 파일이 없습니다.")

# ── Pre-warming: Cold Start 데이터 무결성 검사 ──
def check_and_initialize_data():
    """
    서버 부팅 시 각 글라이더의 필수 WebData JSON 파일 존재 여부를 검사합니다.
    누락된 글라이더 목록을 반환합니다.
    """
    required_suffixes = ['_log.json', '_sensor_web.json', '_performance.json']
    missing_gliders = []
    
    for glider in BACKEND_ACTIVE_GLIDERS:
        webdata_dir = os.path.join(_backend_path, 'gliders', glider, 'WebData')
        for suffix in required_suffixes:
            filepath = os.path.join(webdata_dir, f'{glider}{suffix}')
            if not os.path.exists(filepath):
                missing_gliders.append(glider)
                logger.info(f"[Pre-warming] 누락 감지: {filepath}")
                break  # 하나라도 없으면 해당 글라이더는 초기화 대상
    
    return missing_gliders

def _run_initial_processor(missing_gliders):
    """
    누락된 글라이더의 데이터를 백그라운드에서 순차 파싱합니다.
    daemon 스레드로 실행되므로 메인 루프를 차단하지 않습니다.
    """
    processor_script = os.path.join(_backend_path, 'glider_processor.py')
    
    for glider in missing_gliders:
        # Race Condition Guard
        with _processing_lock:
            if glider in _processing_gliders:
                logger.warning(f"[Pre-warming] {glider} 이미 파싱 중 → 스킵")
                continue
            _processing_gliders.add(glider)
        
        try:
            logger.info(f"[Pre-warming] {glider} 초기 데이터 파싱 시작...")
            subprocess.run(["python", processor_script, "--glider", glider], check=True, timeout=300)
            logger.info(f"[Pre-warming] {glider} 초기 데이터 파싱 완료.")
        except subprocess.TimeoutExpired:
            logger.error(f"[Pre-warming] {glider} 파싱 타임아웃 (300초 초과) → 강제 종료")
        except Exception as e:
            logger.error(f"[Pre-warming] {glider} 파싱 실패: {e}")
        finally:
            with _processing_lock:
                _processing_gliders.discard(glider)
    
    logger.info("[Pre-warming] 모든 초기화 작업 완료.")

# 메인 실행 부분
if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    setup_signal_handlers(loop)
    
    # Cold Start Pre-warming 검사
    missing = check_and_initialize_data()
    if missing:
        logger.info(f"[Pre-warming] 초기화 필요 글라이더: {missing} → 백그라운드 스레드 실행")
        threading.Thread(target=_run_initial_processor, args=(missing,), daemon=True).start()
    else:
        logger.info("[Pre-warming] 모든 데이터 정상 → 초기화 불필요")
    
    try:
        client.run(config.DISCORD_TOKEN_OPERATION)
    except KeyboardInterrupt:
        logger.info("🛑 사용자에 의해 프로그램이 중단되었습니다.")
    except Exception as e:
        logger.error(f"프로그램 실행 중 오류: {e}")
    finally:
        loop.close()
