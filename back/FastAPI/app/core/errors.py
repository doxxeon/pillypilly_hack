# app/core/errors.py
from typing import Any, Dict, Optional, List
from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from app.utils.logger import logger_error
from app.services.token_service import verify_access_token
import json

# 예외 정의
class ModelInferenceError(HTTPException):
    def __init__(
        self,
        message: str,
        *,
        code: str = "MODEL_INFER_FAIL",
        status_code: int = 422,
        context: Optional[Dict[str, Any]] = None,
    ):
        super().__init__(status_code=status_code, detail={
            "code": code, "message": message, "context": context or {}
        })

class ExternalApiError(HTTPException):
    def __init__(
        self,
        message: str,
        *,
        code: str = "UPSTREAM_ERROR",
        status_code: int = 502,
        context: Optional[Dict[str, Any]] = None,
    ):
        super().__init__(status_code=status_code, detail={
            "code": code, "message": message, "context": context or {}
        })

# 에러 로그 저장
from app.db.crud.error_log import log_error_to_mongo

VALIDATION_ERROR_MAX_ITEMS = 10

def _user_from_token(request: Request) -> Optional[str]:
    auth = request.headers.get("authorization") or request.headers.get("Authorization")
    if not auth or not auth.lower().startswith("bearer "):
        return None
    token = auth.split(" ", 1)[1].strip()
    try:
        payload = verify_access_token(token)
        return payload.get("sub")
    except Exception:
        return None

async def _resolve_user_id(request: Request, exc: Optional[Exception] = None) -> Optional[str]:
    # 1) 액세스 토큰 sub(로그인/익명 UUID)
    uid = _user_from_token(request)
    if uid:
        return uid
    # 2) 익명 사용자 식별: anonymous_id 쿠키
    uid = request.cookies.get("anonymous_id")
    if uid:
        return uid
    # 3) 레이트리밋 등에서 detail.context.key 제공 시 보정
    if exc and isinstance(exc, HTTPException) and isinstance(exc.detail, dict):
        ctx = exc.detail.get("context")
        if isinstance(ctx, dict) and "key" in ctx:
            return str(ctx["key"])
    return None

def _attach_error_meta(detail: Any, exc: Exception) -> Dict[str, Any]:
    meta = {"error_type": type(exc).__name__}
    if isinstance(detail, dict):
        return {**detail, **meta}
    return {"message": str(detail), **meta}

async def _safe_log_to_mongo(
    *,
    handler_name: str,
    request: Request,
    user_id: Optional[str],
    exc: Exception,
    status_code: int,
    detail: Dict[str, Any],
) -> None:
    try:
        await log_error_to_mongo(
            request=request,
            user_id=user_id,
            exc=exc,
            status_code=status_code,
            detail=detail,
            handler=handler_name,
        )
    except TypeError:
        await log_error_to_mongo(
            request=request,
            user_id=user_id,
            exc=exc,
            status_code=status_code,
            detail=detail,
        )

def _file_log(
    *,
    handler_name: str,
    request: Request,
    user_id: Optional[str],
    status_code: int,
    detail: Dict[str, Any],
):
    # request_id는 파일 로그에서 제거
    record = {
        "handler": handler_name,
        "status": status_code,
        "route": str(request.url.path),
        "method": request.method,
        "user_id": user_id,
        "detail": detail,
    }
    logger_error.error(json.dumps(record, ensure_ascii=False, default=str))

# ▶ FastAPI 핸들러 등록
def register_exception_handlers(app):
    @app.exception_handler(ModelInferenceError)
    async def _model_error(request: Request, exc: ModelInferenceError):
        user_id = await _resolve_user_id(request, exc)
        detail_with_meta = _attach_error_meta(exc.detail, exc)
        _file_log(handler_name="_model_error", request=request, user_id=user_id,
                  status_code=exc.status_code, detail=detail_with_meta)
        await _safe_log_to_mongo(handler_name="_model_error", request=request, user_id=user_id,
                                 exc=exc, status_code=exc.status_code, detail=detail_with_meta)
        return JSONResponse(status_code=exc.status_code, content={"error": detail_with_meta})

    @app.exception_handler(ExternalApiError)
    async def _external_error(request: Request, exc: ExternalApiError):
        user_id = await _resolve_user_id(request, exc)
        detail_with_meta = _attach_error_meta(exc.detail, exc)
        _file_log(handler_name="_external_error", request=request, user_id=user_id,
                  status_code=exc.status_code, detail=detail_with_meta)
        await _safe_log_to_mongo(handler_name="_external_error", request=request, user_id=user_id,
                                 exc=exc, status_code=exc.status_code, detail=detail_with_meta)
        return JSONResponse(status_code=exc.status_code, content={"error": detail_with_meta})

    @app.exception_handler(RequestValidationError)
    async def _validation_error(request: Request, exc: RequestValidationError):
        user_id = await _resolve_user_id(request, exc)
        errs: List[Dict[str, Any]] = exc.errors()
        detail = {
            "code": "REQUEST_VALIDATION_ERROR",
            "message": "Invalid request",
            "context": errs[:VALIDATION_ERROR_MAX_ITEMS],
        }
        detail_with_meta = _attach_error_meta(detail, exc)
        _file_log(handler_name="_validation_error", request=request, user_id=user_id,
                  status_code=422, detail=detail_with_meta)
        await _safe_log_to_mongo(handler_name="_validation_error", request=request, user_id=user_id,
                                 exc=exc, status_code=422, detail=detail_with_meta)
        return JSONResponse(status_code=422, content={"error": detail_with_meta})

    @app.exception_handler(HTTPException)
    async def _http_error(request: Request, exc: HTTPException):
        user_id = await _resolve_user_id(request, exc)
        base_detail = exc.detail if isinstance(exc.detail, dict) else {"message": str(exc.detail)}
        detail_with_meta = _attach_error_meta(base_detail, exc)
        
        if exc.status_code == 404:
            logger_error.info(json.dumps({
                "handler": "_http_error",
                "status": exc.status_code,
                "route": str(request.url.path),
                "method": request.method,
                "user_id": user_id,
                "detail": detail_with_meta,
            }, ensure_ascii=False, default=str))
        else:
            _file_log(handler_name="_http_error", request=request, user_id=user_id,
                      status_code=exc.status_code, detail=detail_with_meta)
        
        await _safe_log_to_mongo(handler_name="_http_error", request=request, user_id=user_id,
                                 exc=exc, status_code=exc.status_code, detail=detail_with_meta)
        return JSONResponse(status_code=exc.status_code, content={"error": detail_with_meta})

    @app.exception_handler(Exception)
    async def _unexpected_error(request: Request, exc: Exception):
        user_id = await _resolve_user_id(request, exc)
        detail = {"code": "UNEXPECTED", "message": "Unexpected server error"}
        detail_with_meta = _attach_error_meta(detail, exc)
        _file_log(handler_name="_unexpected_error", request=request, user_id=user_id,
                  status_code=500, detail=detail_with_meta)
        await _safe_log_to_mongo(handler_name="_unexpected_error", request=request, user_id=user_id,
                                 exc=exc, status_code=500, detail=detail_with_meta)
        return JSONResponse(status_code=500, content={"error": detail_with_meta})

__all__ = [
    "ModelInferenceError",
    "ExternalApiError",
    "register_exception_handlers",
]
