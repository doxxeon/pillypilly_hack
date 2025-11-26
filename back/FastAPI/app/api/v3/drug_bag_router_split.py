# app/api/v3/drug_bag_router_split.py

from fastapi import APIRouter, UploadFile, File, HTTPException, Request, Form, Depends
from typing import Optional, List, Dict, Any
from bson import ObjectId
from datetime import datetime
from app.inference.drug_bag_split_ocr import extract_drugbag_split
from app.services.permit_service import search_permit_by_keywords, get_item_seq_by_edi_code
from app.db.crud.prescription_model_log import (
    create_prescription_session,
    get_prescription_session,
)
from app.db.crud.user_auth import upsert_anonymous_user
from app.db.mongodb import prescriptions_sessions_collection
from app.core.dependencies import get_current_user
from app.core.errors import ExternalApiError, ModelInferenceError
import time
import os

router = APIRouter()


@router.post("/drugbag-ocr-auto")
async def drugbag_split_ocr(
    request: Request,
    file: UploadFile = File(...),
    expected_count: Optional[int] = Form(None),
    user_id: str = Depends(get_current_user),
):
    """
    [기능]
    약봉투 이미지를 업로드하면 OCR로 약 목록을 추출하고,
    약봉투 세션(drugbag_id)을 생성해 반환합니다.

    [요청 파라미터]
    - file (필수, form-data, 파일):
      약봉투 이미지 파일(JPG, PNG 등)

    - expected_count (선택, form-data, int):
      사용자가 "이 약봉투에서 실제로 구분할 알약 개수"를 알고 있는 경우 설정

    [응답 데이터]
    - prescription_id (str):
      이후 /image-search, /prescriptions/{prescription_id}/results 호출 시 사용하는 세션 ID
    - drugbag_id (str):
      약봉투 세션 ID (prescription_id와 동일)

    - processing_time_sec (float):
      OCR 처리에 걸린 시간(초)

    - total_items (int):
      OCR로 인식된 전체 약 개수

    - rx_item_seqs (list[str]):
      인식된 약들의 ITEM_SEQ 목록 (DB 매핑에 성공한 경우)

    - results (list[object]):
      각 약에 대한 기본 정보
        · itemSeq: 품목기준코드
        · itemName: 약 이름
        · ediCode: 보험코드 (약봉투에는 없을 수 있음)
        · dose: 용량 (약봉투에는 없을 수 있음)
        · onceDose: 1회 투약량
        · dayDose: 1일 투여 횟수
        · totalDose: 총 투약 일수
        · totalCount: 총 개수 (약봉투 전용)
        · timing: 투약 시기 (약봉투에는 없을 수 있음)

    - expected_count (int | null):
      세션에 기록된 expected_count (미전달 시 null)
    """
    start_time = time.time()
    await upsert_anonymous_user(user_id, request)

    try:
        image_bytes = await file.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="빈 파일입니다.")

        save_dir = r"D:\pilly-pilly_h\FastAPI\app\inference\drugbag_pro2"
        os.makedirs(save_dir, exist_ok=True)

        ext = os.path.splitext(file.filename or "")[1] or ".jpg"
        save_path = os.path.join(save_dir, f"{int(time.time())}{ext}")

        with open(save_path, "wb") as f:
            f.write(image_bytes)

        try:
            parsed = extract_drugbag_split(save_path)
        except Exception as e:
            raise ExternalApiError(
                f"약봉투 분석 중 오류: {str(e)}",
                code="OCR_PROCESSING_ERROR",
                context={"error_type": type(e).__name__},
            )

        rows = parsed["rows"]

        if not rows:
            raise ExternalApiError(
                "약봉투에서 약품 정보를 추출하지 못했습니다.",
                code="OCR_EMPTY_RESULT",
                context={},
            )

        final_items = []
        rx_item_seqs: List[str] = []

        for row in rows:
            drug_name = row.get("drugName", "")
            once_dose = row.get("onceDose")
            day_dose = row.get("dayDose")
            total_dose = row.get("days")
            total_count = row.get("totalCount")

            item_seq = None
            matched_item_name = drug_name

            if drug_name:
                try:
                    search_result = await search_permit_by_keywords(
                        request, drug_name, user_id
                    )
                    items = search_result.get("items", [])
                    if items:
                        item_seq = items[0].get("itemSeq")
                        matched_item_name = items[0].get("itemName", drug_name)
                except Exception:
                    pass

            if item_seq is None:
                item_seq = None
            elif isinstance(item_seq, (list, tuple)):
                if not item_seq:
                    item_seq = None
                else:
                    item_seq = str(item_seq[0]).strip() or None
            else:
                item_seq = str(item_seq).strip() or None
            
            if item_seq:
                rx_item_seqs.append(item_seq)

            final_items.append(
                {
                    "itemSeq": item_seq,
                    "itemName": matched_item_name,
                    "ediCode": None,
                    "dose": None,
                    "onceDose": once_dose,
                    "dayDose": day_dose,
                    "totalDose": total_dose,
                    "totalCount": total_count,
                    "timing": None,
                }
            )

        ocr_drug_count = len(final_items)

        session = await create_prescription_session(
            user_id=user_id,
            rx_item_seqs=rx_item_seqs,
            expected_count=None,
            filename=file.filename or "drugbag_upload.jpg",
            processing_time_sec=round(time.time() - start_time, 3),
            total_items=ocr_drug_count,
            ocr_raw_results=rows,
            final_items=final_items,
            session_type="DRUG_BAG",
        )

        drugbag_id = str(session["_id"])
        
        await prescriptions_sessions_collection.update_one(
            {"_id": ObjectId(drugbag_id)},
            {"$set": {"drugbag_id": drugbag_id}}
        )

        elapsed = round(time.time() - start_time, 3)

        return {
            "message": "OCR 및 item_seq 매핑 완료",
            "prescription_id": drugbag_id,
            "drugbag_id": drugbag_id,
            "processing_time_sec": elapsed,
            "total_items": ocr_drug_count,
            "rx_item_seqs": rx_item_seqs,
            "results": final_items,
            "expected_count": ocr_drug_count,
        }

    except (ModelInferenceError, ExternalApiError, HTTPException):
        raise
    except Exception as e:
        raise ExternalApiError(
            f"예상치 못한 오류: {str(e)}",
            code="OCR_PROCESSING_ERROR",
            context={"error_type": type(e).__name__},
        )
