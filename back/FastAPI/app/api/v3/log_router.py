# app/api/v2/log_router.py
import asyncio
import anyio
import math
from fastapi import APIRouter, Request, HTTPException, Depends, Query, Body
from typing import List, Dict, Optional
import traceback

from app.services.permit_service import get_permit_combined, get_item_seq_by_standard_code, get_item_seq_by_edi_code
from app.services.e_drug_service import get_edrug_info
from app.services.dur_service import get_all_dur_info
from app.services.log_service import log_to_mongo
from app.core.dependencies import get_current_user
from app.db.crud.user_auth import upsert_anonymous_user
from app.utils.logger import logger_drugs

router = APIRouter()

# DUR 카테고리 키 매핑 (출력 구조 유지용)
DUR_KEYMAP = {
    "elderly": "고령자",
    "age": "특정연령대",
    "dosage": "용량주의",
    "pregnant": "임부금기",
    "term": "투여기간주의",
}

# 기본형 eDrug 결과 (타임아웃/데이터없음 시 대체)
EMPTY_EDRUG = {
    "itemName": None,
    "effect": [],
    "dosage": [],
    "warning": [],
    "precautions": [],
    "interactions": [],
    "sideEffects": [],
}


@router.post("/log", summary="여러 item_seq에 대한 통합조회")
async def get_combined_info(
    request: Request,
    item_seqs: Optional[List[str]] = Body(None, embed=False),
    user_id: str = Depends(get_current_user),
):
    start_time = anyio.current_time()
    await upsert_anonymous_user(user_id, request)

    if not item_seqs:
        raise HTTPException(status_code=400, detail="item_seqs가 필요합니다.")

    try:
        final_result: Dict[str, dict] = {}

        for item_seq in item_seqs:
            try:
                # ─────────────────────────────
                # 내부 비동기 작업 정의
                # ─────────────────────────────
                async def _permit():
                    with anyio.move_on_after(6.0) as scope:
                        data = await get_permit_combined(item_seq)
                    return {} if scope.cancel_called else (data or {})

                async def _edrug():
                    with anyio.move_on_after(5.0) as scope:
                        data = await get_edrug_info(item_seq)
                    return (EMPTY_EDRUG if scope.cancel_called else {**EMPTY_EDRUG, **(data or {})})

                async def _dur():
                    with anyio.move_on_after(6.0) as scope:
                        data = await get_all_dur_info(item_seq)
                    return {} if scope.cancel_called else (data or {})

                # 세 그룹 병렬 실행
                permit_result, dur_result, edrug_result = await asyncio.gather(
                    _permit(), _dur(), _edrug()
                )

                # 최종 결과 조합
                combined = {
                    "permit": permit_result,
                    "edrug": edrug_result,
                    "dur": dur_result,
                }
                final_result[item_seq] = combined

                # 로그 저장
                await log_to_mongo(
                    request, user_id, {"source": "multi", "item_seq": item_seq}, combined
                )

            except Exception as inner_e:
                logger_drugs.error(f"❌ item_seq={item_seq} 처리 중 오류: {inner_e}")
                logger_drugs.error(traceback.format_exc())

        elapsed = round(anyio.current_time() - start_time, 4)
        logger_drugs.info(
            f"[약 정보 통합조회] user_id={user_id} | count={len(item_seqs)} | elapsed={elapsed}s"
        )

        safe_result = clean_float_values(final_result)
        return {"message": "통합조회 완료", "results": safe_result}

    except Exception as e:
        logger_drugs.error(f"[FATAL] 통합조회 전체 실패: {e}")
        logger_drugs.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"❌ 서버 오류: {e}")


@router.post("/log/by-standard-code", summary="표준코드로 통합조회")
async def get_combined_info_by_standard_code(
    request: Request,
    standard_code: str = Body(..., embed=True),
    user_id: str = Depends(get_current_user),
):
    """
    표준코드로 QR/바코드 약품 정보 통합 조회
    - standard_code: 표준코드 (필수, 쉼표로 구분된 여러 코드 지원)
    """
    start_time = anyio.current_time()
    await upsert_anonymous_user(user_id, request)

    try:
        # 1. 표준코드로 item_seq 목록 추출
        item_seqs = await get_item_seq_by_standard_code(standard_code)
        
        if not item_seqs:
            return {
                "message": "해당 표준코드에 대한 약품 정보가 없습니다.",
                "search_code": {"standard_code": standard_code},
                "results": {}
            }

        # 2. 기존 log 엔드포인트와 동일한 로직으로 통합 조회
        final_result: Dict[str, dict] = {}

        for item_seq in item_seqs:
            try:
                # ─────────────────────────────
                # 내부 비동기 작업 정의
                # ─────────────────────────────
                async def _permit():
                    with anyio.move_on_after(6.0) as scope:
                        data = await get_permit_combined(item_seq)
                    return {} if scope.cancel_called else (data or {})

                async def _edrug():
                    with anyio.move_on_after(5.0) as scope:
                        data = await get_edrug_info(item_seq)
                    return (EMPTY_EDRUG if scope.cancel_called else {**EMPTY_EDRUG, **(data or {})})

                async def _dur():
                    with anyio.move_on_after(6.0) as scope:
                        data = await get_all_dur_info(item_seq)
                    return {} if scope.cancel_called else (data or {})

                # 세 그룹 병렬 실행
                permit_result, dur_result, edrug_result = await asyncio.gather(
                    _permit(), _dur(), _edrug()
                )

                # 최종 결과 조합
                combined = {
                    "permit": permit_result,
                    "edrug": edrug_result,
                    "dur": dur_result,
                }
                final_result[item_seq] = combined

                # 로그 저장
                await log_to_mongo(
                    request, user_id, {"source": "standard_code", "standard_code": standard_code, "item_seq": item_seq}, combined
                )

            except Exception as inner_e:
                logger_drugs.error(f"❌ item_seq={item_seq} 처리 중 오류: {inner_e}")
                logger_drugs.error(traceback.format_exc())

        elapsed = round(anyio.current_time() - start_time, 4)
        logger_drugs.info(
            f"[표준코드 기반 통합조회] user_id={user_id} | standard_code={standard_code} | count={len(item_seqs)} | elapsed={elapsed}s"
        )

        safe_result = clean_float_values(final_result)
        return {
            "message": "표준코드 기반 통합조회 완료",
            "search_code": {"standard_code": standard_code},
            "found_items": len(item_seqs),
            "results": safe_result
        }

    except Exception as e:
        logger_drugs.error(f"[FATAL] 표준코드 기반 통합조회 전체 실패: {e}")
        logger_drugs.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"❌ 서버 오류: {e}")

'''
@router.post("/log/by-edi-code", summary="보험코드로 통합조회")
async def get_combined_info_by_edi_code(
    request: Request,
    edi_code: str = Body(..., embed=True),
    user_id: str = Depends(get_current_user),
):
    """
    보험코드로 약품 정보 통합 조회
    - edi_code: 보험코드 (필수)
    """
    start_time = anyio.current_time()
    await upsert_anonymous_user(user_id, request)

    try:
        # 1. 보험코드로 item_seq 목록 추출
        item_seqs = await get_item_seq_by_edi_code(edi_code)
        
        if not item_seqs:
            return {
                "message": "해당 보험코드에 대한 약품 정보가 없습니다.",
                "search_code": {"edi_code": edi_code},
                "results": {}
            }

        # 2. 기존 log 엔드포인트와 동일한 로직으로 통합 조회
        final_result: Dict[str, dict] = {}

        for item_seq in item_seqs:
            try:
                # ─────────────────────────────
                # 내부 비동기 작업 정의
                # ─────────────────────────────
                async def _permit():
                    with anyio.move_on_after(6.0) as scope:
                        data = await get_permit_combined(item_seq)
                    return {} if scope.cancel_called else (data or {})

                async def _edrug():
                    with anyio.move_on_after(5.0) as scope:
                        data = await get_edrug_info(item_seq)
                    return (EMPTY_EDRUG if scope.cancel_called else {**EMPTY_EDRUG, **(data or {})})

                async def _dur():
                    with anyio.move_on_after(6.0) as scope:
                        data = await get_all_dur_info(item_seq)
                    return {} if scope.cancel_called else (data or {})

                # 세 그룹 병렬 실행
                permit_result, dur_result, edrug_result = await asyncio.gather(
                    _permit(), _dur(), _edrug()
                )

                # 최종 결과 조합
                combined = {
                    "permit": permit_result,
                    "edrug": edrug_result,
                    "dur": dur_result,
                }
                final_result[item_seq] = combined

                # 로그 저장
                await log_to_mongo(
                    request, user_id, {"source": "edi_code", "edi_code": edi_code, "item_seq": item_seq}, combined
                )

            except Exception as inner_e:
                logger_drugs.error(f"❌ item_seq={item_seq} 처리 중 오류: {inner_e}")
                logger_drugs.error(traceback.format_exc())

        elapsed = round(anyio.current_time() - start_time, 4)
        logger_drugs.info(
            f"[보험코드 기반 통합조회] user_id={user_id} | edi_code={edi_code} | count={len(item_seqs)} | elapsed={elapsed}s"
        )

        safe_result = clean_float_values(final_result)
        return {
            "message": "보험코드 기반 통합조회 완료",
            "search_code": {"edi_code": edi_code},
            "found_items": len(item_seqs),
            "results": safe_result
        }

    except Exception as e:
        logger_drugs.error(f"[FATAL] 보험코드 기반 통합조회 전체 실패: {e}")
        logger_drugs.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"❌ 서버 오류: {e}")
'''

def clean_float_values(obj):
    if isinstance(obj, dict):
        return {k: clean_float_values(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [clean_float_values(v) for v in obj]
    elif isinstance(obj, float):
        if math.isnan(obj) or math.isinf(obj):
            return None
        return obj
    return obj
