import os
from dotenv import load_dotenv

# 루트 디렉토리의 .env 파일 로드
load_dotenv()

# 더미 백엔드 설정 (포트폴리오 용)
FRONTEND_URL = os.getenv("FRONTEND_URL", "http://localhost:3000")
SECRET_KEY = os.getenv("SECRET_KEY", "dummy-secret-key-for-portfolio")
ALGORITHM = os.getenv("ALGORITHM", "HS256")

# 현재 활성화된 글라이더 목록 (환경 변수에서 콤마로 구분하여 로드)
active_gliders_str = os.getenv("ACTIVE_GLIDERS", "glider_A,glider_B,glider_C")
ACTIVE_GLIDERS = [g.strip() for g in active_gliders_str.split(",") if g.strip()]

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
GLIDERS_DIR = os.path.join(BASE_DIR, "gliders")

# API Keys
WEATHER_API_KEY = os.getenv("WEATHER_API_KEY", "YOUR_WEATHER_API_KEY_HERE")
