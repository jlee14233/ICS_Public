import os
import shutil
import glob
import logging
from datetime import datetime

# 로깅 설정
logger = logging.getLogger(__name__)

def sync_downloaded_data_to_control_room(glider_name, desktop_path, control_room_path):
    """
    바탕화면의 테스트 봇에 의해 다운로드된 glider 데이터를 control-room의 
    LOG 및 SBD 특정 폴더로 분류 및 복사합니다.
    
    Args:
        glider_name (str): 글라이더 이름
        desktop_path (str): 바탕화면 경로 
        control_room_path (str): control-room 백엔드 경로
    """
    # 원본(바탕화면) 경로
    src_glider_dir = os.path.join(desktop_path, glider_name)
    src_logs_dir = os.path.join(src_glider_dir, 'logs')
    src_from_glider_dir = os.path.join(src_glider_dir, 'from-glider')

    # 목적지(control-room) 경로
    dest_glider_dir = os.path.join(control_room_path, 'gliders', glider_name)
    dest_log_dir = os.path.join(dest_glider_dir, 'LOG')
    dest_tbd_pair_dir = os.path.join(dest_glider_dir, 'SCI')
    
    os.makedirs(dest_log_dir, exist_ok=True)
    os.makedirs(dest_tbd_pair_dir, exist_ok=True)

    copied_files_count = 0

    # 1. LOG 폴더: .log 복사
    if os.path.exists(src_logs_dir):
        log_files = glob.glob(os.path.join(src_logs_dir, '*.log'))
        for src_file in log_files:
            file_name = os.path.basename(src_file)
            dest_file = os.path.join(dest_log_dir, file_name)
            
            # 목적지에 파일이 없으면 이동 (LOG)
            if not os.path.exists(dest_file):
                shutil.copy2(src_file, dest_file)
                logger.debug(f"복사 완료: {file_name} -> {dest_log_dir}")
                copied_files_count += 1
            else:
                # 목적지에 이미 존재하는 경우 원본 삭제 처리(선택 사항) 혹은 남겨둠
                pass
    else:
        logger.warning(f"원본 로그 디렉토리를 찾을 수 없습니다: {src_logs_dir}")

    # 2. from-glider 폴더: SBD_only / TBD_pair 분리 복사
    if os.path.exists(src_from_glider_dir):
        sbd_files = glob.glob(os.path.join(src_from_glider_dir, '*.sbd'))
        all_tbd_files = set(glob.glob(os.path.join(src_from_glider_dir, '*.tbd')))
        processed_tbd = set()

        for sbd in sbd_files:
            base_name = os.path.basename(sbd).replace('.sbd', '')
            tbd = os.path.join(src_from_glider_dir, f"{base_name}.tbd")
            
            sbd_filename = os.path.basename(sbd)
            tbd_filename = os.path.basename(tbd)

            # 짝이 있는 경우에만 TBD_pair(-> SCI) 로 이동
            if os.path.exists(tbd):
                dest_sbd_file = os.path.join(dest_tbd_pair_dir, sbd_filename)
                dest_tbd_file = os.path.join(dest_tbd_pair_dir, tbd_filename)
                
                if not os.path.exists(dest_sbd_file):
                    shutil.copy2(sbd, dest_sbd_file)
                    copied_files_count += 1
                if not os.path.exists(dest_tbd_file):
                    shutil.copy2(tbd, dest_tbd_file)
                    copied_files_count += 1
                
                processed_tbd.add(tbd)

    else:
        logger.warning(f"원본 SBD/TBD 디렉토리를 찾을 수 없습니다: {src_from_glider_dir}")

    logger.info(f"✅ {glider_name} 제어실 파일 복사 완료: 총 {copied_files_count}개 파일 업데이트 됨.")
    return copied_files_count

if __name__ == "__main__":
    # Test execution mock
    import argparse
    import sys
    # config 참조를 위해 backend 경로를 추가
    backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if backend_dir not in sys.path:
        sys.path.insert(0, backend_dir)
    from backend_config import GLIDER_NAME, DESKTOP_PATH, BASE_DIR
    
    parser = argparse.ArgumentParser(description="Sync glider files to control-room")
    parser.add_argument("--glider", type=str, default=GLIDER_NAME, help="글라이더 이름")
    parser.add_argument("--desktop", type=str, default=DESKTOP_PATH, help="바탕화면 경로")
    parser.add_argument("--dest", type=str, default=BASE_DIR, help="제어실 경로")
    
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
    sync_downloaded_data_to_control_room(args.glider, args.desktop, args.dest)
