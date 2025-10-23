# FastAPI\app\api\v3\identify_feature_based.py

from fastapi import APIRouter, Request, Query, Depends, HTTPException
from app.services.identify_feature_service import fetch_pills_by_features
from app.core.dependencies import get_current_user
from app.db.crud.user_auth import upsert_anonymous_user
router = APIRouter()

@router.get("/feature-search", summary="알약 외형 기반 식별 검색")
async def identify_by_feature(
    request: Request,
    item_seq: str = Query(None, description="품목기준 일련번호"),
    print_front: str = Query(None, description="알약 앞면 문자"),
    print_back: str = Query(None, description="알약 뒷면 문자"),
    drug_shape: str = Query(None, description="알약 모양"),
    color_class1: str = Query(None, description="알약 색상"),
    user_id: str = Depends(get_current_user)
):
    await upsert_anonymous_user(user_id, request)
    try:
        # 예외처리
        if not any([item_seq, print_front, print_back, drug_shape, color_class1]):
            raise HTTPException(status_code=400, detail="최소 한 가지 이상의 검색 조건이 필요합니다.")

        result = await fetch_pills_by_features(
            request,
            item_seq=item_seq,
            print_front=print_front,
            print_back=print_back,
            drug_shape=drug_shape,
            color_class1=color_class1,
            user_id=user_id
        )
        return {
            "message": "알약 식별검색",
            "results": result
        }

    except Exception:
        # 예외처리
        raise