# app/db/crud/prescription_model_log.py
from __future__ import annotations
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from bson import ObjectId

from app.db.mongodb import (
    prescription_model_log_collection,
    prescriptions_sessions_collection,
    pill_images_collection,
)

# ──────────────────────────────────────────────
# 처방전 OCR 결과 저장
# ──────────────────────────────────────────────
async def insert_prescription_model_log(
    user_id: str,
    ocr_results: List[tuple],
    final_items: List[Dict[str, Any]],
    item_seq_list: List[str],
    processing_time_sec: float,
    filename: str,
    total_items: int
) -> None:
    now = datetime.now()

    ocr_raw_results = [
        {"보험코드": code, "약품명": name}
        for code, name in ocr_results
    ]

    keyword_mapped_items = [
        item for item in final_items
        if (
            item.get("is_keyword_mapped")
            or (item.get("item_seq") and (item.get("보험코드") in [None, ""]))
        )
    ]

    doc = {
        "user_id": user_id,
        "timestamp": now,
        "filename": filename,
        "processing_time_sec": processing_time_sec,
        "total_items": total_items,
        "ocr_raw_results": ocr_raw_results,
        "final_items": final_items,
        "item_seq_list": item_seq_list,
        "keyword_mapped_count": len(keyword_mapped_items),
        "keyword_mapped_items": keyword_mapped_items,
    }

    await prescription_model_log_collection.insert_one(doc)

# ──────────────────────────────────────────────
# 세션 생성/업서트 (처방전 OCR 이후)
# ──────────────────────────────────────────────
async def create_prescription_session(
    user_id: str,
    rx_item_seqs: list,
    expected_count: int,
    filename: str,
    processing_time_sec: float,
    total_items: int,
    ocr_raw_results: list,
    final_items: list,
    is_template: bool = False,
    session_type: str = "PRESCRIPTION",  # PRESCRIPTION or DRUG_BAG
    drugbag_id: Optional[str] = None,
):
    doc = {
        "user_id": user_id,
        "created_at": datetime.now(),
        "updated_at": datetime.now(),
        "status": "PROCESSING",
        "filename": filename,
        "processing_time_sec": processing_time_sec,
        "total_items": total_items,
        "expected_count": expected_count,
        "received_count": 0,
        "completed_count": 0,
        "rx_item_seqs": rx_item_seqs,
        "ocr_raw_results": ocr_raw_results,
        "final_items": final_items,
        "is_template": is_template,
        "session_type": session_type,  # PRESCRIPTION or DRUG_BAG
    }
    
    # DRUG_BAG 타입일 때 drugbag_id 추가
    if session_type == "DRUG_BAG" and drugbag_id:
        doc["drugbag_id"] = drugbag_id

    result = await prescriptions_sessions_collection.insert_one(doc)
    return await prescriptions_sessions_collection.find_one({"_id": result.inserted_id})


# ──────────────────────────────────────────────
# 세션 조회/보조
# ──────────────────────────────────────────────
def _get_session_query(prescription_id: str) -> Dict[str, Any]:
    """
    prescription_id를 받아서 _id 또는 drugbag_id 둘 다로 검색 가능한 쿼리 생성
    처방전은 _id로, 약봉투는 _id 또는 drugbag_id 둘 다로 검색 가능
    """
    try:
        oid = ObjectId(prescription_id)
        return {"_id": oid}
    except Exception:
        return {"drugbag_id": prescription_id}


async def get_prescription_session(prescription_id: str) -> Optional[Dict[str, Any]]:
    """세션 단건 조회 (_id 또는 drugbag_id 둘 다로 검색 가능)"""
    try:
        session = await prescriptions_sessions_collection.find_one({"_id": ObjectId(prescription_id)})
        if session:
            return session
    except Exception:
        pass
    
    return await prescriptions_sessions_collection.find_one({"drugbag_id": prescription_id})

async def get_rx_set(prescription_id: str) -> set[str]:
    """rx_item_seqs 조회 (_id 또는 drugbag_id 둘 다로 검색 가능)"""
    s = await get_prescription_session(prescription_id)
    raw = s.get("rx_item_seqs", []) if s else []
    rx = []
    for x in raw:
        if isinstance(x, (list, tuple)):
            if x:
                rx.append(str(x[0]))
        elif x is not None:
            rx.append(str(x))
    return set(rx)

async def touch_expected_count(prescription_id: str, expected_count: int) -> None:
    """expected_count 설정 (_id 또는 drugbag_id 둘 다로 검색 가능)"""
    base_query = _get_session_query(prescription_id)
    query = {
        **base_query,
        "$or": [
            {"expected_count": None},
            {"expected_count": {"$exists": False}},
        ],
    }
    
    await prescriptions_sessions_collection.update_one(
        query,
        {
            "$set": {
                "expected_count": int(expected_count),
                "updated_at": datetime.now(),
            }
        }
    )


# ──────────────────────────────────────────────
# 세션 진행 카운터
# ──────────────────────────────────────────────
async def increment_received_count(prescription_id: str) -> None:
    query = _get_session_query(prescription_id)
    await prescriptions_sessions_collection.update_one(
        query,
        {"$inc": {"received_count": 1}, "$set": {"updated_at": datetime.now()}}
    )

async def increment_completed_count(prescription_id: str) -> None:

    query = _get_session_query(prescription_id)
    
    new_doc = await prescriptions_sessions_collection.find_one_and_update(
        query,
        {"$inc": {"completed_count": 1}, "$set": {"updated_at": datetime.now()}},
        return_document=True,
    )
    if not new_doc:
        return

    exp = new_doc.get("expected_count")
    comp = new_doc.get("completed_count", 0)
    status = "DONE" if (isinstance(exp, int) and exp > 0 and comp >= exp) else "PROCESSING"
    
    await prescriptions_sessions_collection.update_one(
        query,
        {"$set": {"status": status, "updated_at": datetime.now()}}
    )


# ──────────────────────────────────────────────
# pill_images: 업로드/상태/결과 저장
# ──────────────────────────────────────────────
async def upsert_pill_image_queued(
    prescription_id: str,
    order_index: int,
    image_path: str,
) -> None:
    now = datetime.now()
    doc = {
        "prescription_id": prescription_id,
        "order_index": order_index,
        "image_path": image_path,
        "inference": {},
        "status": "QUEUED",  # QUEUED | RUNNING | DONE | ERROR
        "created_at": now,
        "updated_at": now,
    }
    await pill_images_collection.update_one(
        {"prescription_id": prescription_id, "order_index": order_index},
        {"$set": doc},
        upsert=True
    )

async def mark_pill_running(prescription_id: str, order_index: int) -> None:
    await pill_images_collection.update_one(
        {"prescription_id": prescription_id, "order_index": order_index},
        {"$set": {"status": "RUNNING", "updated_at": datetime.now()}}
    )

async def save_pill_inference_done(
    prescription_id: str,
    order_index: int,
    inference: Dict[str, Any],
    image_path: Optional[str] = None,
    status: str = "DONE",
) -> None:
    payload = {
        "inference": inference,
        "status": status,
        "updated_at": datetime.now()
    }
    if image_path:
        payload["image_path"] = image_path

    await pill_images_collection.update_one(
        {"prescription_id": prescription_id, "order_index": order_index},
        {"$set": payload},
        upsert=True
    )

async def list_pill_images(prescription_id: str) -> List[Dict[str, Any]]:
    cursor = pill_images_collection.find({"prescription_id": prescription_id}).sort("order_index", 1)
    return await cursor.to_list(length=1000)
