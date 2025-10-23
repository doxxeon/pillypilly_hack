from fastapi import APIRouter, HTTPException, Request, Depends
from typing import Callable, Awaitable, Dict, Any
from app.services.dur_service import (
    get_dur_elderly,
    get_dur_age,
    get_dur_dosage,
    get_dur_pregnant,
    get_dur_term,
    get_dur_combination,
)
from app.core.dependencies import get_current_user
from app.db.crud.user_auth import upsert_anonymous_user


router = APIRouter()


# 카테고리별 함수 매핑 (한글/영문/동의어 지원)
_CATEGORY_HANDLERS: Dict[str, Callable[[str], Awaitable[Any]]] = {
    # 병용금기
    "combination": get_dur_combination,
    "병용금기": get_dur_combination,
    # 임부금기
    "pregnant": get_dur_pregnant,
    "임부금기": get_dur_pregnant,
    # 노인금기
    "elderly": get_dur_elderly,
    "노인금기": get_dur_elderly,
    # 연령주의
    "age": get_dur_age,
    "연령": get_dur_age,
    "특정연령대": get_dur_age,
    # 용량주의
    "dosage": get_dur_dosage,
    "용량주의": get_dur_dosage,
    "용량": get_dur_dosage,
    # 투여기간주의
    "term": get_dur_term,
    "투여기간": get_dur_term,
    "투여기간주의": get_dur_term,
}


def _normalize_category(raw: str) -> str:
    return (raw or "").strip().lower()


@router.get("/dur", summary="DUR 단일 유형 조회")
async def get_dur_by_category(
    request: Request,
    category: str,
    item_seq: str,
    user_id: str = Depends(get_current_user),
):
    """
    금기 카테고리(영문/한글) + item_seq   
    - 예시: /api/v3/dur?category=elderly&item_seq=1234567890   
    - 예시: /api/v3/dur?category=임부금기&item_seq=1234567890   
    """
    await upsert_anonymous_user(user_id, request)

    key = _normalize_category(category)
    handler = _CATEGORY_HANDLERS.get(key)
    if handler is None:
        allowed = sorted(set(_CATEGORY_HANDLERS.keys()))
        raise HTTPException(
            status_code=400,
            detail={
                "message": "지원하지 않는 DUR 카테고리입니다.",
                "allowed": allowed,
            },
        )

    try:
        data = await handler(item_seq)
        count = (len(data) if isinstance(data, list) else None)
        return {
            "category": category,
            "item_seq": item_seq,
            "count": count,
            "data": data,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DUR 조회 중 오류: {e}")


