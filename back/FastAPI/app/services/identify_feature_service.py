# app/services/identify_feature_service.py
from fastapi import HTTPException, Request
from app.utils.logger import logger
from app.db.mongodb import itentify_all_collection, searchlog_collection
from app.db.models import SearchLog
from pymongo import ASCENDING
import re

# ──────────────────────────────────────────────
# 특징 기반 알약 검색
# ──────────────────────────────────────────────
async def fetch_pills_by_features(
    request: Request,
    item_seq: str = None, 
    print_front: str = None,
    print_back: str = None,
    drug_shape: str = None,
    color_class1: str = None,
    user_id: str = None
):
    try:
        query_filter = {}

        if item_seq:
            query_filter["ITEM_SEQ"] = {"$regex": f"^{re.escape(item_seq)}$", "$options": "i"}

        if print_front:
            cleaned = re.escape(print_front.strip())
            query_filter["PRINT_FRONT"] = {"$regex": f".*{cleaned}.*", "$options": "i"}

        if print_back:
            cleaned = re.escape(print_back.strip())
            query_filter["PRINT_BACK"] = {"$regex": f".*{cleaned}.*", "$options": "i"}

        if drug_shape:
            cleaned = re.escape(drug_shape.strip())
            query_filter["DRUG_SHAPE"] = {"$regex": f"^{cleaned}$", "$options": "i"}

        if color_class1:
            # 색상이 쉼표나 공백으로 구분되어 있는 경우
            colors = [c.strip() for c in re.split(r'[,\s]+', color_class1.strip()) if c.strip()]
            
            if len(colors) > 1:
                # 여러 색상인 경우: 각 색상이 포함된 레코드 검색
                color_regex_list = [f".*{re.escape(color)}.*" for color in colors]
                query_filter["COLOR_CLASS1"] = {
                    "$regex": "|".join(color_regex_list), 
                    "$options": "i"
                }
            else:
                # 단일 색상인 경우
                cleaned = re.escape(colors[0])
                query_filter["COLOR_CLASS1"] = {"$regex": f".*{cleaned}.*", "$options": "i"}

        items = [item async for item in itentify_all_collection.find(query_filter)]

        logger.debug(f"[쿼리 조건] {query_filter}")
        logger.debug(f"[결과 수] {len(items)}")

        for item in items:
            item.pop("_id", None)

        # 로그 기록
        query_log = {"source": "identify"}
        if item_seq: query_log["item_seq"] = item_seq
        if print_front: query_log["print_front"] = print_front
        if print_back: query_log["print_back"] = print_back
        if drug_shape: query_log["drug_shape"] = drug_shape
        if color_class1: query_log["color_class1"] = color_class1

        log = SearchLog(
            user_id=user_id,
            query=query_log,
            results={"items": items}
        )
        await searchlog_collection.insert_one(log.model_dump())

        logger.debug(f"🔍 feature search (from DB) | user={request.client.host} | count={len(items)}")
        return items

    except Exception as e:
        logger.error(f"❌ DB 검색 실패: {str(e)}")
        raise HTTPException(status_code=500, detail="DB 조회 오류가 발생했습니다.")

    
