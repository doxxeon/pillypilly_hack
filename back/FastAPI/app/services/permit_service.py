# app/services/permit_service.py
from fastapi import HTTPException, Request
from typing import List
from app.db.mongodb import (
    permit_info_all_collection, 
    permit_detail_collection, 
    searchlog_collection
)
from app.db.models import SearchLog
from app.utils.logger import logger
import re


# ──────────────────────────────────────────────
# 허가 상세 정보 조회
# ──────────────────────────────────────────────
async def get_permit_detail(item_seq: str) -> dict:
    try:
        result = await permit_detail_collection.find_one({"ITEM_SEQ": item_seq})
        if not result:
            return {}
        result.pop("_id", None)
        return result
    except Exception as e:
        logger.error(f"permit_detail 조회 실패: {e}")
        raise HTTPException(status_code=500, detail="permit_detail DB 조회 중 오류")


# ──────────────────────────────────────────────
# 허가 목록 정보 조회
# ──────────────────────────────────────────────
async def get_permit_list(item_seq: str) -> dict:
    try:
        result = await permit_info_all_collection.find_one({"ITEM_SEQ": item_seq})
        if not result:
            return {}

        return {
            "itemSeq": result.get("ITEM_SEQ", ""),
            "itemName": result.get("ITEM_NAME", ""),
            "entpName": result.get("ENTP_NAME", ""),
            "imageUrl": result.get("BIG_PRDT_IMG_URL", ""),
            "specltyPblc": result.get("SPCLTY_PBLC", ""),
            "prductType": result.get("PRDUCT_TYPE", ""),
            "cancleDate": result.get("CANCEL_DATE", ""),
            "cancleName": result.get("CANCEL_NAME", "")
        }
    except Exception as e:
        logger.error(f"permit_list 조회 실패: {e}")
        raise HTTPException(status_code=500, detail="permit_list DB 조회 중 오류")


# ──────────────────────────────────────────────
# 허가 통합 조회
# ──────────────────────────────────────────────
async def get_permit_combined(item_seq: str) -> dict:
    try:
        permit_detail = await get_permit_detail(item_seq)
        permit_list = await get_permit_list(item_seq)

        return {
            "permitDetail": permit_detail or {},
            "permitList": permit_list or {}
        }

    except Exception as e:
        logger.error(f"의약품 통합 조회 실패: {e}")
        raise HTTPException(status_code=500, detail="permit 통합 조회 중 오류")


# ──────────────────────────────────────────────
# 이미지 검색 요약 조회
# ──────────────────────────────────────────────
async def get_permit_summary(item_seq: str) -> dict:
    try:
        item = await permit_info_all_collection.find_one({"ITEM_SEQ": item_seq})
        if not item:
            logger.warning(f"item_seq {item_seq}에 해당하는 항목 없음")
            return {}

        item.pop("_id", None)
        return {
            "itemSeq": item.get("ITEM_SEQ", ""),
            "itemName": item.get("ITEM_NAME", ""),
            "entpName": item.get("ENTP_NAME", ""),
            "imageUrl": item.get("BIG_PRDT_IMG_URL", "")
        }

    except Exception as e:
        logger.error(f"get_permit_summary 실패: {str(e)}")
        raise HTTPException(status_code=500, detail="permit_summary DB 조회 중 오류")


# ──────────────────────────────────────────────
# 표준코드로 item_seq 검색
# ──────────────────────────────────────────────
async def get_item_seq_by_standard_code(standard_code: str) -> List[str]:
    """표준코드로 item_seq 목록을 반환 (쉼표로 구분된 여러 코드 지원)"""
    try:
        if not standard_code:
            raise HTTPException(status_code=400, detail="표준코드가 필요합니다.")
        
        # 쉼표로 구분된 표준코드들을 리스트로 변환
        standard_codes = [code.strip() for code in standard_code.split(",") if code.strip()]
        # 정규식 기반 OR 검색
        regex_filters = []
        for code in standard_codes:
            pattern = re.compile(f"(^|,\\s*){re.escape(code)}(,|$)", re.IGNORECASE)
            regex_filters.append({"STANDARD_CODE": {"$regex": pattern}})
        
        query_filter = {"$or": regex_filters}
        
        # DB 검색
        results_cursor = permit_detail_collection.find(query_filter, {"ITEM_SEQ": 1, "STANDARD_CODE": 1})
        item_seqs = []
        found_codes = []
        
        async for doc in results_cursor:
            if doc.get("ITEM_SEQ"):
                item_seqs.append(doc["ITEM_SEQ"])
                found_codes.append(doc.get("STANDARD_CODE", "N/A"))
        
        return item_seqs
        
    except Exception as e:
        logger.error(f"표준코드 기반 item_seq 검색 실패: {e}")
        raise HTTPException(status_code=500, detail="표준코드 기반 검색 중 오류")


# ──────────────────────────────────────────────
# 보험코드로 item_seq 검색
# ──────────────────────────────────────────────
async def get_item_seq_by_edi_code(edi_code: str) -> List[str]:
    """보험코드로 item_seq 목록을 반환"""
    try:
        if not edi_code:
            raise HTTPException(status_code=400, detail="보험코드가 필요합니다.")
        
        query_filter = {"EDI_CODE": edi_code}
        
        # DB 검색
        results_cursor = permit_detail_collection.find(query_filter, {"ITEM_SEQ": 1})
        item_seqs = []
        async for doc in results_cursor:
            if doc.get("ITEM_SEQ"):
                item_seqs.append(doc["ITEM_SEQ"])
        
        return item_seqs
        
    except Exception as e:
        logger.error(f"보험코드 기반 item_seq 검색 실패: {e}")
        raise HTTPException(status_code=500, detail="보험코드 기반 검색 중 오류")


# ──────────────────────────────────────────────
# 통합 검색 (키워드 기반)
# ──────────────────────────────────────────────
async def search_permit_by_keywords(
    request: Request,
    keyword: str,
    user_id: str
):
    try:
        spaced_keyword = re.sub(r'([a-z])([A-Z])', r'\1 \2', keyword)

        keyword_list = [k.strip() for k in re.split(r"[,\s]+", spaced_keyword) if len(k.strip()) >= 2]

        if not keyword_list:
            raise HTTPException(status_code=400, detail="검색어는 2자 이상이어야 합니다.")

        query_filter = {"$or": []}
        for kw in keyword_list:
            query_filter["$or"].extend([
                {"ITEM_NAME": {"$regex": f".*{re.escape(kw)}.*", "$options": "i"}},
                {"ITEM_ENG_NAME": {"$regex": f".*{re.escape(kw)}.*", "$options": "i"}},
                {"ITEM_INGR_NAME": {"$regex": f".*{re.escape(kw)}.*", "$options": "i"}},
                {"ITEM_ENG_INGR_NAME": {"$regex": f".*{re.escape(kw)}.*", "$options": "i"}}
            ])

        # DB 검색
        results_cursor = permit_info_all_collection.find(query_filter)
        results = []
        async for doc in results_cursor:
            doc.pop("_id", None)
            results.append({
                "itemSeq": doc.get("ITEM_SEQ", ""),
                "itemName": doc.get("ITEM_NAME", ""),
                "entpName": doc.get("ENTP_NAME", ""),
                "imageUrl": doc.get("BIG_PRDT_IMG_URL", "")
            })

        log = SearchLog(
            user_id=user_id,
            query={"source": "keyword", "keyword": keyword},
            results={"items": results}
        )
        await searchlog_collection.insert_one(log.model_dump())

        logger.debug(f"[키워드 통합검색] | user={request.client.host} | keyword='{keyword}' | count={len(results)}")
        return {"items": results}

    except Exception as e:
        logger.error(f"통합검색 실패: {str(e)}")
        raise HTTPException(status_code=500, detail="통합검색 오류 발생")