#app\utils\request_utils.py
# 네트워크/요청 관련 유틸

from fastapi import Request

def get_user_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"
