# app/services/dur_service.py
from __future__ import annotations
import os
from typing import Dict, Any, List, Optional, Tuple
from datetime import datetime, timedelta
from app.core.errors import ExternalApiError
from app.db.mongodb import (
    dur_comb_collection,
    dur_preg_collection,
    dur_age_collection,
    dur_term_collection,
    dur_elderly_collection,
    dur_dosage_collection,
)

# ──────────────────────────────────────────────
# 캐시 설정
# ──────────────────────────────────────────────
USE_CACHE = os.getenv("DUR_USE_CACHE", "true").lower() == "true"
CACHE_TTL_MIN = int(os.getenv("DUR_CACHE_TTL_MIN", "60"))
_CACHE: Dict[str, Tuple[datetime, List[Dict[str, Any]]]] = {}

# ──────────────────────────────────────────────
# 캐시 관리 함수
# ──────────────────────────────────────────────
def _cache_get(key: str) -> Optional[List[Dict[str, Any]]]:
    if not USE_CACHE:
        return None
    now = datetime.now()
    if key in _CACHE:
        ts, val = _CACHE[key]
        if now - ts < timedelta(minutes=CACHE_TTL_MIN):
            return val
        _CACHE.pop(key, None)
    return None


def _cache_put(key: str, items: List[Dict[str, Any]]) -> None:
    """캐시에 결과 저장"""
    if USE_CACHE:
        _CACHE[key] = (datetime.utcnow(), items)


# ───────── DUR 공통 fetch 함수 ─────────
async def _fetch(coll, item_seq: str) -> List[Dict[str, Any]]:
    """
    DUR 데이터 조회용 공통 fetch 함수
    - DB 핸들(coll)을 직접 받아 사용
    - itemSeq / ITEM_SEQ 둘 다 조회 지원
    - 캐시 적용 유지
    """
    cache_key = f"{coll.name}:{item_seq}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached

    try:
        cursor = coll.find({"itemSeq": item_seq})
        docs: List[Dict[str, Any]] = []
        async for d in cursor:
            d.pop("_id", None)
            d = {(k.strip() if isinstance(k, str) else k): v for k, v in d.items()}
            docs.append(d)

        _cache_put(cache_key, docs)
        return docs

    except Exception as e:
        raise ExternalApiError(
            "DUR DB failure",
            status_code=502,
            context={"collection": coll.name, "msg": str(e)},
        )


# ───────── 데이터 정제(공통 스키마) ─────────
def _normalize_common(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """일반 DUR 유형 (연령/임부/용량/투여기간/노인) 정제"""
    out: List[Dict[str, Any]] = []
    for it in items or []:
        out.append({
            "typeName":        it.get("typeName"),
            "itemName":        it.get("itemName"),
            "prohibitContent": it.get("prohibitContent"),
            "remark":          it.get("remark"),
        })
    return [o for o in out if any(v not in (None, "", []) for v in o.values())]


def _normalize_combination(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """병용금기 전용 정제 스키마"""
    out: List[Dict[str, Any]] = []
    for it in items or []:
        out.append({
            "typeName":           it.get("typeName"),
            "itemName":           it.get("itemName"),
            "mixtureItemName":    it.get("mixtureItemName"),
            "mixtureIngredient":  it.get("mixtureIngredient"),
            "prohibitContent":    it.get("prohibitContent"),
            "remark":             it.get("remark"),
        })
    return [o for o in out if any(v not in (None, "", []) for v in o.values())]


# ───────── DUR 유형별 조회 함수 ─────────
async def get_dur_elderly(item_seq: str):
    """고령자 DUR"""
    return _normalize_common(await _fetch(dur_elderly_collection, item_seq))


async def get_dur_age(item_seq: str):
    """연령 DUR"""
    return _normalize_common(await _fetch(dur_age_collection, item_seq))


async def get_dur_dosage(item_seq: str):
    """용량 DUR"""
    return _normalize_common(await _fetch(dur_dosage_collection, item_seq))


async def get_dur_pregnant(item_seq: str):
    """임부 DUR"""
    return _normalize_common(await _fetch(dur_preg_collection, item_seq))


async def get_dur_term(item_seq: str):
    """투여기간 DUR"""
    return _normalize_common(await _fetch(dur_term_collection, item_seq))


async def get_dur_combination(item_seq: str):
    """병용금기 DUR"""
    return _normalize_combination(await _fetch(dur_comb_collection, item_seq))


# ───────── 통합 조회 함수 ─────────
async def get_all_dur_info(item_seq: str) -> Dict[str, Any]:
    """
    모든 DUR 유형 통합 조회
    """
    try:
        elderly = await get_dur_elderly(item_seq)
        age = await get_dur_age(item_seq)
        dosage = await get_dur_dosage(item_seq)
        pregnant = await get_dur_pregnant(item_seq)
        term = await get_dur_term(item_seq)
        combination = await get_dur_combination(item_seq)

        return {
            "elderly": elderly,
            "age": age,
            "dosage": dosage,
            "pregnant": pregnant,
            "term": term,
            "combination": combination,
        }

    except Exception as e:
        raise ExternalApiError(
            "DUR aggregation failed",
            status_code=500,
            context={"item_seq": item_seq, "msg": str(e)},
        )