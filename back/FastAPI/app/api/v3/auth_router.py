#FastAPI\app\api\v3\auth_router.py

import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Request, Response, HTTPException, Depends
from fastapi.responses import JSONResponse

from app.db.mongodb import refresh_tokens_collection
from app.services.token_service import (
    create_access_token, create_refresh_token,
    verify_refresh_token, hash_refresh_token
)
from app.db.crud.user_auth import upsert_anonymous_user
from app.core.rate_limit import rate_limit_ip
from app.utils.logger import logger_auth, logger


router = APIRouter()

# 캐시 없는 경우 새 UUID 발급(쿠키 저장) — 기존 동작 유지
def _get_or_set_anon_cookie(request: Request, response: Response) -> str:
    anon_id = request.cookies.get("anonymous_id")
    if not anon_id:
        anon_id = str(uuid.uuid4())
        response.set_cookie(
            key="anonymous_id",
            value=anon_id,
            max_age=60 * 60 * 24 * 365,  # 1년
            httponly=True,
            samesite="Lax"
        )
    return anon_id

@router.post("/auth/token", summary="익명 사용자: Access+Refresh 발급",
             dependencies=[Depends(rate_limit_ip("auth_issue", limit=30, window_s=600))],  # 10분에 30회/IP
             )
async def issue_tokens(request: Request, response: Response):
    # 1) 사용자 식별(쿠키 없으면 새 UUID 발급 → user_id로 사용)
    user_id = _get_or_set_anon_cookie(request, response)

    # 2) 활성 세션 제한/정리
    now = datetime.now(timezone.utc)
    max_sessions = 3  # ← 원하는 값(진단 시 1로 낮춰서 테스트 추천)

    pipeline = [
        {"$match": {
            "user_id": user_id,
            "revoked": False,
            "expires_at": {"$gt": now},
        }},
        {"$group": {
            "_id": "$sid",
            "first_created_at": {"$min": "$created_at"},
        }},
        {"$sort": {"first_created_at": 1}},
    ]
    active_by_sid = await refresh_tokens_collection.aggregate(pipeline).to_list(length=None)

    over = len(active_by_sid) + 1 - max_sessions
    revoked_sids = []
    if over > 0:
        revoked_sids = [d["_id"] for d in active_by_sid[:over]]
        res = await refresh_tokens_collection.update_many(
            {"sid": {"$in": revoked_sids}, "revoked": False},
            {"$set": {"revoked": True}}
        )
        logger_auth.debug(f"[AUTH] REVOKE_OLD_SESSIONS user_id={user_id} "
                         f"to_revoke={revoked_sids} matched={res.matched_count} modified={res.modified_count}")
    else:
        logger_auth.debug(f"[AUTH] NO_REVOKE_NEEDED user_id={user_id} "
                         f"active={len(active_by_sid)} max={max_sessions}")

    # 3) 새 세션 발급
    sid = str(uuid.uuid4())
    access = create_access_token(user_id=user_id, sid=sid)
    refresh = create_refresh_token(user_id=user_id, sid=sid)
    payload = verify_refresh_token(refresh)
    jti = payload["jti"]
    exp = datetime.fromtimestamp(payload["exp"], tz=timezone.utc)

    await refresh_tokens_collection.insert_one({
        "jti": jti,
        "sid": sid,
        "user_id": user_id,
        "token_hash": hash_refresh_token(refresh),
        "expires_at": exp,
        "revoked": False,
        "created_at": now,
        "last_used_at": now,
        "user_agent": request.headers.get("user-agent"),
        "ip": request.client.host,
    })

    # 6) 사용자 로그 업서트
    await upsert_anonymous_user(user_id, request)
    logger.debug(f"📌사용자 Access+Refresh 발급 user_id={user_id}")

    return {"access_token": access, "refresh_token": refresh, "token": access, "user_id": user_id, "sid": sid}

@router.post("/auth/refresh", summary="리프레시로 Access 재발급 (회전)")
async def refresh_tokens(request: Request, body: dict):
    # 1) 클라이언트가 보낸 refresh 토큰 검증
    refresh = body.get("refresh_token")
    if not refresh:
        raise HTTPException(status_code=400, detail="refresh_token 필요",
                             dependencies=[Depends(rate_limit_ip("auth_refresh", limit=30, window_s=600))],
                            )

    payload = verify_refresh_token(refresh)
    user_id = payload["sub"]
    sid = payload["sid"]
    jti = payload["jti"]

    # ✅ now 한 번만 계산
    now = datetime.now(timezone.utc)

    # 2) DB에서 유효 refresh인지 확인(해시 비교 + 미폐기 + 미만료)
    doc = await refresh_tokens_collection.find_one({"jti": jti, "revoked": False})
    if not doc:
        raise HTTPException(status_code=401, detail="유효하지 않은 세션")
    # 해시 비교
    if doc.get("token_hash") != hash_refresh_token(refresh):
        raise HTTPException(status_code=401, detail="토큰 불일치")

    # ✅ expires_at이 naive인 경우 UTC로 보정 후 비교
    expires_at = doc.get("expires_at")
    if expires_at is None:
        raise HTTPException(status_code=401, detail="만료된 세션")

    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)

    if expires_at < now:
        raise HTTPException(status_code=401, detail="만료된 세션")

    # 3) 리프레시 회전(rotate) – 보안 강화를 위해 기존 jti 폐기 후 신규 발급
    # ✅ revoke 하면서 마지막 사용 시각 갱신
    await refresh_tokens_collection.update_one(
        {"jti": jti},
        {"$set": {"revoked": True, "last_used_at": now}}
    )

    new_access = create_access_token(user_id=user_id, sid=sid)
    new_refresh = create_refresh_token(user_id=user_id, sid=sid)  # 새 jti
    new_payload = verify_refresh_token(new_refresh)
    new_jti = new_payload["jti"]
    new_exp = datetime.fromtimestamp(new_payload["exp"], tz=timezone.utc)

    await refresh_tokens_collection.insert_one({
        "jti": new_jti,
        "sid": sid,
        "user_id": user_id,
        "token_hash": hash_refresh_token(new_refresh),
        "expires_at": new_exp,
        "revoked": False,
        "created_at": now,
        "last_used_at": now,
        "user_agent": request.headers.get("user-agent"),
        "ip": request.client.host,
    })

    logger.debug(f"😉사용자 acess 재발급(회전 user_id={user_id}")

    return {"access_token": new_access, "refresh_token": new_refresh, "token": new_access, "user_id": user_id, "sid": sid}

@router.post("/auth/logout", summary="세션 종료(Refresh 폐기)")
async def logout(body: dict):
    # 클라이언트가 보유중인 refresh를 폐기
    refresh = body.get("refresh_token")
    if not refresh:
        raise HTTPException(status_code=400, detail="refresh_token 필요")

    try:
        payload = verify_refresh_token(refresh)
        jti = payload["jti"]
    except Exception:
        # 형식이 이상해도 조용히 처리(보안상 정보 노출 방지)
        return JSONResponse({"ok": True})

    await refresh_tokens_collection.update_one({"jti": jti}, {"$set": {"revoked": True}})
    return {"ok": True}
