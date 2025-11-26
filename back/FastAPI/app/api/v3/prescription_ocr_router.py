# app/api/v3/prescription_ocr_router.py
from __future__ import annotations

import json
import os
import re
import time
import math
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path
from typing import Optional, List, Dict, Any, Set, Tuple

from bson import ObjectId
from datetime import datetime

from fastapi import (
    APIRouter,
    UploadFile,
    File,
    HTTPException,
    Request,
    Depends,
    Form,
    Query,
)

from app.inference.prescription_ocr import extract_drug_info
from app.services.permit_service import (
    get_item_seq_by_edi_code,
    search_permit_by_keywords,
)
from app.core.dependencies import get_current_user
from app.db.crud.user_auth import upsert_anonymous_user
from app.core.errors import ModelInferenceError, ExternalApiError
from app.db.crud.prescription_model_log import (
    create_prescription_session,
    get_prescription_session,
    list_pill_images,
)
from app.db.mongodb import prescriptions_sessions_collection

router = APIRouter()

BASE_DIR = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = BASE_DIR / "inference" / "ocr-uploaded"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

RESOURCES_DIR = BASE_DIR / "inference" / "resources"
with open(RESOURCES_DIR / "label_data.json", "r", encoding="utf-8") as f:
    LABEL_JSON = json.load(f)
with open(RESOURCES_DIR / "color_map2.json", "r", encoding="utf-8") as f:
    COLOR_JSON = json.load(f)
with open(RESOURCES_DIR / "3type_label.json", "r", encoding="utf-8") as f:
    TYPE_JSON = json.load(f)

def _normalize_text_for_sim(s: Any) -> str:
    """OCR/약명 비교용 텍스트 정규화"""
    if s is None:
        return ""
    if isinstance(s, (list, tuple)):
        s = " ".join(map(str, s))
    s = str(s)
    s = s.lower().strip()
    s = unicodedata.normalize("NFKC", s)
    s = re.sub(r"\s+", "", s)
    s = re.sub(r"[^0-9a-z가-힣]", "", s)
    return s


def text_similarity(a: Any, b: Any) -> float:
    """간단한 문자열 유사도 (SequenceMatcher)"""
    sa = _normalize_text_for_sim(a)
    sb = _normalize_text_for_sim(b)
    if not sa or not sb:
        return 0.0
    return SequenceMatcher(None, sa, sb).ratio()


def _as_str_item_seq(x: Any) -> Optional[str]:
    """item_seq를 문자열로 정규화 (tuple/list 방어 포함)."""
    if x is None:
        return None
    if isinstance(x, (list, tuple)):
        if not x:
            return None
        return str(x[0]).strip()
    s = str(x).strip()
    return s or None


def cosine_similarity(v1: Optional[List[float]], v2: Optional[List[float]]) -> float:
    """색상 벡터 등 간단 코사인 유사도 (None/길이 불일치 방어)."""
    if not v1 or not v2:
        return 0.0
    if len(v1) != len(v2):
        return 0.0

    dot = 0.0
    n1 = 0.0
    n2 = 0.0
    for a, b in zip(v1, v2):
        dot += a * b
        n1 += a * a
        n2 += b * b
    if n1 == 0 or n2 == 0:
        return 0.0
    return dot / (math.sqrt(n1) * math.sqrt(n2))


def _as_float_vector(vec: Any) -> Optional[List[float]]:
    if vec is None:
        return None
    if not isinstance(vec, (list, tuple)):
        return None
    floats: List[float] = []
    for v in vec:
        if isinstance(v, (int, float)):
            floats.append(float(v))
        else:
            return None
    return floats if floats else None


def _color_similarity_flexible(
    img_vec: Optional[List[float]], drug_vec: Any
) -> float:
    img = _as_float_vector(img_vec)
    if not img:
        return 0.0

    candidates: List[List[float]] = []

    if isinstance(drug_vec, (list, tuple)):
        if drug_vec and isinstance(drug_vec[0], (list, tuple)):
            for sub in drug_vec:
                normalized = _as_float_vector(sub)
                if normalized:
                    candidates.append(normalized)
        else:
            normalized = _as_float_vector(drug_vec)
            if normalized:
                candidates.append(normalized)

    if not candidates:
        return 0.0

    best = 0.0
    for cand in candidates:
        best = max(best, cosine_similarity(img, cand))
    return best


def _normalize_type_value(v: Any) -> Optional[str]:
    if v is None:
        return None
    s = str(v).strip().lower()
    return s or None


def compute_leftover_score(
    ocr_text: str,
    img_color_vec: Optional[List[float]],
    img_type: Optional[str],
    drug_label: str,
    drug_color_vec: Optional[List[float]],
    drug_type: Optional[str],
) -> Tuple[float, Dict[str, float]]:
    txt_sim = text_similarity(ocr_text or "", drug_label or "")
    col_sim = _color_similarity_flexible(img_color_vec, drug_color_vec)

    img_type_norm = _normalize_type_value(img_type)
    drug_type_norm = _normalize_type_value(drug_type)
    type_score = (
        1.0
        if img_type_norm
        and drug_type_norm
        and img_type_norm == drug_type_norm
        else 0.0
    )

    final_score = 0.5 * txt_sim + 0.3 * col_sim + 0.2 * type_score
    return final_score, {
        "ocr": txt_sim,
        "color": col_sim,
        "type": type_score,
    }

NON_PILL_FORMS = ["크림", "겔", "연고", "시럽", "액", "현탁액", "스프레이", "용액"]


def is_pill_form(name: str) -> bool:
    """정제/캡슐 형태만 남기기 위한 필터."""
    if not isinstance(name, str):
        return True
    for bad in NON_PILL_FORMS:
        if bad in name:
            return False
    return True


# ──────────────────────────────────────────────
# 1) 처방전 OCR
# ──────────────────────────────────────────────
@router.post("/prescription-ocr-auto")
async def prescription_ocr_auto(
    request: Request,
    file: UploadFile = File(...),
    expected_count: Optional[int] = Form(None),
    user_id: str = Depends(get_current_user),
):
    """
    [기능]
    처방전 이미지를 업로드하면 OCR로 약 목록을 추출하고,
    처방전 세션(prescription_id)을 생성해 반환합니다.

    [요청 파라미터]
    - file (필수, form-data, 파일):
      처방전 이미지 파일(JPG, PNG 등)

    - expected_count (선택, form-data, int):
      사용자가 "이 처방전에서 실제로 구분할 알약 개수"를 알고 있는 경우 설정
      (예: 크림 1개 + 알약 3개 처방인데, 알약 3개만 이미지로 찍을 예정이라면 3)

    [응답 데이터]
    - prescription_id (str):
      이후 /image-search, /prescriptions/{prescription_id}/results 호출 시 사용하는 세션 ID

    - processing_time_sec (float):
      OCR 처리에 걸린 시간(초)

    - total_items (int):
      OCR로 인식된 전체 처방 약 개수 (크림/연고 포함)

    - rx_item_seqs (list[str]):
      인식된 약들의 ITEM_SEQ 목록 (DB 매핑에 성공한 경우)

    - results (list[object]):
      각 약에 대한 기본 정보
        · itemSeq: 품목기준코드
        · itemName: 약 이름
        · ediCode: 보험코드
        · dose: 용량 (예: 250mg)
        · onceDose: 1회 투약량
        · dayDose: 1일 투여 횟수
        · totalDose: 총 투약 일수

    - expected_count (int | null):
      세션에 기록된 expected_count (미전달 시 null)
    """
    start_time = time.time()
    await upsert_anonymous_user(user_id, request)

    try:
        image_bytes = await file.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="빈 파일입니다.")

        # 파일 저장
        orig_ext = os.path.splitext(file.filename or "")[1] or ".jpg"
        ts = time.strftime("%Y%m%d_%H%M%S")
        safe_name = f"{ts}_{(file.filename or 'upload').replace(os.sep, '_')}"
        save_path = (UPLOAD_DIR / safe_name).with_suffix(orig_ext)

        with open(save_path, "wb") as f:
            f.write(image_bytes)

        # OCR 처리
        try:
            ocr_raw = extract_drug_info(str(save_path))
        except Exception as e:
            raise ExternalApiError(
                f"처방전 분석 중 오류: {str(e)}",
                code="OCR_PROCESSING_ERROR",
                context={"error_type": type(e).__name__},
            )

        if not ocr_raw:
            raise ExternalApiError(
                "OCR 결과 없음",
                code="OCR_EMPTY_RESULT",
                context={},
            )

        # OCR 결과를 통합 구조로 변환
        ocr_entries: List[Dict[str, Any]] = []

        for row in ocr_raw:
            if not isinstance(row, (list, tuple)):
                continue

            edi   = row[0] if len(row) > 0 else ""
            name  = row[1] if len(row) > 1 else ""
            dose  = row[2] if len(row) > 2 else ""
            once  = row[3] if len(row) > 3 else ""
            day   = row[4] if len(row) > 4 else ""
            total = row[5] if len(row) > 5 else ""

            if isinstance(name, str):
                name = re.sub(r"/\s*\d+.*$", "", name).strip()

            ocr_entries.append(
                {
                    "drug_name": name,
                    "edi_code": edi,
                    "dose": dose,
                    "once_dose": once,
                    "day_dose": day,
                    "total_dose": total,
                    "timing": None,  # 확장 예정
                }
            )

        # item_seq 매핑
        final_items = []
        rx_item_seqs: List[str] = []

        for ent in ocr_entries:
            drug_name = ent["drug_name"]
            edi_code = ent["edi_code"]

            item_seq = None

            # 1차: 보험코드 기반
            if edi_code:
                try:
                    item_seq = await get_item_seq_by_edi_code(edi_code)
                except Exception:
                    item_seq = None

            # 2차: 약명 검색
            if not item_seq and drug_name:
                try:
                    search_result = await search_permit_by_keywords(request, drug_name, user_id)
                    cands = search_result.get("items", [])
                except Exception:
                    cands = []
                if cands:
                    item_seq = cands[0].get("itemSeq")

            item_seq = _as_str_item_seq(item_seq)
            if item_seq:
                rx_item_seqs.append(item_seq)

            final_items.append(
                {
                    "itemSeq": item_seq,
                    "itemName": drug_name,
                    "ediCode": edi_code,
                    "dose": ent["dose"],
                    "onceDose": ent["once_dose"],
                    "dayDose": ent["day_dose"],
                    "totalDose": ent["total_dose"],
                    "timing": ent["timing"],
                }
            )

        # 세션 생성
        ocr_drug_count = len(final_items)

        session = await create_prescription_session(
            user_id=user_id,
            rx_item_seqs=rx_item_seqs,
            expected_count=None,
            filename=file.filename or "upload.jpg",
            processing_time_sec=round(time.time() - start_time, 3),
            total_items=ocr_drug_count,
            ocr_raw_results=ocr_entries,
            final_items=final_items,
            session_type="PRESCRIPTION",
        )

        prescription_id = str(session["_id"])
        elapsed = round(time.time() - start_time, 3)

        return {
            "message": "OCR 및 item_seq 매핑 완료",
            "prescription_id": prescription_id,
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


# ──────────────────────────────────────────────
# 2) 처방전 기록함 관련 라우터
# ──────────────────────────────────────────────

@router.post("/prescriptions/{prescription_id}/save-template")
async def save_template(
    prescription_id: str,
    user_id: str = Depends(get_current_user),
):
    """
    세션을 '기록함 템플릿'으로 저장.
    - 처방전 또는 약봉투 세션 모두 지원
    - 프론트에서 처음 OCR 후, 자동/수동으로 호출
    """
    session = await prescriptions_sessions_collection.find_one(
        {"_id": ObjectId(prescription_id)}
    )

    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")

    if session.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="권한이 없습니다.")

    session_type = session.get("session_type") or "PRESCRIPTION"
    
    await prescriptions_sessions_collection.update_one(
        {"_id": ObjectId(prescription_id)},
        {
            "$set": {
                "is_template": True,
                "updated_at": datetime.utcnow(),
            }
        },
    )

    response = {
        "message": "기록함에 템플릿으로 저장했습니다.",
        "prescription_id": prescription_id,
    }
    
    if session_type == "DRUG_BAG":
        response["drugbag_id"] = prescription_id

    return response


@router.post("/prescriptions/{template_id}/start-session")
async def start_new_session_from_template(
    template_id: str,
    request: Request,
    expected_count: Optional[int] = None,
    user_id: str = Depends(get_current_user),
):
    """
    [기능]
    기록함에 저장된 템플릿(template_id)을 기반으로
    새로운 세션을 생성. (처방전 또는 약봉투 모두 지원)

    [요청]
    - template_id: 기록함에서 선택한 세션 ID
    - expected_count: 새 세션에서 인식하려는 알약 개수(미지정 시 자동 계산)

    [응답]
    - new_prescription_id: 새로 생성된 세션 ID
    - new_drugbag_id: DRUG_BAG 타입일 때 (new_prescription_id와 동일)
    - expected_count: 세션에 설정된 알약 개수
    - drug_list: 새 세션에 포함된 약 목록
    """
    original = await get_prescription_session(template_id)
    if not original:
        raise HTTPException(status_code=404, detail="기록된 템플릿을 찾을 수 없습니다.")

    session_type = original.get("session_type") or "PRESCRIPTION"  # 기본값
    ocr_raw = original.get("ocr_raw_results") or []
    final_items = original.get("final_items") or []
    rx_item_seqs = original.get("rx_item_seqs", [])

    # 비알약 제형 제거
    filtered_items = []
    filtered_rx_items: List[str] = []
    
    for item in final_items:
        name = item.get("itemName", "")
        if is_pill_form(name):
            filtered_items.append(item)
            if item.get("itemSeq"):
                filtered_rx_items.append(str(item["itemSeq"]))
    
    if expected_count is None:
        expected_count = len(filtered_items)
    
    items_to_use = filtered_items
    rx_items_to_use = filtered_rx_items

    filename_prefix = "drugbag_template_copy" if session_type == "DRUG_BAG" else "template_copy"
    new_session = await create_prescription_session(
        user_id=user_id,
        rx_item_seqs=rx_items_to_use,
        expected_count=expected_count,
        filename=f"{filename_prefix}_{template_id}.jpg",
        processing_time_sec=0.0,
        total_items=len(items_to_use),
        ocr_raw_results=ocr_raw,
        final_items=items_to_use,
        session_type=session_type,
    )

    new_id = str(new_session["_id"])
    
    # DRUG_BAG 타입이면 drugbag_id 필드 업데이트
    if session_type == "DRUG_BAG":
        await prescriptions_sessions_collection.update_one(
            {"_id": ObjectId(new_id)},
            {"$set": {"drugbag_id": new_id}}
        )

    response = {
        "message": "new session created",
        "new_prescription_id": new_id,
        "expected_count": expected_count,
        "drug_list": items_to_use,
    }
    
    if session_type == "DRUG_BAG":
        response["new_drugbag_id"] = new_id

    return response


@router.get("/prescriptions/templates")
async def get_prescription_templates(
    user_id: str = Depends(get_current_user),
    session_type: Optional[str] = Query(None, description="PRESCRIPTION, DRUG_BAG, 또는 미지정 시 전체"),
):
    """
    [기능]
    사용자가 기록함에 저장해 둔 템플릿 목록 조회.
    - 처방전 또는 약봉투 모두 지원

    [요청 파라미터]
    - session_type (선택): "PRESCRIPTION" 또는 "DRUG_BAG" (미지정 시 전체)

    [응답]
    - count: 템플릿 개수
    - templates: [
        {
          "template_id": "...",
          "drugbag_id": "...",  # DRUG_BAG 타입일 때만
          "filename": "...",
          "created_at": "...",
          "pill_count": 3,  # PRESCRIPTION 타입
          "drug_count": 3,  # DRUG_BAG 타입
          "pill_items": [... 정/캡슐 약 목록 ...],  # PRESCRIPTION 타입
          "drug_items": [... 약 목록 ...],  # DRUG_BAG 타입
          "session_type": "PRESCRIPTION" or "DRUG_BAG"
        }, ...
      ]
    """
    query = {
        "user_id": user_id,
        "is_template": True,
    }
    
    # session_type 필터링
    if session_type:
        query["session_type"] = session_type
    else:
        # 전체 조회 시 기존 데이터 호환성 고려
        query["$or"] = [
            {"session_type": "PRESCRIPTION"},
            {"session_type": "DRUG_BAG"},
            {"session_type": {"$exists": False}},  # 기존 데이터
        ]

    cursor = prescriptions_sessions_collection.find(query).sort("created_at", -1)

    templates = []
    async for doc in cursor:
        template_id = str(doc["_id"])
        doc_session_type = doc.get("session_type") or "PRESCRIPTION"
        filename = doc.get("filename")
        created_at = doc.get("created_at")
        final_items = doc.get("final_items", []) or []

        template_data = {
            "template_id": template_id,
            "filename": filename,
            "created_at": created_at,
            "session_type": doc_session_type,
        }

        if doc_session_type == "DRUG_BAG":
            drugbag_id = doc.get("drugbag_id") or template_id
            template_data["drugbag_id"] = drugbag_id
            template_data["drug_count"] = len(final_items)
            template_data["drug_items"] = final_items
        else:  # PRESCRIPTION
            pill_items = [
                item for item in final_items
                if is_pill_form(item.get("itemName", ""))
            ]
            template_data["pill_count"] = len(pill_items)
            template_data["pill_items"] = pill_items

        templates.append(template_data)

    return {
        "count": len(templates),
        "templates": templates,
    }


# ──────────────────────────────────────────────
# 3) 세션 결과 조회 (image-search 후 결과)
# ──────────────────────────────────────────────
@router.get("/prescriptions/{prescription_id}/results")
async def get_prescription_results(prescription_id: str):
    """
    [기능]
    특정 세션에 대해 현재까지 업로드된 알약 이미지 인식 결과 조회.
    - 처방전 또는 약봉투 세션 모두 지원
    - prescription_id는 _id 또는 drugbag_id 필드로 검색 가능

    [요약 로직]
    - 세션(final_items) + pill_images(inference) 조합
    - 외용제(크림/겔/연고/용액 등)는 이미지 매핑 대상에서 제외
    - 모델+처방 교집합으로 확정된 약(strong)을 우선 사용
    - '처방전 기반 추정'으로만 매핑된 weak 결과가 strong과 겹치면 weak 제거
    - 남은 처방 알약(leftover)을, 인식 실패/추정용 이미지에
      점수 기반(텍스트+색상+type) 1:1 재배정
    """
    # prescription_id로 먼저 시도 (_id)
    session = await get_prescription_session(prescription_id)
    
    # _id로 찾지 못하면 drugbag_id 필드로 검색
    if not session:
        session = await prescriptions_sessions_collection.find_one(
            {"drugbag_id": prescription_id}
        )
    
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")

    # -------------------------------
    # 1) final_items 기반 매핑 준비
    # -------------------------------
    final_items = session.get("final_items", []) or []

    name_by_seq: Dict[str, Optional[str]] = {}
    timing_by_seq: Dict[str, Optional[str]] = {}
    once_by_seq: Dict[str, Optional[str]] = {}
    day_by_seq: Dict[str, Optional[str]] = {}
    total_by_seq: Dict[str, Optional[str]] = {}
    pilltype_by_seq: Dict[str, Optional[str]] = {}
    color_by_seq: Dict[str, Optional[List[float]]] = {}

    rx_all: Set[str] = set()
    rx_oral: Set[str] = set()

    for it in final_items:
        seq = it.get("itemSeq")
        if not seq:
            continue
        key = str(seq).strip()

        name = (it.get("itemName") or "").strip()
        name_by_seq[key] = name
        timing_by_seq[key] = it.get("timing")
        once_by_seq[key] = it.get("onceDose")
        day_by_seq[key] = it.get("dayDose")
        total_by_seq[key] = it.get("totalDose")

        pilltype_by_seq[key] = it.get("pillType")
        color_by_seq[key] = it.get("color_vector")

        rx_all.add(key)

        if any(form in name for form in NON_PILL_FORMS):
            # 외용제 → image-search 매핑 대상에서 제외
            continue
        rx_oral.add(key)

    # -------------------------------
    # 2) pill_images 로부터 1차 결과 생성
    # -------------------------------
    images = await list_pill_images(prescription_id)

    raw_results: List[Dict[str, Any]] = []
    image_metainfo: List[Dict[str, Any]] = []

    for doc in images:
        inf = doc.get("inference") or {}
        reranked = inf.get("reranked", []) or []
        selected = dict(inf.get("selected") or {})
        order_idx = doc.get("order_index", 0)

        pill_status = (
            doc.get("pill_status")
            or inf.get("status")
            or doc.get("status")
            or "DONE"
        )
        error_msg = inf.get("error") or doc.get("error_message")

        seq = selected.get("item_seq") or selected.get("itemSeq")
        if seq:
            key = str(seq).strip()

            if not selected.get("drug_name"):
                selected["drug_name"] = name_by_seq.get(key)
            if not selected.get("timing"):
                selected["timing"] = timing_by_seq.get(key)

            selected["onceDose"] = once_by_seq.get(key)
            selected["dayDose"] = day_by_seq.get(key)
            selected["totalDose"] = total_by_seq.get(key)

        raw_results.append(
            {
                "order_index": order_idx,
                "top_candidates": reranked,
                "selected": selected,
                "pill_status": pill_status,
                "error_message": error_msg,
            }
        )

        ocr_meta = inf.get("ocr_keywords")
        if isinstance(ocr_meta, (list, tuple)):
            ocr_txt = " ".join(map(str, ocr_meta))
        elif isinstance(ocr_meta, str):
            ocr_txt = ocr_meta
        else:
            ocr_txt = ""

        image_metainfo.append(
            {
                "order_index": order_idx,
                "ocr_text": ocr_txt,
                "image_type": inf.get("pill_type"),
                "image_color": inf.get("color_vector"),
            }
        )

    # -----------------------------------
    # 3) strong / weak / unassigned 분류
    # -----------------------------------
    strong_assigned: Set[str] = set()
    weak_indices: List[int] = []
    unassigned_indices: List[int] = []

    weak_index_set: Set[int] = set()

    for idx, res in enumerate(raw_results):
        sel = res["selected"] or {}
        seq = sel.get("item_seq") or sel.get("itemSeq")

        if not seq:
            unassigned_indices.append(idx)
            continue

        seq = str(seq).strip()
        reason = (sel.get("reason") or "").strip()
        top_candidates = res.get("top_candidates") or []

        # 외용제인 경우(크림/겔/연고 등)는 image-search 매핑에서 제외
        if seq in rx_all and seq not in rx_oral:
            sel["item_seq"] = None
            sel["itemSeq"] = None
            sel["drug_name"] = None
            sel["onceDose"] = None
            sel["dayDose"] = None
            sel["totalDose"] = None

            raw_results[idx]["selected"] = sel
            raw_results[idx]["error_message"] = (
                res.get("error_message")
                or "외용제(크림/겔/연고 등)는 이미지 매핑 대상에서 제외되었습니다."
            )
            unassigned_indices.append(idx)
            continue

        # 처방전 기반 추정 여부
        is_from_prescription_reason = "처방전 기반 추정" in reason

        all_from_prescription = (
            len(top_candidates) > 0
            and all(c.get("source") == "from_prescription" for c in top_candidates)
        )

        is_weak = is_from_prescription_reason or all_from_prescription

        if is_weak:
            weak_indices.append(idx)
            weak_index_set.add(idx)
            if idx not in unassigned_indices:
                unassigned_indices.append(idx)
        else:
            strong_assigned.add(seq)

    # -----------------------------------
    # 3-2) strong 결과와 겹치는 weak 제거
    # -----------------------------------
    for idx in weak_indices:
        sel = raw_results[idx]["selected"] or {}
        seq = sel.get("item_seq") or sel.get("itemSeq")
        if not seq:
            continue

        seq = str(seq).strip()
        if seq in strong_assigned:
            sel["item_seq"] = None
            sel["itemSeq"] = None
            sel["drug_name"] = None
            sel["onceDose"] = None
            sel["dayDose"] = None
            sel["totalDose"] = None

            prev_err = raw_results[idx].get("error_message")
            msg = "다른 알약에서 모델+처방 교집합으로 이미 확정된 약이어서, 처방전 기반 추정 결과를 제거했습니다."
            raw_results[idx]["error_message"] = (
                msg if not prev_err else f"{prev_err} / {msg}"
            )

            raw_results[idx]["selected"] = sel
            if idx not in unassigned_indices:
                unassigned_indices.append(idx)

    # -----------------------------------
    # 3-2-1) weak 내부 중복 제거 (동일 처방전 추정 결과는 1개만 유지)
    weak_seq_map: Dict[str, List[int]] = {}
    for idx in weak_indices:
        sel = raw_results[idx]["selected"] or {}
        seq = sel.get("item_seq") or sel.get("itemSeq")
        if not seq:
            continue
        seq = str(seq).strip()
        weak_seq_map.setdefault(seq, []).append(idx)

    for seq, idx_list in weak_seq_map.items():
        if len(idx_list) <= 1:
            continue
        for dup_idx in idx_list[1:]:
            sel = raw_results[dup_idx]["selected"] or {}
            sel["item_seq"] = None
            sel["itemSeq"] = None
            sel["drug_name"] = None
            sel["onceDose"] = None
            sel["dayDose"] = None
            sel["totalDose"] = None
            msg = (
                "동일 처방전 기반 추정 중복으로 제거되었습니다."
            )
            prev_err = raw_results[dup_idx].get("error_message")
            raw_results[dup_idx]["error_message"] = (
                msg if not prev_err else f"{prev_err} / {msg}"
            )
            raw_results[dup_idx]["selected"] = sel
            if dup_idx not in unassigned_indices:
                unassigned_indices.append(dup_idx)
            weak_index_set.add(dup_idx)

    # -----------------------------------
    # 3-3) leftover 약 계산
    # -----------------------------------
    used_item_seqs: Set[str] = set()
    for idx, res in enumerate(raw_results):
        sel = res["selected"] or {}
        seq = sel.get("item_seq") or sel.get("itemSeq")
        if seq:
            if idx in weak_index_set:
                continue  # weak 결과는 leftover 재배정 대상
            used_item_seqs.add(str(seq).strip())

    leftover_oral = [seq for seq in rx_oral if seq not in used_item_seqs]

    ordered_leftover: List[str] = []
    for it in final_items:
        key = str(it.get("itemSeq") or "").strip()
        if key in leftover_oral and key not in ordered_leftover:
            ordered_leftover.append(key)

    # -----------------------------------
    # 3-4) leftover 매칭 — 점수 기반 1:1 재배정
    # -----------------------------------
    print(
        "[rx-results]"
        f"[{prescription_id}] strong={len(strong_assigned)} "
        f"weak={len(weak_index_set)} "
        f"leftover={ordered_leftover}"
    )
    # 3-4-1) 이미지별 추론 메타(ocr/색상/type) 정리
    image_features_by_order: Dict[int, Dict[str, Any]] = {
        meta["order_index"]: meta for meta in image_metainfo
    }

    # 3-4-2) leftover 약 정보 준비 (seq별로 name/투약량 + 리소스 기반 메타 포함)
    leftover_drugs: List[Dict[str, Any]] = []
    for seq in ordered_leftover:
        seq_key = str(seq).strip()
        label_text = LABEL_JSON.get(seq_key) if LABEL_JSON else None
        color_vec = COLOR_JSON.get(seq_key) if COLOR_JSON else None
        pill_type = TYPE_JSON.get(seq_key) if TYPE_JSON else None
        leftover_drugs.append(
            {
                "item_seq": seq_key,
                "drug_name": name_by_seq.get(seq_key) or "",
                "ocr_label": label_text or name_by_seq.get(seq_key) or "",
                "timing": timing_by_seq.get(seq_key),
                "onceDose": once_by_seq.get(seq_key),
                "dayDose": day_by_seq.get(seq_key),
                "totalDose": total_by_seq.get(seq_key),
                "color_vector": color_vec,
                "pill_type": pill_type or pilltype_by_seq.get(seq_key),
            }
        )

    seen_un: List[int] = []
    for idx in unassigned_indices:
        if idx not in seen_un:
            seen_un.append(idx)

    # 3-4-3) 모든 비할당 인덱스 × leftover 약 조합 점수 계산
    candidate_scores: List[Dict[str, Any]] = []
    for idx in seen_un:
        order_idx = raw_results[idx]["order_index"]
        features = image_features_by_order.get(order_idx, {})
        ocr_text = features.get("ocr_text", "") if features else ""
        img_color_vec = features.get("image_color") if features else None
        img_type = features.get("image_type") if features else None

        for drug in leftover_drugs:
            score, breakdown = compute_leftover_score(
                ocr_text,
                img_color_vec,
                img_type,
                drug.get("ocr_label") or drug.get("drug_name"),
                drug.get("color_vector"),
                drug.get("pill_type"),
            )
            candidate_scores.append(
                {
                    "score": score,
                    "idx": idx,
                    "seq": drug["item_seq"],
                    "drug": drug,
                    "breakdown": breakdown,
                }
            )

    candidate_scores.sort(key=lambda x: x["score"], reverse=True)

    assigned_orders: Set[int] = set()
    assigned_seqs: Set[str] = set()

    for cand in candidate_scores:
        idx = cand["idx"]
        seq = cand["seq"]
        if idx in assigned_orders or seq in assigned_seqs:
            continue
        sel = raw_results[idx]["selected"] or {}
        drug = cand["drug"]
        breakdown = cand["breakdown"]

        sel["item_seq"] = seq
        sel.pop("itemSeq", None)
        sel["drug_name"] = drug["drug_name"]
        sel["timing"] = drug["timing"]
        sel["onceDose"] = drug["onceDose"]
        sel["dayDose"] = drug["dayDose"]
        sel["totalDose"] = drug["totalDose"]

        base_reason = sel.get("reason")
        extra_reason = (
            "보정 매칭"
            f"(score={cand['score']:.3f}, "
            f"ocr={breakdown['ocr']:.3f}, "
            f"color={breakdown['color']:.3f}, "
            f"type={breakdown['type']:.1f})"
        )
        sel["reason"] = extra_reason if not base_reason else f"{base_reason} / {extra_reason}"

        raw_results[idx]["selected"] = sel
        assigned_orders.add(idx)
        assigned_seqs.add(seq)

    # 3-4-4) 여전히 남은 이미지/약에 대해 순차 보정 (score 동률/없음 대비)
    remaining_drugs = [
        d for d in leftover_drugs if d["item_seq"] not in assigned_seqs
    ]
    remaining_indices = [idx for idx in seen_un if idx not in assigned_orders]

    for idx in remaining_indices:
        if not remaining_drugs:
            break
        drug = remaining_drugs.pop(0)
        sel = raw_results[idx]["selected"] or {}
        sel["item_seq"] = drug["item_seq"]
        sel.pop("itemSeq", None)
        sel["drug_name"] = drug["drug_name"]
        sel["timing"] = drug["timing"]
        sel["onceDose"] = drug["onceDose"]
        sel["dayDose"] = drug["dayDose"]
        sel["totalDose"] = drug["totalDose"]
        base_reason = sel.get("reason")
        fallback_reason = "처방전 기반 단독 매핑(남은 약 자동 할당)"
        sel["reason"] = fallback_reason if not base_reason else f"{base_reason} / {fallback_reason}"
        raw_results[idx]["selected"] = sel

    # -----------------------------------
    # 4) guide 텍스트 / TTS용 문장 생성
    # -----------------------------------
    session_type = session.get("session_type") or "PRESCRIPTION"
    is_drug_bag = session_type == "DRUG_BAG"
    
    sequence_text: List[str] = []
    for res in raw_results:
        sel = res["selected"] or {}
        idx = res["order_index"]

        dn = sel.get("drug_name") or "미확인"
        seq = sel.get("item_seq") or sel.get("itemSeq")
        err = res.get("error_message")

        if err and not seq:
            seq_txt = f"{idx + 1}번째 알약: 인식 실패 (에러: {err})"
        else:
            if is_drug_bag:
                # 약봉투는 약이름만 표시
                seq_txt = f"{idx + 1}번째 약은 {dn}입니다"
            else:
                # 처방전은 투약량 정보 포함
                od = sel.get("onceDose") or "-"
                dd = sel.get("dayDose") or "-"
                td = sel.get("totalDose") or "-"
                seq_txt = (
                    f"{idx + 1}번째 약은 {dn}, "
                    f"복용량은 하루에 {dd}번, 한번에 {od}개씩 총 {td}개 입니다"
                )

        sequence_text.append(seq_txt)

    tts_text = " ".join(sequence_text)

    expected = session.get("expected_count")
    completed = session.get("completed_count", 0)
    status = (
        "DONE"
        if (isinstance(expected, int) and expected > 0 and completed >= expected)
        else "PROCESSING"
    )

    cleaned_results: List[Dict[str, Any]] = []
    for res in raw_results:
        r = dict(res)
        r.pop("top_candidates", None)
        cleaned_results.append(r)

    return {
        "prescription_id": prescription_id,
        "expected_count": expected,
        "received_count": session.get("received_count", 0),
        "completed_count": completed,
        "results": cleaned_results,
        "guide": {
            "sequence_text": sequence_text,
            "tts_text": tts_text,
        },
        "status": status,
    }
