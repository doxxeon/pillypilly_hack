# 날짜/문자열 포맷 변환 등 헬퍼 함수

from datetime import datetime
from pytz import timezone

def seoul_now():
    return datetime.now(timezone("Asia/Seoul"))