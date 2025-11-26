# app/services/e_drug_service.py
from __future__ import annotations

import os
from typing import Dict, Any, Optional, Tuple, List
from datetime import datetime, timedelta

from motor.motor_asyncio import AsyncIOMotorClient
from app.core.errors import ExternalApiError
from app.db.mongodb import edrug_collection

# ──────────────────────────────────────────────
# 캐시 설정
# ──────────────────────────────────────────────
USE_CACHE = os.getenv("EDRUG_USE_CACHE", "true").lower() == "true"
CACHE_TTL_MIN = int(os.getenv("EDRUG_CACHE_TTL_MIN", "60"))
_CACHE: Dict[str, Tuple[datetime, Dict[str, Any]]] = {}

# ──────────────────────────────────────────────
# 텍스트 처리 함수
# ──────────────────────────────────────────────
def split_text(text: Optional[str]) -> List[str]:
    if text is None:
        return []
    s = str(text).strip()
    if not s or s.lower() == "nan":
        return []
    
    return [line.strip() for line in s.split("\n") if line.strip()]

def _cache_get(item_seq: str) -> Optional[Dict[str, Any]]:
    if not USE_CACHE:
        return None
    now = datetime.utcnow()
    if item_seq in _CACHE:
        ts, val = _CACHE[item_seq]
        if now - ts < timedelta(minutes=CACHE_TTL_MIN):
            return val
        _CACHE.pop(item_seq, None)
    return None

def _cache_put(item_seq: str, data: Dict[str, Any]) -> None:
    if not USE_CACHE:
        return
    _CACHE[item_seq] = (datetime.utcnow(), data)

# ─────────────────────────────────────────────
# 메인 함수 (이름/시그니처/동작 유지)
# ─────────────────────────────────────────────
async def get_edrug_info(item_seq: str) -> Dict[str, Any]:
    # 캐시
    cached = _cache_get(item_seq)
    if cached is not None:
        return cached

    try:
        doc = await edrug_collection.find_one({"ITEM_SEQ": item_seq})

        if not doc:
            result: Dict[str, Any] = {
                "itemName": None,
                "effect": [], "dosage": [], "warning": [],
                "precautions": [], "interactions": [], "sideEffects": [],
            }
            _cache_put(item_seq, result)
            return result

        result = {
            "itemName": doc.get("ITEM_NAME"),
            "effect":       split_text(doc.get("EFCY_QES_ITM")),
            "dosage":       split_text(doc.get("USE_METHOD_QES_ITM")),
            "warning":      split_text(doc.get("ATPN_WARN_QES_ITM")),
            "precautions":  split_text(doc.get("ATPN_QES_ITM")),
            "interactions": split_text(doc.get("INTRC_QES_ITM")),
            "sideEffects":  split_text(doc.get("SE_QES_ITM")),
        }

        _cache_put(item_seq, result)
        return result

    except Exception as e:
        raise ExternalApiError("eDrug failure", status_code=502,
                               context={"endpoint": "e_drug_db", "msg": str(e)})
