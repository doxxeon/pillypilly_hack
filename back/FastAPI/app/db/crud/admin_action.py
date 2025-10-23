from datetime import datetime, timezone
from fastapi import Request
from typing import Optional
from app.db.mongodb import audit_collection  

async def log_admin_action(
    request: Request,
    admin_id: str,
    action: str,
    *,
    target_user_id: Optional[str] = None,
    details: Optional[dict] = None,
) -> None:
    """관리자 조치 공통 감사 로깅"""
    doc = {
        "admin_id": admin_id,                 # 누가
        "action": action,                     # 무엇을
        "target_user_id": target_user_id,     # 누구에게(선택)
        "details": details or {},             # 부가정보(선택)
        "timestamp": datetime.now(timezone.utc),  # UTC 고정 권장
        "ip": request.client.host if request and request.client else None,
        "endpoint": str(request.url.path) if request and request.url else None,
    }
    await audit_collection.insert_one(doc)