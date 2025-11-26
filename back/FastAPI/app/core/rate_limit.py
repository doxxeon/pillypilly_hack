# app/core/rate_limit.py
import time
import asyncio
from typing import Deque, Dict, Tuple, Optional
from collections import defaultdict, deque

from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from app.services.token_service import verify_access_token


# ──────────────────────────────────────────────
# 공통: 요청자 식별
# ──────────────────────────────────────────────
def _client_ip(request: Request) -> str:
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return getattr(request.client, "host", "0.0.0.0")

def _resolve_user_id(request: Request) -> Optional[str]:
    # Authorization: Bearer <access_token> → sub(= 익명 UUID)
    auth = request.headers.get("authorization") or request.headers.get("Authorization")
    if auth and auth.lower().startswith("bearer "):
        token = auth.split(" ", 1)[1].strip()
        try:
            payload = verify_access_token(token)
            sub = payload.get("sub")
            if sub:
                return str(sub)
        except Exception:
            pass
    # 익명 쿠키(토큰 누락 대비)
    uid = request.cookies.get("anonymous_id")
    if uid:
        return uid
    return None


# ──────────────────────────────────────────────
# 인메모리 레이트리미터
# ──────────────────────────────────────────────
class InMemoryRateLimiter:
    def __init__(self) -> None:
        self._buckets: Dict[str, Deque[float]] = defaultdict(deque)
        self._locks: Dict[str, asyncio.Lock] = defaultdict(asyncio.Lock)

    async def hit(self, key: str, limit: int, window_s: int) -> Tuple[bool, int, int, int]:
        """
        반환: (허용 여부, retry_after_sec, remaining, reset_sec)
        """
        now = time.time()
        lock = self._locks[key]
        async with lock:
            dq = self._buckets[key]
            cutoff = now - window_s
            while dq and dq[0] <= cutoff:
                dq.popleft()

            if len(dq) >= limit:
                retry_after = int(max(1, window_s - (now - dq[0])))
                remaining = 0
                reset = retry_after
                return False, retry_after, remaining, reset

            dq.append(now)
            remaining = max(0, limit - len(dq))
            reset = int(max(0, window_s - (now - (dq[0] if dq else now))))
            return True, 0, remaining, reset


RATE_LIMITER = InMemoryRateLimiter()


# ──────────────────────────────────────────────
# 전역 미들웨어
# ──────────────────────────────────────────────
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(
        self, app,
        *,
        user_limit: int = 120, user_window: int = 60,
        ip_limit: int = 60, ip_window: int = 60,
    ):
        super().__init__(app)
        self.user_limit = user_limit
        self.user_window = user_window
        self.ip_limit = ip_limit
        self.ip_window = ip_window

    async def dispatch(self, request: Request, call_next):
        # Admin 페이지는 rate limiting 완화
        if request.url.path.startswith("/admin"):
            admin_user_limit = self.user_limit * 3  # 300회
            admin_ip_limit = self.ip_limit * 2      # 120회
            
            # 사용자 제한
            user_id = _resolve_user_id(request)
            if user_id:
                ok, retry_after, remaining, reset = await RATE_LIMITER.hit(
                    key=f"user:{user_id}:admin",
                    limit=admin_user_limit,
                    window_s=self.user_window,
                )
                if not ok:
                    raise HTTPException(
                        status_code=429,
                        detail={
                            "code": "RATE_LIMITED",
                            "message": "Too many requests (admin user)",
                            "context": {
                                "scope": "admin_user",
                                "limit": admin_user_limit,
                                "window": self.user_window,
                                "ttl": retry_after,
                                "key": user_id,
                            },
                        },
                        headers={"Retry-After": str(retry_after)},
                    )

            # IP 제한 (Admin 페이지용)
            ip = _client_ip(request)
            ok, retry_after, remaining_ip, reset_ip = await RATE_LIMITER.hit(
                key=f"ip:{ip}:admin",
                limit=admin_ip_limit,
                window_s=self.ip_window,
            )
            if not ok:
                raise HTTPException(
                    status_code=429,
                    detail={
                        "code": "RATE_LIMITED",
                        "message": "Too many requests (admin ip)",
                        "context": {
                            "scope": "admin_ip",
                            "limit": admin_ip_limit,
                            "window": self.ip_window,
                            "ttl": retry_after,
                            "key": ip,
                        },
                    },
                    headers={"Retry-After": str(retry_after)},
                )

            # 통과 → 응답에 헤더 부가
            response = await call_next(request)
            if user_id:
                response.headers.setdefault("X-RateLimit-Limit-AdminUser", str(admin_user_limit))
                response.headers.setdefault("X-RateLimit-Window-AdminUser", str(self.user_window))
            response.headers.setdefault("X-RateLimit-Limit-AdminIP", str(admin_ip_limit))
            response.headers.setdefault("X-RateLimit-Window-AdminIP", str(self.ip_window))
            return response

        user_id = _resolve_user_id(request)
        ip = _client_ip(request)

        if user_id:
            ok, retry_after, remaining, reset = await RATE_LIMITER.hit(
                key=f"user:{user_id}:global",
                limit=self.user_limit,
                window_s=self.user_window,
            )
            if not ok:
                raise HTTPException(
                    status_code=429,
                    detail={
                        "code": "RATE_LIMITED",
                        "message": "Too many requests (user)",
                        "context": {
                            "scope": "user",
                            "limit": self.user_limit,
                            "window": self.user_window,
                            "ttl": retry_after,
                            "key": user_id,
                        },
                    },
                    headers={"Retry-After": str(retry_after)},
                )

        ok, retry_after, remaining_ip, reset_ip = await RATE_LIMITER.hit(
            key=f"ip:{ip}:global",
            limit=self.ip_limit,
            window_s=self.ip_window,
        )
        if not ok:
            raise HTTPException(
                status_code=429,
                detail={
                    "code": "RATE_LIMITED",
                    "message": "Too many requests (ip)",
                    "context": {
                        "scope": "ip",
                        "limit": self.ip_limit,
                        "window": self.ip_window,
                        "ttl": retry_after,
                        "key": ip,
                    },
                },
                headers={"Retry-After": str(retry_after)},
            )

        response = await call_next(request)
        if user_id:
            response.headers.setdefault("X-RateLimit-Limit-User", str(self.user_limit))
            response.headers.setdefault("X-RateLimit-Window-User", str(self.user_window))
        response.headers.setdefault("X-RateLimit-Limit-IP", str(self.ip_limit))
        response.headers.setdefault("X-RateLimit-Window-IP", str(self.ip_window))
        return response


# ──────────────────────────────────────────────
# 라우트 전용 레이트리밋
# ──────────────────────────────────────────────
def rate_limit_user(scope: str, limit: int, window_s: int):
    async def _dep(request: Request):
        user_id = _resolve_user_id(request)
        key = f"user:{(user_id or _client_ip(request))}:{scope}"
        ok, retry_after, remaining, reset = await RATE_LIMITER.hit(key, limit, window_s)
        if not ok:
            raise HTTPException(
                status_code=429,
                detail={
                    "code": "RATE_LIMITED",
                    "message": "Too many requests (user)",
                    "context": {
                        "scope": scope,
                        "limit": limit,
                        "window": window_s,
                        "ttl": retry_after,
                        "key": user_id or _client_ip(request),
                    },
                },
                headers={"Retry-After": str(retry_after)},
            )
    return _dep

def rate_limit_ip(scope: str, limit: int, window_s: int):
    async def _dep(request: Request):
        ip = _client_ip(request)
        key = f"ip:{ip}:{scope}"
        ok, retry_after, remaining, reset = await RATE_LIMITER.hit(key, limit, window_s)
        if not ok:
            raise HTTPException(
                status_code=429,
                detail={
                    "code": "RATE_LIMITED",
                    "message": "Too many requests (ip)",
                    "context": {
                        "scope": scope,
                        "limit": limit,
                        "window": window_s,
                        "ttl": retry_after,
                        "key": ip,
                    },
                },
                headers={"Retry-After": str(retry_after)},
            )
    return _dep


# ──────────────────────────────────────────────
# 동시성 제한(세마포어)
# ──────────────────────────────────────────────
_GLOBAL_SEMAPHORES: Dict[str, asyncio.Semaphore] = {}
_USER_SEMAPHORES: Dict[tuple, asyncio.Semaphore] = {}

def concurrency_limit(scope: str, *, per_user: int = 1, global_limit: int = 8):
    """
    사용 예: Depends(concurrency_limit("image_search", per_user=1, global_limit=8))
    """
    global _GLOBAL_SEMAPHORES, _USER_SEMAPHORES
    _GLOBAL_SEMAPHORES.setdefault(scope, asyncio.Semaphore(global_limit))

    async def _dep(request: Request):
        global_sem = _GLOBAL_SEMAPHORES[scope]
        user_key = _resolve_user_id(request) or _client_ip(request)
        user_sem_key = (scope, user_key)
        _USER_SEMAPHORES.setdefault(user_sem_key, asyncio.Semaphore(per_user))
        user_sem = _USER_SEMAPHORES[user_sem_key]

        got_global = False
        got_user = False
        try:
            # 대기 n초, 타임아웃 초과 시 429
            await asyncio.wait_for(global_sem.acquire(), timeout=2.0)
            got_global = True
        except asyncio.TimeoutError:
            raise HTTPException(
                status_code=429,
                detail={
                    "code": "CONCURRENCY_LIMIT",
                    "message": "Too many concurrent requests (global)",
                    "context": {"scope": scope, "global_limit": global_limit},
                },
                headers={"Retry-After": "1"},
            )

        try:
            await asyncio.wait_for(user_sem.acquire(), timeout=5.0)
            got_user = True
        except asyncio.TimeoutError:
            # 글로벌 해제 후 에러
            if got_global:
                global_sem.release()
            raise HTTPException(
                status_code=429,
                detail={
                    "code": "CONCURRENCY_LIMIT",
                    "message": "Too many concurrent requests (user)",
                    "context": {"scope": scope, "per_user": per_user, "key": user_key},
                },
                headers={"Retry-After": "1"},
            )

        try:
            yield
        finally:
            if got_user:
                user_sem.release()
            if got_global:
                global_sem.release()
    return _dep
