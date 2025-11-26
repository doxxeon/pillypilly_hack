# ========================
# db/crud/user_auth.py
# JWT 인증 기반 사용자 활동 기록을 업데이트
# ========================
from datetime import datetime
from fastapi import Request
from app.db.mongodb import auth_collection
from app.utils.logger import logger_auth


async def upsert_anonymous_user(user_id: str, request: Request):
    now = datetime.now()
    existing_user = await auth_collection.find_one({"user_id": user_id})

    if existing_user:
        await auth_collection.update_one(
            {"user_id": user_id},
            {"$set": {"last_access": now}}
        )
        # 재방문 로그
        logger_auth.info(
            f"[AUTH - 재발급 사용자] USER_ID={user_id} IP={request.client.host} UA={request.headers.get('user-agent')}"
        )
    else:
        await auth_collection.insert_one({
            "user_id": user_id,
            "is_anonymous": True,
            "created_at": now,
            "last_access": now,
            "ip_address": request.client.host,
            "user_agent": request.headers.get("user-agent"),
        })
        # 신규 접속 로그
        logger_auth.info(
            f"[AUTH - 신규 사용자] USER_ID={user_id} IP={request.client.host} UA={request.headers.get('user-agent')}"
        )