# app/utils/formatter.py
# 날짜/문자열 포맷 변환 등 헬퍼 함수

from datetime import datetime
from pytz import timezone

# ──────────────────────────────────────────────
# 서울 시간 반환
# ──────────────────────────────────────────────
def seoul_now():
    return datetime.now(timezone("Asia/Seoul"))