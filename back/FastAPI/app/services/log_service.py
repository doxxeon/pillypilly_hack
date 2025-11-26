# app/services/log_service.py
from app.utils.formatter import seoul_now
from fastapi import Request
from typing import Dict, Any
from app.utils.logger import logger_drugs, logger_gemini, logger_favorite, logger_auth, logger

from app.db.crud.search_log import insert_search_log
from app.db.crud.favorite_log import insert_favorite_log
from app.db.crud.chatbot_log import insert_chatbot_log
from app.db.crud.user_auth import upsert_anonymous_user

# ──────────────────────────────────────────────
# 약제 정보 검색 로그
# ──────────────────────────────────────────────
async def log_to_mongo(request: Request, user_id: str, query: dict, results: dict):
    try:
        await insert_search_log(user_id, query, results)
        logger.info(f"약제 정보 로그 저장 완료 | USER_ID={user_id} | ITEM_SEQ={query.get('item_seq')}")
    except Exception as e:
        logger.error(f"약제 정보 로그 저장 실패: {str(e)}")

# ──────────────────────────────────────────────
# 즐겨찾기 로그
# ──────────────────────────────────────────────
async def log_favorite_to_mongo(request: Request, user_id: str, folder_name: str, item_seq: str, item_name: str, image_url: str, source: str = "app"):
    try:
        await insert_favorite_log(user_id, folder_name, item_seq, item_name, image_url, source)
        logger.info(f"즐겨찾기 저장 완료 | USER_ID={user_id} | 약명={item_name}")
    except Exception as e:
        logger.error(f"즐겨찾기 저장 실패: {str(e)}")

# ──────────────────────────────────────────────
# 챗봇 로그
# ──────────────────────────────────────────────
async def log_chatbot_to_mongo(request: Request, user_id: str, drug_info: Dict[str, Any], drug_summary: str, user_input: str, answer: str, source: str = "chatbot"):
    try:
        await insert_chatbot_log(user_id, drug_info, drug_summary, user_input, answer, source)
        logger_gemini.info(f"챗봇 로그 저장 완료 | USER_ID={user_id} | 입력={len(user_input)}")
    except Exception as e:
        logger_gemini.error(f"챗봇 로그 저장 실패: {str(e)}")

# ──────────────────────────────────────────────
# 사용자 인증/갱신 로그
# ──────────────────────────────────────────────
async def log_or_update_anon_user(request: Request, user_id: str):
    try:
        await upsert_anonymous_user(user_id, request)
        logger_auth.info(f"사용자 DB 저장 | USER_ID={user_id}")
    except Exception as e:
        logger_auth.error(f"사용자 저장 실패: {str(e)}")

# ──────────────────────────────────────────────
# 처방전 OCR 로그
# ──────────────────────────────────────────────
async def log_prescription_ocr_to_mongo(
    request: Request, 
    user_id: str, 
    ocr_results: list, 
    final_items: list, 
    item_seq_list: list, 
    processing_time_sec: float, 
    filename: str, 
    total_items: int
):
    try:
        from app.db.crud.prescription_model_log import insert_prescription_model_log

        await insert_prescription_model_log(
            user_id=user_id,
            ocr_results=ocr_results,
            final_items=final_items,
            item_seq_list=item_seq_list,
            processing_time_sec=processing_time_sec,
            filename=filename,
            total_items=total_items
        )
        logger.info(f"처방전 OCR 로그 저장 완료 | USER_ID={user_id} | 약품수={total_items}")
    except Exception as e:
        logger.error(f"처방전 OCR 로그 저장 실패: {str(e)}")