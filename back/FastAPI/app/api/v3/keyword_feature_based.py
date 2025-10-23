# app\api\v3\keyword_feature_based.py
from fastapi import APIRouter, Request, Query, Depends
from app.services.permit_service import search_permit_by_keywords
from app.core.dependencies import get_current_user
from app.db.crud.user_auth import upsert_anonymous_user
from datetime import datetime, timedelta
from app.db.mongodb import db, searchlog_collection

router = APIRouter()

@router.get("/keyword-search", summary="통합검색 (제품명/성분 한글/영문)")
async def permit_unified_search(
    request: Request,
    keyword: str = Query(..., description="검색 키워드 (2자 이상, 공백/쉼표 구분)"),
    user_id: str = Depends(get_current_user)
):
    await upsert_anonymous_user(user_id, request)
    results = await search_permit_by_keywords(
        request, 
        keyword,
        user_id)
    return {
        "message": "✅ 통합검색 성공",
        "results": results
    }

@router.get("/stats/top-pills", summary="알약 검색 TOP 랭크(multi)")
async def stats_top_pills(
    start: str = Query(None, description="YYYY-MM-DD (로컬 기준)"),
    end: str = Query(None, description="YYYY-MM-DD (포함, 로컬 기준)"),
    tz_offset_minutes: int = Query(0, description="클라이언트 타임존 오프셋(분, 한국: 540)"),
    limit: int = Query(20, gt=0, le=100),
    user_id: str = Depends(get_current_user)
):
    """
    search_logs에서 query.source == 'multi' 인 로그만 집계.
    - itemName별 등장 횟수 TOP N
    - 확장성: permitList의 필드를 함께 투영(상세 팝업/추후 /log 조회에 활용)
    """
    match: dict = {"query.source": "multi"}

    # 날짜 범위 → UTC로 변환
    def parse_utc(date_str: str) -> datetime:
        # 사용자가 넣은 로컬 날짜의 00:00을 UTC로
        d = datetime.strptime(date_str, "%Y-%m-%d")
        return d - timedelta(minutes=tz_offset_minutes)

    if start:
        start_utc = parse_utc(start)
        match["timestamp"] = {"$gte": start_utc}
    if end:
        # end-day 의 23:59:59.999 로컬 포함되도록 다음날 00:00 직전까지
        end_utc = (parse_utc(end) + timedelta(days=1))
        match["timestamp"] = {**match.get("timestamp", {}), "$lt": end_utc}

    pipeline = [
        {"$match": match},
        # 결과 구조에서 permitList를 투영(한 건 선택 로그 구조 가정)
        {"$project": {
            "permitList": "$results.permit.permitList",
        }},
        {"$match": {"permitList.itemName": {"$exists": True}}},
        {"$group": {
            "_id": {
                "itemName": "$permitList.itemName",
                "prductType": "$permitList.prductType",
                "entpName": "$permitList.entpName",
                "specltyPblc": "$permitList.specltyPblc",
            },
            "count": {"$sum": 1},
            "examples": {"$push": "$permitList"},  # 확장성: 상세 필드 보존
        }},
        {"$sort": {"count": -1}},
        {"$limit": limit},
    ]

    rows = await searchlog_collection.aggregate(pipeline).to_list(length=None)
    data = [{
        "itemName": r["_id"]["itemName"],
        "count": r["count"],
        "prductType": r["_id"].get("prductType"),
        "entpName": r["_id"].get("entpName"),
        "specltyPblc": r["_id"].get("specltyPblc"),
        "samples": r.get("examples", [])[:1],   # 응답 경량화 (예시 최대 3개)
    } for r in rows]

    return {"rows": data, "total": len(data)}