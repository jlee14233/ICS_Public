import os
import shutil
import zipfile
import re
import logging
from datetime import datetime
import asyncio  # Added for async execution
import pysftp
import paramiko
from pysftp import CnOpts
from server_glider_list import get_dockserver_ip, list141, list142, list195

import sys, os
root_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if root_path not in sys.path:
    sys.path.append(root_path)

import config

logger = logging.getLogger(__name__)

def is_nas_target_glider(glider_name):
    """
    해당 글라이더가 NAS 동기화 대상인지 확인
    config.NAS_TARGET_SERVER에 지정된 서버의 글라이더만 대상
    
    Args:
        glider_name: 글라이더 이름
    
    Returns:
        bool: 대상 서버의 글라이더이면 True, 아니면 False
    """
    if not hasattr(config, 'NAS_TARGET_SERVER'):
        # 기본값: 195 서버 (하위 호환성)
        target_server = '195'
    else:
        target_server = config.NAS_TARGET_SERVER
    
    # 서버 ID에 따라 해당 리스트 선택
    if target_server == '141':
        return glider_name in list141
    elif target_server == '142':
        return glider_name in list142
    elif target_server == '195':
        return glider_name in list195
    else:
        logger.warning(f"알 수 없는 NAS_TARGET_SERVER: {target_server}")
        return False

def zip_old_logs(log_folder):
    """
    오래된 로그 파일들을 날짜별로 그룹화하여 압축합니다.
    3일 이상 차이가 나거나, 마지막 로그가 3일 이상 지난 경우 압축합니다.
    """
    if not os.path.exists(log_folder):
        logger.warning(f"Log folder does not exist: {log_folder}")
        return None

    log_files = [f for f in os.listdir(log_folder) if f.endswith('.log')]
    if not log_files:
        return None

    log_files.sort()
    date_pattern = re.compile(r'_(\d{8})T')
    non_continuous_blocks = []
    current_block = []

    for i in range(len(log_files)):
        match = date_pattern.search(log_files[i])
        if not match:
            continue
            
        log_date_str = match.group(1)
        log_date = datetime.strptime(log_date_str, '%Y%m%d')

        if not current_block:
            current_block.append(log_files[i])
        else:
            prev_match = date_pattern.search(current_block[-1])
            if prev_match:
                prev_log_date_str = prev_match.group(1)
                prev_log_date = datetime.strptime(prev_log_date_str, '%Y%m%d')
                
                if (log_date - prev_log_date).days <= 3:
                    current_block.append(log_files[i])
                else:
                    non_continuous_blocks.append(current_block)
                    current_block = [log_files[i]]
            else:
                 # Should not happen if pattern matched before
                 current_block.append(log_files[i])

    if current_block:
        non_continuous_blocks.append(current_block)

    if not non_continuous_blocks:
        return None

    # Check last block against today
    last_block = non_continuous_blocks[-1]
    last_match = date_pattern.search(last_block[-1])
    if last_match:
        last_log_date_str = last_match.group(1)
        last_log_date = datetime.strptime(last_log_date_str, '%Y%m%d')
        today = datetime.today()
        if (today - last_log_date).days <= 3:
            non_continuous_blocks.pop()

    archive_folder = os.path.join(os.path.dirname(log_folder), 'ArchivedLogs')
    if not os.path.exists(archive_folder):
        os.makedirs(archive_folder)

    created_archives = []
    for block in non_continuous_blocks:
        if not block: 
            continue
            
        first_match = date_pattern.search(block[0])
        last_match = date_pattern.search(block[-1])
        
        if first_match and last_match:
            first_str = first_match.group(1)
            last_str = last_match.group(1)
            archive_name = os.path.join(archive_folder, f'{first_str}_to_{last_str}.Archive.zip')
            
            try:
                with zipfile.ZipFile(archive_name, 'w') as archive:
                    for log_file in block:
                        file_path = os.path.join(log_folder, log_file)
                        if os.path.exists(file_path):
                            archive.write(file_path, log_file)
                            os.remove(file_path)
                created_archives.append(os.path.basename(archive_name))
            except Exception as e:
                logger.error(f"Failed to archive block starting {first_str}: {e}")

    return created_archives

def zip_old_from_glider_files(from_glider_folder):
    """
    오래된 from-glider 파일들을 블록 단위로 압축합니다.
    - 연속된 파일(3일 이내 간격)을 하나의 블록으로 그룹화
    - 마지막 블록이 3일 이상 지났으면 그 블록을 제외한 모든 블록 압축
    - LOG 파일의 zip_old_logs()와 동일한 로직
    
    파일명 형식: kg_1167-2026-035-0-0.sbd (YYYY-DDD-S-F)
    """
    if not os.path.exists(from_glider_folder):
        logger.warning(f"from-glider folder does not exist: {from_glider_folder}")
        return None

    data_files = [f for f in os.listdir(from_glider_folder) if f.endswith(('.sbd', '.tbd'))]
    if not data_files:
        return None

    # 파일명과 수정 시간을 함께 저장
    files_with_mtime = []
    for data_file in data_files:
        file_path = os.path.join(from_glider_folder, data_file)
        mtime = os.path.getmtime(file_path)
        files_with_mtime.append((data_file, mtime))
    
    # 수정 시간 기준 정렬
    files_with_mtime.sort(key=lambda x: x[1])
    
    # 블록으로 그룹화 (3일 이내 연속된 파일)
    non_continuous_blocks = []
    current_block = []
    
    for i in range(len(files_with_mtime)):
        data_file, mtime = files_with_mtime[i]
        file_date = datetime.fromtimestamp(mtime)
        
        if not current_block:
            current_block.append(data_file)
        else:
            # 이전 파일의 mtime
            prev_file, prev_mtime = files_with_mtime[i - 1]
            prev_date = datetime.fromtimestamp(prev_mtime)
            
            # 이전 파일과 3일 이내 차이면 같은 블록
            if (file_date - prev_date).days <= 3:
                current_block.append(data_file)
            else:
                # 3일 초과 차이 → 새 블록 시작
                non_continuous_blocks.append(current_block)
                current_block = [data_file]
    
    if current_block:
        non_continuous_blocks.append(current_block)
    
    if not non_continuous_blocks:
        return None
    
    # 마지막 블록이 최근 3일 이내면 제외 (압축하지 않음)
    last_block = non_continuous_blocks[-1]
    last_file = last_block[-1]
    last_file_path = os.path.join(from_glider_folder, last_file)
    last_mtime = os.path.getmtime(last_file_path)
    last_date = datetime.fromtimestamp(last_mtime)
    today = datetime.today()
    
    if (today - last_date).days <= 3:
        # 마지막 블록은 최근 데이터이므로 압축하지 않음
        non_continuous_blocks.pop()
    
    if not non_continuous_blocks:
        logger.debug(f"No old from-glider blocks to archive in {from_glider_folder}")
        return None
    
    archive_folder = os.path.join(os.path.dirname(from_glider_folder), 'ArchivedFromGlider')
    if not os.path.exists(archive_folder):
        os.makedirs(archive_folder)
    
    # 파일명에서 날짜 추출용 패턴
    date_pattern = re.compile(r'-(\d{4})-(\d{3})-')
    created_archives = []
    
    for block in non_continuous_blocks:
        if not block:
            continue
        
        first_match = date_pattern.search(block[0])
        last_match = date_pattern.search(block[-1])
        
        if first_match and last_match:
            first_year = int(first_match.group(1))
            first_day = int(first_match.group(2))
            last_year = int(last_match.group(1))
            last_day = int(last_match.group(2))
            
            # Archive filename: 2026-030_to_2026-035.Archive.zip
            archive_name = os.path.join(archive_folder, 
                                       f'{first_year}-{first_day:03d}_to_{last_year}-{last_day:03d}.Archive.zip')
            
            try:
                with zipfile.ZipFile(archive_name, 'w') as archive:
                    for data_file in block:
                        file_path = os.path.join(from_glider_folder, data_file)
                        if os.path.exists(file_path):
                            archive.write(file_path, data_file)
                            os.remove(file_path)
                created_archives.append(os.path.basename(archive_name))
                logger.info(f"✅ Archived block: {os.path.basename(archive_name)} ({len(block)} files)")
            except Exception as e:
                logger.error(f"Failed to archive from-glider block {first_year}-{first_day:03d}: {e}")
    
    return created_archives

async def download_logs_for_glider(glider_name, desktop_path, bot_path):
    """
    [보안 처리됨] 제조사(SFMC) 서버에서 글라이더 원시 로그를 SFTP 프로토콜을 이용해 동기화합니다.
    (내부 서버 IP, 포트, 인증 정보 및 디렉토리 구조는 비공개 처리되었습니다.)
    """
    # [SECURITY NOTICE] Proprietary SFMC connection & download loop redacted
    pass

def new_glider_sensing():
    """
    [보안 처리됨] 통합 데이터 서버 구조 자동 생성 및 관리(Provisioning) 로직입니다.
    (내부 데이터 서버 SSH 접근 및 구조 확인 로직 비공개)
    """
    # [SECURITY NOTICE] Data server SSH connection and mkdir logic redacted
    pass

def create_nas_directory_structure(glider_name, event_date=None):
    """
    NAS에 글라이더별 폴더 구조 생성
    
    Args:
        glider_name: 글라이더 이름
        event_date: 사용하지 않음 (하위 호환성을 위해 유지)
    
    Returns:
        tuple: (log_path, from_glider_path) 또는 (None, None) on error
    """
    if not config.NAS_ENABLED:
        return None, None
    
    if not is_nas_target_glider(glider_name):
        logger.debug(f"{glider_name}은 NAS 대상 글라이더가 아닙니다.")
        return None, None
    
    try:
        base_path = os.path.join(config.NAS_BASE_PATH, glider_name)
        log_path = os.path.join(base_path, 'LOG')
        from_glider_path = os.path.join(base_path, 'from-glider')
        
        # 디렉토리 생성
        os.makedirs(log_path, exist_ok=True)
        os.makedirs(from_glider_path, exist_ok=True)
        
        logger.info(f"✅ NAS 폴더 생성 완료: {base_path}")
        return log_path, from_glider_path
        
    except PermissionError as e:
        logger.error(f"❌ NAS 권한 오류: {e}")
        return None, None
    except Exception as e:
        logger.error(f"❌ NAS 폴더 생성 실패: {e}")
        return None, None


async def download_from_glider_files(glider_name, desktop_path):
    """
    [보안 처리됨] SFMC 서버에서 from-glider(측정 원시 바이너리 SBD, TBD) 파일의 
    차분(Delta) 다운로드를 수행합니다. 집합 자료구조를 활용한 동기화.
    (내부 통신 포트 및 접속 로직 비공개)
    """
    # [SECURITY NOTICE] Proprietary from-glider fetch logic redacted
    pass

async def archive_old_nas_mission(glider_name):
    """
    NAS에 저장된 과거 미션 자료를 압축합니다.
    LOG 폴더만 체크하여 30일 이상 경과 시 과거 미션으로 간주하고
    LOG + from-glider 폴더를 하나의 ZIP 파일로 압축합니다.
    
    Args:
        glider_name: 글라이더 이름
    """
    if not config.NAS_ENABLED or not is_nas_target_glider(glider_name):
        return
    
    try:
        # NAS 경로 설정
        nas_glider_path = os.path.join(config.NAS_BASE_PATH, glider_name)
        nas_log_path = os.path.join(nas_glider_path, 'LOG')
        nas_from_glider_path = os.path.join(nas_glider_path, 'from-glider')
        
        # LOG 폴더 확인
        if not os.path.exists(nas_log_path):
            logger.debug(f"{glider_name} NAS LOG 폴더 없음, 압축 건너뜀")
            return
        
        # LOG 파일 목록 가져오기
        log_files = [f for f in os.listdir(nas_log_path) if f.endswith('.log')]
        if not log_files:
            logger.debug(f"{glider_name} NAS LOG 파일 없음, 압축 건너뜀")
            return
        
        # LOG 파일에서 날짜 추출 (패턴: glider_YYYYMMDDTHHMMSS.log)
        date_pattern = re.compile(r'_(\d{8})T')
        dates = []
        for log_file in log_files:
            match = date_pattern.search(log_file)
            if match:
                date_str = match.group(1)
                file_date = datetime.strptime(date_str, '%Y%m%d')
                dates.append(file_date)
        
        if not dates:
            logger.debug(f"{glider_name} LOG 파일에서 날짜 추출 실패")
            return
        
        # 마지막 파일 날짜 확인
        last_date = max(dates)
        today = datetime.today()
        days_since_last = (today - last_date).days
        
        # 15일 미만이면 연속 운용 중 → 압축 안 함
        if days_since_last < config.NAS_ARCHIVE_THRESHOLD_DAYS:
            logger.debug(f"{glider_name} 연속 운용 중 ({days_since_last}일), 압축 안 함")
            return
        
        # 15일 이상 경과 → 과거 미션으로 간주, 압축 실행
        logger.info(f"🗜️ [NAS ARCHIVE] {glider_name} 과거 미션 감지 ({days_since_last}일 경과) → 압축 시작")
        
        # 날짜 범위 추출
        start_date = min(dates)
        end_date = max(dates)
        start_str = start_date.strftime('%Y%m%d')
        end_str = end_date.strftime('%Y%m%d')
        
        # ArchivedMissions 폴더 생성
        archive_folder = os.path.join(nas_glider_path, 'ArchivedMissions')
        if not os.path.exists(archive_folder):
            os.makedirs(archive_folder)
        
        # ZIP 파일
        archive_name = f"{glider_name}_{start_str}_{end_str}.zip"
        archive_path = os.path.join(archive_folder, archive_name)
        
        # 이미 존재하는 압축 파일이면 건너뜀
        if os.path.exists(archive_path):
            logger.warning(f"⚠️ [NAS ARCHIVE] {archive_name} 이미 존재, 압축 건너뜀")
            return
        
        # ZIP 파일 생성
        with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            # LOG 폴더 압축
            if os.path.exists(nas_log_path):
                for log_file in os.listdir(nas_log_path):
                    if log_file.endswith('.log'):
                        file_path = os.path.join(nas_log_path, log_file)
                        # ZIP 내부 경로: LOG/filename.log
                        zipf.write(file_path, os.path.join('LOG', log_file))
                logger.info(f"  ✅ LOG 폴더 ({len(log_files)}개 파일) 압축 완료")
            
            # from-glider 폴더 압축
            from_glider_count = 0
            if os.path.exists(nas_from_glider_path):
                from_glider_files = [f for f in os.listdir(nas_from_glider_path) 
                                    if f.endswith(('.sbd', '.tbd'))]
                for data_file in from_glider_files:
                    file_path = os.path.join(nas_from_glider_path, data_file)
                    # ZIP 내부 경로: from-glider/filename.sbd
                    zipf.write(file_path, os.path.join('from-glider', data_file))
                    from_glider_count += 1
                logger.info(f"  ✅ from-glider 폴더 ({from_glider_count}개 파일) 압축 완료")
        
        # 원본 폴더 삭제
        if os.path.exists(nas_log_path):
            shutil.rmtree(nas_log_path)
            logger.info(f"  🗑️ 원본 LOG 폴더 삭제")
        
        if os.path.exists(nas_from_glider_path):
            shutil.rmtree(nas_from_glider_path)
            logger.info(f"  🗑️ 원본 from-glider 폴더 삭제")
        
        # 새 빈 폴더 생성
        os.makedirs(nas_log_path)
        os.makedirs(nas_from_glider_path)
        logger.info(f"  📁 새 LOG, from-glider 폴더 생성")
        
        logger.info(f"✅ [NAS ARCHIVE] {archive_name} 생성 완료 ({start_str} ~ {end_str})")
        
    except Exception as e:
        logger.error(f"❌ [NAS ARCHIVE] {glider_name} 압축 실패: {e}")

async def sync_files_to_nas(glider_name, event_type='submerged'):
    """
    195 서버 글라이더 전용: Surface/Submerged 이벤트 발생 시 파일을 NAS로 동기화
    
    Args:
        glider_name: 글라이더 이름
        event_type: 'surfaced' 또는 'submerged'
    """
    if not config.NAS_ENABLED or not is_nas_target_glider(glider_name):
        return
    
    logger.info(f"🔄 [NAS SYNC] {glider_name} - {event_type} 이벤트 동기화 시작")
    
    # NAS 폴더 구조 생성
    nas_log_path, nas_from_glider_path = create_nas_directory_structure(glider_name)
    
    if not nas_log_path or not nas_from_glider_path:
        logger.warning(f"⚠️ [NAS SYNC] {glider_name} NAS 경로 생성 실패")
        return
    
    # 로컬 경로 설정
    local_glider_path = os.path.join(config.DESKTOP_PATH, glider_name)
    local_log_path = os.path.join(local_glider_path, 'logs')
    local_from_glider_path = os.path.join(local_glider_path, 'from-glider')
    
    file_count = 0
    
    try:
        # 1. LOG 파일 동기화 (*.log)
        if os.path.exists(local_log_path):
            log_files = [f for f in os.listdir(local_log_path) if f.endswith('.log')]
            for log_file in log_files:
                src_file = os.path.join(local_log_path, log_file)
                dst_file = os.path.join(nas_log_path, log_file)
                
                # 파일이 없거나 더 최신인 경우만 복사
                if not os.path.exists(dst_file) or \
                   os.path.getmtime(src_file) > os.path.getmtime(dst_file):
                    shutil.copy2(src_file, dst_file)
                    logger.debug(f"📄 복사: {log_file} → NAS/LOG/")
                    file_count += 1
        
        # 2. from-glider 파일 동기화 (*.sbd, *.tbd)
        if os.path.exists(local_from_glider_path):
            data_files = [f for f in os.listdir(local_from_glider_path) 
                         if f.endswith(('.sbd', '.tbd'))]
            for data_file in data_files:
                src_file = os.path.join(local_from_glider_path, data_file)
                dst_file = os.path.join(nas_from_glider_path, data_file)
                
                # 파일이 없거나 더 최신인 경우만 복사
                if not os.path.exists(dst_file) or \
                   os.path.getmtime(src_file) > os.path.getmtime(dst_file):
                    shutil.copy2(src_file, dst_file)
                    logger.debug(f"📄 복사: {data_file} → NAS/from-glider/")
                    file_count += 1
        
        logger.info(f"✅ [NAS SYNC] {glider_name} 동기화 완료 ({file_count}개 파일)")
        
    except Exception as e:
        logger.error(f"❌ [NAS SYNC] {glider_name} 동기화 실패: {e}")

def log_update():
    """
    [보안 처리됨] 통합 관제 백엔드 서버로 최신 파싱 성공/실패 로그를 안전하게 업로드(Sync)합니다.
    (내부 paramiko SSH 핸들링 및 서버 디렉토리 구조 룰은 제거됨)
    """
    # [SECURITY NOTICE] Secondary remote backup mechanism redacted
    pass

async def main_manual_update():
    """
    수동으로 로그 매니저를 실행할 때 호출되는 함수입니다.
    1. SFMC 서버에서 로그를 다운로드합니다.
    2. 데이터 서버에 글라이더 폴더가 있는지 확인하고 생성합니다.
    3. 로컬의 로그를 데이터 서버로 업로드합니다.
    """
    # 로깅 설정 (콘솔 출력용)
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    logger.info("수동 로그 업데이트 시작...")

    if not os.path.exists(config.USE_GLIDER_FILE):
        logger.error(f"글라이더 목록 파일이 없습니다: {config.USE_GLIDER_FILE}")
        return

    with open(config.USE_GLIDER_FILE, 'r') as f:
        gliders = [line.strip() for line in f if line.strip()]

    logger.info(f"대상 글라이더: {gliders}")

    # 1. SFMC에서 로그 다운로드
    logger.info(">>> 단계 1: SFMC 로그 다운로드 및 압축")
    for glider in gliders:
        logger.info(f"[{glider}] 로그 다운로드 시도...")
        await download_logs_for_glider(glider, config.DESKTOP_PATH, config.BOT_PATH)
    
    # 2. 데이터 서버 폴더 확인
    logger.info(">>> 단계 2: 데이터 서버 폴더 확인 (New Glider Sensing)")
    new_glider_sensing()

    # 3. 데이터 서버로 업로드
    logger.info(">>> 단계 3: 데이터 서버로 로그 업로드 (Log Update)")
    log_update()

    logger.info("수동 로그 업데이트 완료.")

if __name__ == "__main__":
    asyncio.run(main_manual_update())
