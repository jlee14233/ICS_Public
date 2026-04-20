import asyncio
import datetime
import os
import logging

from collections import deque
import discord
import uvicorn
from discord.ext import commands, tasks
from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware

# ==============================================================================
# [보안 처리됨] 외부망(Public Portfolio) 공개를 위해 아래 내부 핵심 모듈들은 제외되었습니다.
# 각 모듈이 아키텍처 상 수행하는 역할은 다음과 같습니다:
#
# 1. glider_connected_parsing: 제조사 서버(SFMC)와의 소켓 통신을 통해 실시간 상태(Submerged/Surfaced) 알람 수신
# 2. list_glider_in_operation: 운영 중인 기체 목록을 내부망에서 동기화
# 3. sfmc_login_logic: 서버 인증 및 토큰 발급/갱신 (비밀번호/세션 탈취 방지)
# 4. glider_wake_time: 자체 물리/ML 기반 부상 예상 시간(Time to Surface) 추정 스크립트
# 5. ais_cache: 선박 자동 식별 장치 API 연동 및 보안망 내비게이션 캐싱 기능
# ==============================================================================
# from glider_connected_parsing import safe_glider_alarm, broadcaster
# from list_glider_in_operation import update_glider_list
# from sfmc_login_logic import sfmc_login
# from glider_wake_time import update_all_glider_wake_times, update_wake_time_prediction
# from ais_cache import update_ais_cache
import sys

# 루트 경로의 config.py를 임포트하기 위해 sys.path에 상위 두 단계 폴더(ICS_Public) 추가
root_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if root_path not in sys.path:
    sys.path.append(root_path)

import config

# backend 모듈을 위한 상대 경로 추가 (src/backend)
backend_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend")
if backend_path not in sys.path:
    sys.path.append(backend_path)

from main import router as api_router

# 로깅 설정
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 기본 설정 (config.py 사용)
desktop_path = config.DESKTOP_PATH
bot_path = config.BOT_PATH
txt_location = config.USE_GLIDER_FILE
use_glider = deque()

# 전역 태스크 변수 초기화
glider_alarm_task = None
process_results_task = None

# Discord 봇 설정
intents = discord.Intents.default()
intents.message_content = True
bot = commands.Bot(command_prefix="!", intents=intents)
KOREA = datetime.timezone(datetime.timedelta(hours=9))

# 글라이더 부상 주기 데이터를 저장할 딕셔너리
glider_cycle_data = {}

# FastAPI 앱 생성 및 CORS 설정
app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 메인 API 라우터 (REST endpoints) 통합
app.include_router(api_router)

# 파싱 완료 후 프론트엔드 새로고침을 트리거하는 내부 API
from pydantic import BaseModel

class DataUpdatedRequest(BaseModel):
    glider: str

@app.post("/api/notify-data-updated")
async def notify_data_updated(req: DataUpdatedRequest):
    """operation_bot_program.py에서 파이프라인 완료 후 호출하여 프론트엔드에 DATA_UPDATED 이벤트를 전파합니다."""
    await broadcaster.broadcast({
        "type": "DATA_UPDATED",
        "glider": req.glider
    })
    return {"status": "ok", "glider": req.glider}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    websocket_subscriber = broadcaster.subscribe()
    try:
        while True:
            event = await websocket_subscriber.get()
            await websocket.send_json(event)
    except Exception as e:
        logger.error(f"WebSocket 연결 중 에러 발생: {e}")
    finally:
        await websocket.close()

@bot.command(name="부예시")
async def check_wake_time(ctx):
    """현재 모든 글라이더의 부상 예상 시간을 확인합니다. 먼저 업데이트를 실행합니다."""
    try:
        # 먼저 업데이트 작업 실행
        await update_all_glider_wake_times()

        if not os.path.exists(txt_location):
            await ctx.send("글라이더 목록 파일을 찾을 수 없습니다.")
            return
            
        with open(txt_location, 'r') as file:
            for line in file:
                glider_name = line.strip()
                glider_folder = os.path.join(desktop_path, glider_name)
                wake_time_file_path = os.path.join(glider_folder, 'wake_time.txt')
                
                # 글라이더 이름 전송
                await ctx.send(f"**{glider_name}**")
                
                # 부상 예상 시간 정보 전송
                if os.path.exists(wake_time_file_path):
                    with open(wake_time_file_path, 'r', encoding='utf-8') as wake_file:
                        wake_time = wake_file.read()
                    await ctx.send(f"```{wake_time}```")
                else:
                    await ctx.send("부상 예상 시간 정보를 찾을 수 없습니다.")
                    
    except Exception as e:
        logger.error(f"부상 예상 시간 확인 중 오류 발생: {e}")
        await ctx.send(f"오류가 발생했습니다: {e}")

@bot.event
async def on_ready():
    logger.info(f"Logged in as {bot.user}")
    global glider_alarm_task, process_results_task
    
    # 이미 실행 중인 태스크가 있으면 건너뜀
    if glider_alarm_task is None or glider_alarm_task.done():
        logger.info("모니터링 태스크 시작 (on_ready)")
        glider_alarm_task = asyncio.create_task(safe_glider_alarm())
    else:
        logger.info("모니터링 태스크가 이미 실행 중입니다.")

    if process_results_task is None or process_results_task.done():
        logger.info("결과 처리 태스크 시작 (on_ready)")
        process_results_task = asyncio.create_task(process_results())
    else:
        logger.info("결과 처리 태스크가 이미 실행 중입니다.")

    if not start_monitoring.is_running():
        start_monitoring.start()
    if not stop_monitoring.is_running():
        stop_monitoring.start()
    if not update_glider_job.is_running():
        update_glider_job.start()
    if not update_state_file.is_running():
        update_state_file.start()
    if not send_daily_wake_time.is_running():
        send_daily_wake_time.start()
    
    # 프로그램 시작 시 모든 글라이더 부상 예상 시간 업데이트
    try:
        await update_all_glider_wake_times()
        logger.info("프로그램 시작 시 부상 예상 시간 업데이트 완료")
    except Exception as e:
        logger.error(f"프로그램 시작 시 부상 예상 시간 업데이트 중 오류: {e}")

@tasks.loop(time=datetime.time(hour=3, minute=0, tzinfo=KOREA))
async def start_monitoring():
    channel = bot.get_channel(config.CHANNEL_ID_FLOAT_ALARM)
    if channel:
        global glider_alarm_task, process_results_task
        content = "모니터링 작업 시작 (새벽 3시)"
        
        if glider_alarm_task is None or glider_alarm_task.done():
            glider_alarm_task = asyncio.create_task(safe_glider_alarm())
            logger.info("새벽 3시 스케줄: 모니터링 태스크 시작")
        
        if process_results_task is None or process_results_task.done():
            process_results_task = asyncio.create_task(process_results())
            logger.info("새벽 3시 스케줄: 결과 처리 태스크 시작")
            
        await channel.send(content)

@tasks.loop(time=datetime.time(hour=2, minute=58, tzinfo=KOREA))
async def stop_monitoring():
    channel = bot.get_channel(config.CHANNEL_ID_FLOAT_ALARM)
    if channel:
        global glider_alarm_task, process_results_task
        content = "운용 글라이더 업데이트(새벽 2시 58분)"
        if glider_alarm_task:
            glider_alarm_task.cancel()
        if process_results_task:
            process_results_task.cancel()
        await channel.send(content)

@tasks.loop(time=datetime.time(hour=2, minute=58, second=3, tzinfo=KOREA))
async def update_glider_job():
    logger.info("update_glider_list() 실행 (새벽 2시 58분 30초)")

    try:
        fetched_glider_list = await update_glider_list()
        use_glider.clear()
        use_glider.extend(fetched_glider_list)
        
        print(use_glider)   
        with open(txt_location, 'w') as file:
            unique_gliders = list(dict.fromkeys(use_glider))
            for glider in unique_gliders:
                file.write(f"{glider}\n")
        logger.info(f"{txt_location} 파일 업데이트 완료.")
        
    except Exception as e:
       logger.error(f"update_glider_job 실행 중 오류: {e}")

@tasks.loop(time=datetime.time(hour=2, minute=58, second=45, tzinfo=KOREA))
async def update_state_file():
    known_suffixes = ["141", "195", "se"]
    for suffix in known_suffixes:
        state_file = os.path.join(bot_path, f"state_{suffix}.json")
        if os.path.exists(state_file):
            os.remove(state_file)
            await sfmc_login(suffix, state_file=state_file)

@tasks.loop(time=datetime.time(hour=9, minute=50, tzinfo=KOREA))
async def send_daily_wake_time():
    """매일 9시 50분에 부상 예상 시간을 자동으로 업데이트하고 송출합니다."""
    try:
        logger.info("9시 50분 부상 예상 시간 업데이트 시작")
        await update_all_glider_wake_times()
        logger.info("9시 50분 부상 예상 시간 업데이트 완료")
        
        channel = bot.get_channel(config.CHANNEL_ID_WAKE_TIME)
        if channel is None:
            logger.error("부상 예상 시간 채널을 찾을 수 없습니다. config.CHANNEL_ID_WAKE_TIME 확인 필요.")
            return

        if not os.path.exists(txt_location):
            await channel.send("글라이더 목록 파일을 찾을 수 없습니다.")
            return

        with open(txt_location, 'r') as file:
            for line in file:
                glider_name = line.strip()
                glider_folder = os.path.join(desktop_path, glider_name)
                wake_time_file_path = os.path.join(glider_folder, 'wake_time.txt')
                
                if os.path.exists(wake_time_file_path):
                    with open(wake_time_file_path, 'r', encoding='utf-8') as wake_file:
                        wake_time_content = wake_file.read()
                    await channel.send(f"**{glider_name}**\n```{wake_time_content}```")
                else:
                    await channel.send(f"**{glider_name}**\n부상 예상 시간 정보를 찾을 수 없습니다.")
    except Exception as e:
        logger.error(f"매일 부상 예상 시간 송출 중 오류 발생: {e}")

async def process_results():
    await bot.wait_until_ready()
    channel = bot.get_channel(config.CHANNEL_ID_FLOAT_ALARM)
    if channel is None:
        logger.error("채널을 찾을 수 없습니다. config.CHANNEL_ID_FLOAT_ALARM 확인 필요.")
        return
    discord_subscriber = broadcaster.subscribe()
    while True:
        try:
            event = await discord_subscriber.get()
            event_type = event.get("type")
            glider = event.get("glider")
            ip = event.get("ip")
            
            # 프론트엔드 전용 이벤트는 Discord로 전송하지 않음 (Unknown event 방지)
            if event_type in ("ALARM_INFO", "ALARM_START", "ALARM_END", "DATA_UPDATED"):
                continue
            
            # 부상/잠항 이벤트를 받아서 부상 주기 계산
            if event_type in ["surfaced", "submerged"]:
                update_wake_time_prediction(glider, event_type, datetime.datetime.now())
            
            now_kst = datetime.datetime.now(KOREA).strftime("%Y-%m-%d %H:%M:%S")
            
            if event_type == "alarm":
                content = (
                    f"({ip}): Alarm '{event['alarm']}' triggered.\n"
                    f"Data: {event['data']}\n"
                    f"Connection: {event['connection']} @everyone"
                )
            elif event_type == "surfaced":
                content = f"Glider {glider} 부상했습니다 ({ip}) (Connected). @everyone"
                # AIS 캐시 업데이트 트리거 (별도 태스크로 비동기 실행)
                asyncio.create_task(asyncio.to_thread(update_ais_cache, glider))
                # 프론트엔드 알람: 부상 INFO
                await broadcaster.broadcast({
                    "type": "ALARM_INFO",
                    "glider": glider,
                    "level": "info",
                    "msg": f"Glider {glider} 부상했습니다 ({ip})",
                    "timestamp": now_kst
                })
            elif event_type == "submerged":
                content = f"Glider {glider} 잠항했습니다 ({ip}) (Not Connected)."
                # 프론트엔드 알람: 잠항 INFO
                await broadcaster.broadcast({
                    "type": "ALARM_INFO",
                    "glider": glider,
                    "level": "info",
                    "msg": f"Glider {glider} 잠항했습니다 ({ip})",
                    "timestamp": now_kst
                })
            else:
                content = f"Glider {glider} ({ip}): Unknown event."
            await channel.send(content)
        except Exception as e:
            logger.exception(f"[process_results] Error processing event: {e}")

async def run_fastapi():
    config_uvicorn = uvicorn.Config(app, host="0.0.0.0", port=8000, loop="asyncio", log_level="info")
    server = uvicorn.Server(config_uvicorn)
    await server.serve()

async def main():
    fastapi_task = asyncio.create_task(run_fastapi())
    discord_task = asyncio.create_task(bot.start(config.DISCORD_TOKEN_FLOAT))
    await asyncio.gather(fastapi_task, discord_task)

if __name__ == "__main__":
    asyncio.run(main())
