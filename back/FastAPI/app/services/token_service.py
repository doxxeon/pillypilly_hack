# app/services/token_service.py
# JWT 발급/검증 (Access/Refresh 분리)
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
import uuid, hmac, hashlib
from app.core.config import settings
from fastapi import HTTPException 

ALGO = settings.jwt_algorithm

# ──────────────────────────────────────────────
# 유틸리티 함수
# ──────────────────────────────────────────────
def _now():
    return datetime.now(timezone.utc)

def _hmac_sha256(secret: str, data: str) -> str:
    return hmac.new(secret.encode("utf-8"), data.encode("utf-8"), hashlib.sha256).hexdigest()

# ──────────────────────────────────────────────
# 토큰 해시 함수
# ──────────────────────────────────────────────
def hash_refresh_token(plain: str) -> str:
    return f"sha256:{_hmac_sha256(settings.jwt_refresh_secret_key, plain)}"

# ──────────────────────────────────────────────
# 액세스 토큰 생성
# ──────────────────────────────────────────────
def create_access_token(*, user_id: str, sid: str) -> str:
    exp = _now() + timedelta(minutes=settings.jwt_exp_minutes)
    payload = {
        "sub": user_id,
        "sid": sid,                 # 세션 ID로 연계
        "iss": settings.jwt_issuer,
        "iat": _now(),
        "exp": exp,
        "type": "access",
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=ALGO)

def create_refresh_token(*, user_id: str, sid: str, jti: str = None) -> str:
    exp = _now() + timedelta(days=settings.jwt_refresh_exp_days)
    payload = {
        "sub": user_id,
        "sid": sid,
        "jti": jti or str(uuid.uuid4()),  # 리프레시 고유 ID
        "iss": settings.jwt_issuer,
        "iat": _now(),
        "exp": exp,
        "type": "refresh",
    }
    return jwt.encode(payload, settings.jwt_refresh_secret_key, algorithm=ALGO)

def verify_access_token(token: str) -> dict:
    try:
        decoded = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[ALGO],
            issuer=settings.jwt_issuer,
            options={"require": ["exp", "iss", "sub", "sid"]}
        )
        if decoded.get("type") != "access":
            raise JWTError("not an access token")
        return decoded
    except JWTError as e:
        raise HTTPException(status_code=401, detail="Invalid or expired access token")

def verify_refresh_token(token: str) -> dict:
    try:
        decoded = jwt.decode(
            token,
            settings.jwt_refresh_secret_key,
            algorithms=[ALGO],
            issuer=settings.jwt_issuer,
            options={"require": ["exp", "iss", "sub", "sid", "jti"]}
        )
        if decoded.get("type") != "refresh":
            raise JWTError("not a refresh token")
        return decoded
    except JWTError as e:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

