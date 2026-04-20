# 🌊 Integrated Glider Control System (ICS)

**자율 무인 잠수정(Glider) 통합 관제 및 물리 해양 데이터 자동 분석 시스템**

![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Pandas](https://img.shields.io/badge/Pandas-150458?style=for-the-badge&logo=pandas&logoColor=white)
![Discord API](https://img.shields.io/badge/Discord_Bot-5865F2?style=for-the-badge&logo=discord&logoColor=white)

## 프로젝트 개요 (Overview)

ICS(Integrated Glider Control System)는 해양 관측용 자율 무인 잠수정(Glider)에서 전송되는 원시 바이너리(Binary) 데이터와 텔레메트리(Telemetry) 신호를 **실시간으로 수집, 파싱, 분석하여 Web 기반의 대시보드로 시각화하는 통합 관제 파이프라인**입니다.

Event-driven 아키텍처를 도입하여 글라이더의 부상/잠항 이벤트를 즉각적으로 감지하고, 수천 만 개의 해양 데이터 포인트(T, S, P)를 과학 표준에 맞게 정제하여 관제사에게 최적의 의사결정 환경을 제공합니다.

_(※ 본 레포지토리는 포트폴리오 공개용으로 구조화된 저장소이며, 실제 서버 IP, 인증 정보 등 민감한 데이터는 모두 환경변수(`.env`)로 분리 및 마스킹 되었습니다.)_

---

## ⚡ 주요 기술적 성과 (Key Achievements)

### 1. 🤖 Event-Driven 운영 자동화 파이프라인

- **Discord Bot & Playwright 연동**: SFMC 클라우드와 SSH 통신을 이중화하여, 장비의 네트워크 연결(Surface) 지연시간을 5분 이내로 감지.
- 자동으로 해상 트래픽(AIS) 정보 수집 및 원격 NAS 데이터 동기화를 스케줄링하여 기존 수동 관리 대비 **운영 리소스 90% 절감**.

### 2. 🧮 과학 데이터 파싱 및 고도화된 수치 해석 (Data Engineering)

- **UNESCO 1983 / Haversine 적용 (`glider_utils.py`)**: 단편적인 센서 출력값을 처리하기 위해 해양 물리 표준 방정식 기반의 염분(Salinity) 계산 및 구면 윤곽을 고려한 경로 이탈 거리(Cross-track Error) 정밀 계산 로직 자체 구현.
- **Noise Filtering & Interpolation**: 1Hz 단위 선형 보간 기법을 사용하여, 요동치는 수심 데이터를 논리적인 '단일 사이클(YO)' 단위로 분할 분석하는 `gldidx3` 알고리즘 포팅 및 최적화.

### 3. 🚀 High-Performance 웹 관제 시각화

- **FastAPI + WebSockets**: 파싱이 완료된 거대한 JSON 지표열을 비동기 REST API 로 서빙. 장비 상태 변경(Alarm) 발생 시 WebSockets로 실시간 브로드캐스팅.
- **Flutter Web**: GIS 기반 위치 추적 레이어 렌더링, 1년 치(수백만 데이터) 밀도 프로파일 색상 산점도(Scatter)의 응답성을 보장하는 반응형 UI 구축.

---

## 📂 아키텍처 구조 (Directory Structure)

전체 시스템은 역할과 책임(MSA 개념)에 따라 크게 3개의 모듈로 격리되어 관리됩니다.

```text
ICS_Public/
│
├── src/
│   ├── bot/           # [Event Hub] 디스코드 봇 기반 상태 모니터링, NAS 동기화, 파이프라인 트리거
│   ├── backend/       # [Data Layer] 원본 바이너리(SBD/LOG) 컨버팅 패키지 및 FastAPI REST/WS 서버
│   └── frontend/      # [View Layer] 관리자 권한 관제 대시보드 (Flutter)
│
├── config.py          # 앱 전체의 전역 경로 및 상수 바인딩 모듈 (.env 사용)
├── .env.example       # 환경 변수 템플릿 (보안성 확보)
└── project_architecture.md # 상세 시스템 아키텍처 및 통신 플로우 문서
```

_(상세한 데이터 통신 플로우와 아키텍처 다이어그램은 `project_architecture.md` 문서에서 확인하실 수 있습니다.)_

---

## 💻 빠른 시작 가이드 (Quick Start)

본 저장소를 로컬 환경에서 구동하기 위한 가이드입니다.

### 1. 환경 설정 (.env)

1. 루트 경로에 있는 `.env.example` 파일을 복사하여 `.env`로 이름을 변경합니다.
2. 각자의 환경에 맞는 경로(바이너리 변환 툴 경로 등) 및 토큰 값을 주입합니다.

```bash
cp .env.example .env
```

### 2. 백엔드 및 봇 실행

```bash
# 의존성 설치
pip install -r requirements.txt

# Event-Driven 메인 봇 엔진 실행 (FastAPI 서버 동시 구동)
cd src/bot
python operation_bot_program.py
```

### 3. 프론트엔드 대시보드 실행

```bash
cd src/frontend/glider_dashboard
flutter pub get
flutter run -d chrome
```

---

> **🛠️ 리팩토링 및 코드 품질 최적화**
>
> - **Dependency Injection**: 코드 내 모든 서버 주소와 크리덴셜을 소스코드에서 제거하고 환경 변수(os.getenv)로 제어합니다.
> - **OS Indepedence**: Windows 기반의 하드코딩 경로를 상대경로 및 환경 변수로 100% 치환하여, 어떠한 머신에서도 유연하게 배포 가능합니다.
> - **Google Style Docstring**: 심도 깊은 로직을 담당하는 핵심 함수들은 "무엇을", "왜" 하는지에 대한 철저한 Docstring을 작성하여 가독성을 높였습니다.
