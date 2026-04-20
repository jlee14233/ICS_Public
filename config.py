import os
from dotenv import load_dotenv

# 루트 경로의 .env 파일을 로드합니다.
# 실제 운영 환경에서는 GitHub Secrets나 환경 변수를 직접 주입받습니다.
load_dotenv()

# 디렉토리 경로 설정
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DESKTOP_PATH = os.getenv("DESKTOP_PATH", os.path.join(os.path.expanduser('~'), 'Desktop'))
BOT_PATH = os.path.join(BASE_DIR, "src", "bot")
USE_GLIDER_FILE = os.path.join(BOT_PATH, "use_glider.txt")
LOG_FILE = os.path.join(BOT_PATH, "bot_log.txt")

# Discord 봇 관련 토큰 및 채널
DISCORD_TOKEN_FLOAT = os.getenv("DISCORD_TOKEN_FLOAT", "YOUR_DISCORD_BOT_TOKEN_HERE")
DISCORD_TOKEN_OPERATION = os.getenv("DISCORD_TOKEN_OPERATION", "YOUR_DISCORD_APP_TOKEN_HERE")
CHANNEL_ID_FLOAT_ALARM = int(os.getenv("CHANNEL_ID_FLOAT_ALARM", "123456789012345678"))
CHANNEL_ID_LOGS = int(os.getenv("CHANNEL_ID_LOGS", "123456789012345678"))
CHANNEL_ID_IMAGES = int(os.getenv("CHANNEL_ID_IMAGES", "123456789012345678"))
CHANNEL_ID_WAKE_TIME = int(os.getenv("CHANNEL_ID_WAKE_TIME", "123456789012345678"))

# 외부 서버/NAS 및 API 정보
NAS_ENABLED = os.getenv("NAS_ENABLED", "True").lower() in ("true", "1", "yes")
NAS_TARGET_SERVER = os.getenv("NAS_TARGET_SERVER", "SERVER_1")
NAS_BASE_PATH = os.getenv("NAS_BASE_PATH", "Z:\\Your\\NAS\\Path")
NAS_ARCHIVE_THRESHOLD_DAYS = int(os.getenv("NAS_ARCHIVE_THRESHOLD_DAYS", "15"))

# SFMC / SSH 관련 설정
SSH_PRIVATE_KEY_PATH = os.getenv("SSH_PRIVATE_KEY_PATH", "C:\\path\\to\\your\\private_key.pem")
DATA_SERVER_HOST = os.getenv("DATA_SERVER_HOST", "YOUR_DATA_SERVER_IP")
DATA_SERVER_PORT = int(os.getenv("DATA_SERVER_PORT", "22"))
DATA_SERVER_USER = os.getenv("DATA_SERVER_USER", "YOUR_USERNAME")
DATA_SERVER_PASSWORD = os.getenv("DATA_SERVER_PASSWORD", "YOUR_PASSWORD")
DATA_SERVER_DOCK_PATH = os.getenv("DATA_SERVER_DOCK_PATH", "/path/to/remote/dock/")

# WebSocket 설정
WS_URI = os.getenv("WS_URI", "ws://localhost:8000/ws")
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "5"))
RETRY_DELAY = int(os.getenv("RETRY_DELAY", "10"))
