# app/db/crud/error_log.py
from datetime import datetime, timezone
from typing import Any, Dict, Optional
from app.db.mongodb import error_logs_collection

def _client_ip(request) -> Optional[str]:
    xff = request.headers.get("x-forwarded-for") or request.headers.get("X-Forwarded-For")
    if xff:
        return xff.split(",")[0].strip()
    return getattr(request.client, "host", None)

async def log_error_to_mongo(
    *,
    request,
    status_code: int,
    detail: Any,
    user_id: Optional[str],
    exc: Exception,
    handler: Optional[str] = None
) -> None:
    try:
        if isinstance(detail, dict):
            err_type = detail.get("error_type") or type(exc).__name__
        else:
            err_type = type(exc).__name__

        doc = {
            "timestamp": datetime.now(timezone.utc),
            "status_code": status_code,
            "detail": detail,
            "error_type": err_type,
            "route": str(request.url.path),
            "method": request.method,
            "query": dict(request.query_params or {}),
            "ip": _client_ip(request),
            "user_agent": request.headers.get("user-agent"),
            "user_id": user_id,
        }
        if handler:
            doc["handler"] = handler

        await error_logs_collection.insert_one(doc)
    except Exception:
        pass