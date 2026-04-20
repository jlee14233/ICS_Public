# Project Architecture Whitepaper: Integrated Glider Control System

본 문서는 `kakao_test` 루트 디렉토리에서 구동되는 통합관제시스템의 전반적인 기술 아키텍처와 모듈 간의 협업 구조를 설명합니다.

---

## 1. Frontend (Web MVP)

웹 기반의 데이터 시각화 및 관제 인터페이스를 제공하는 파트입니다.

- **프레임워크:** Flutter Web (Google)
- **주요 라우팅 경로 (URL)**
  - `/`: 대시보드 메인 화면 (`DashboardScreen`)
- **핵심 페이지 및 컴포넌트 경로**
  - `control-room/frontend/glider_dashboard/lib/screens/dashboard_screen.dart`: 전체 레이아웃 구성을 담당하는 메인 화면
  - `control-room/frontend/glider_dashboard/lib/widgets/map_frame.dart`: GIS 기반 실시간 위치 및 AIS 데이터 시각화 프레임
  - `control-room/frontend/glider_dashboard/lib/widgets/sensor_frame.dart`: 온도, 염도 등 과학 데이터 시계열/프로파일 차트 프레임
  - `control-room/frontend/glider_dashboard/lib/widgets/flight_frame.dart`: 글라이더 비행 성능 및 상태 지표 프레임
- **전역 상태 관리 (State Management)**
  - **위치:** `control-room/frontend/glider_dashboard/lib/providers/glider_provider.dart`
  - **주요 상태값:** 현재 선택된 글라이더 ID, 실시간 로그 데이터, 통합 트랙 이력(3기 동시 표출), 전역 AIS 선박 데이터 등
- **입출력 인터페이스 (I/O)**
  - **입력:** FastAPI 백엔드로부터 수신되는 JSON 포맷의 관측 및 성능 데이터
  - **출력:** 사용자 인터랙션에 따른 글라이더 전환 명령 및 지도 확대/축소 뷰 제어

---

## 2. Backend (API & Real-time Communication)

데이터 처리 파이프라인과 프론트엔드 간의 브릿지 역할을 수행하는 API 레이어입니다.

- **프레임워크:** FastAPI (Python 기반 비동기 프레임워크)
- **매인 컨트롤러 위치**
  - `control-room/backend/main.py`: 정적 데이터 서빙 및 기본 API 엔드포인트 관리
  - `glider_float_alarm.py`: 실시간 이벤트 발생 및 WebSocket 핸들링
- **REST API 엔드포인트 목록**
  - `GET /data/{glider}/log`: 특정 글라이더의 운영 상태 로그 조회
  - `GET /data/{glider}/sensor_web`: 웹 시각화용 과학 센서(CTD 등) 데이터 조회
  - `GET /data/{glider}/performance`: 비행 효율성 및 성능 지표 조회
  - `GET /data/{glider}/waypoints`: 목표 지점 및 경로 정보 조회
  - `GET /data/ais`: 실시간 주변 선박(AIS) 위치 정보 조회
- **WebSocket 통신 채널**
  - **경로:** `WS /ws` (포트 8000)
  - **구독/발행 이벤트:** 글라이더 부상(surfaced), 잠항(submerged), 경보(alarm) 등의 실시간 장비 텔레메트리 데이터 스트림

---

## 3. Background Services (Automation & Monitoring)

장비의 물리적 신호를 감지하고 데이터 전처리를 자동화하는 데몬 및 스크립트 그룹입니다.

- **핵심 자동화 스크립트 위치**
  - `glider_float_alarm.py`: SBD 및 SFMC 로그를 상시 모니터링하여 장비의 실시간 상태 변화 감지
  - `operation_bot_program.py`: WebSocket 이벤트를 수신하여 데이터 다운로드 및 처리 파이프라인을 자동 트리거하는 제어 루프
  - `control-room/backend/glider_processor.py`: 원본 로그(LOG, DAT)를 파싱하고 JSON 및 가시화 이미지를 생성하는 통합 엔진
- **실행 주기 및 트리거 조건**
  - **부상 이벤트:** 장비 부상 신호 감지 시 즉시 로그 다운로드 및 분석 파이프라인 실행
  - **스케줄 작업:** 매일 특정 시간(예: 09:50 AM) 부상 예상 시간을 업데이트하고 데이터 동기화 수행
- **외부 연동 스크립트**
  - `log_manager.py`: SFMC 클라우드 및 내부 NAS 간의 파일 동기화 인터페이스
  - **Discord Bot:** 장비 상태 알림 및 로그 업로드 완료 메시지 송출 (트리거: 부상/잠항 및 파싱 완료 시)

---

## 4. Control & Simulation (Control Integration)

백엔드 로직과 물리 제어/시뮬레이션 모델을 연결하는 인터페이스 파트입니다.

- **제어 연동 스크립트 위치**
  - `control-room/matlab_script/`: MATLAB 기반의 전문 분석 및 시뮬레이션 알고리즘 보관소
  - `control-room/backend/src/parser/`: Python과 MATLAB 스크립트 간의 호환성을 유지하며 물리 데이터를 구조화하는 파서 층
- **주요 연동 브릿지**
  - `KG_1167_LOG_TO_XLSX.m`: 원본 로그를 엑셀 형식으로 변품하여 정밀 분석 지원
  - `plot_all_figures.m`: MATLAB 엔진을 호출하여 고해상도 품질의 과학 데이터 리포트 생성
- **주요 파라미터 인터페이스 (I/O)**
  - **입력:** SBD/TBD 바이너리 프레임, 웨이포인트(WPT) 좌표계, 센서 캘리브레이션 상수
  - **출력:** 비행 성능 예측 모델 결과물, 고정밀 수심별 물리량 분포도, 조종 명령 생성용 기초 데이터
