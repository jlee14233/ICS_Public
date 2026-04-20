import os
import sys
# backend 폴더를 PYTHON PATH에 추가하여 src 모듈을 임포트할 수 있게 설정
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import glob
import pandas as pd
import numpy as np
import json
from src.parser.log_parser import LogParser
from src.parser.dat_parser import DatParser
from src.utils.binary_converter import BinaryConverter
from src.utils.glider_utils import geo2glider

# Helper functions moved to src.utils.glider_utils

def generate_glider_summary(glider_name, output_dir, all_logs, all_sci, all_performance, existing_sci_data=None, all_waypoints=None):
    """
    [보안 처리됨] parser에서 추출된 원시 로그(LOG)와 과학(SCI) 데이터를 
    프론트엔드 대시보드 규격(웹용 경량 JSON 포맷 등)으로 가공(Binning, Interpolation 등)하여 반환합니다.
    (세부적인 데이터 필터링 규칙 및 센서 파라미터 매핑 로직은 내부 보안 규정에 따라 비공개 처리되었습니다.)
    """
    # [SECURITY NOTICE] Proprietary extraction and aggregation logic redacted
    return ""

if __name__ == "__main__":
    import argparse
    import sys
    # config 참조를 위해 backend 경로를 추가
    backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if backend_dir not in sys.path:
        sys.path.insert(0, backend_dir)
    from backend_config import GLIDER_NAME, get_webdata_dir
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--glider", type=str, default=GLIDER_NAME)
    parser.add_argument("--dest", type=str, default=get_webdata_dir())
    args = parser.parse_args()
    
    generate_glider_summary(args.glider, args.dest)
