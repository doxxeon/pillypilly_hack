# app/api/v3/prescription_ocr_router.py
import os
import io
import time
from pathlib import Path
from datetime import datetime
from fastapi import APIRouter, UploadFile, File, HTTPException, Request, Depends
from PIL import Image
from app.inference.prescription_ocr import extract_drug_info
from app.services.permit_service import (
    get_item_seq_by_edi_code,
    search_permit_by_keywords,
    get_permit_summary,
)
from app.core.dependencies import get_current_user

router = APIRouter()

# ✅ 업로드 폴더 설정
BASE_DIR = Path(__file__).resolve().parent.parent.parent  # app
UPLOAD_DIR = BASE_DIR / "inference" / "ocr-uploaded"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

'''
@router.post("/prescription-ocr", summary="처방전 OCR 분석 (보험코드+약품명 추출)")
async def prescription_ocr_route(
    request: Request,
    file: UploadFile = File(...),
    #user_id: str = Depends(get_current_user)
):
    """
    업로드된 처방전 이미지를 OCR 분석하여 보험코드와 약품명을 추출합니다.
    """
    start_time = time.time()

    try:
        # ✅ 이미지 읽기
        image_bytes = await file.read()
        try:
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"이미지 파일 열기 실패: {str(e)}")

        # ✅ 임시 파일 저장
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{timestamp}_{file.filename}"
        save_path = os.path.join(UPLOAD_DIR, filename)
        with open(save_path, "wb") as f:
            f.write(image_bytes)
        print(f"✅ 업로드된 처방전 이미지 저장: {save_path}")

        # ✅ OCR 실행
        drug_list = extract_drug_info(save_path)

        if not drug_list:
            raise HTTPException(status_code=404, detail="보험코드 또는 약품명을 인식하지 못했습니다.")

        elapsed = round(time.time() - start_time, 4)
        print(f"📌 [API /prescription-ocr] 처리 시간: {elapsed}초")

        # ✅ 결과 반환
        return {
            "message": "처방전 OCR 완료",
            "processing_time_sec": elapsed,
            "results": [{"보험코드": code, "약품명": name} for code, name in drug_list]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OCR 처리 중 오류: {str(e)}")
'''
@router.post("/prescription-ocr-auto", summary="처방전 OCR + 자동 item_seq 매핑 (보험코드/이름 fallback)")
async def prescription_ocr_auto_match(
    request: Request,
    file: UploadFile = File(...)
):
    """
    1️⃣ OCR로 보험코드/약명 추출
    2️⃣ 보험코드 기반 item_seq 매핑
    3️⃣ 실패 시 키워드 fallback 검색
    4️⃣ 각 item_seq의 약 요약정보 조회 후 사용자에게 반환
    """

    start_time = time.time()
    try:
        # ✅ 이미지 읽기
        image_bytes = await file.read()
        try:
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"이미지 파일 열기 실패: {str(e)}")

        # ✅ 업로드 경로 저장
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_name = Path(file.filename).name  # 클라이언트 경로 제거
        save_path = UPLOAD_DIR / f"{timestamp}_{safe_name}"
        with open(save_path, "wb") as f:
            f.write(image_bytes)
        print(f"✅ OCR 이미지 저장: {save_path}")

        # ✅ 1. OCR 수행
        ocr_results = extract_drug_info(str(save_path))
        if not ocr_results:
            raise HTTPException(status_code=422, detail="OCR_FAIL_NO_TEXT")

        final_items = []  # [{약명, 보험코드, item_seq, summary}]
        item_seq_list = []

        # ✅ 2. OCR 결과 반복 (비동기 처리)
        for code, name in ocr_results:
            matched_item_seq = None

            # (1) 보험코드 기반 item_seq 매핑
            if code:
                try:
                    seqs = await get_item_seq_by_edi_code(code)
                    if seqs:
                        matched_item_seq = seqs[0]
                except Exception:
                    pass

            # (2) 보험코드 실패 시 → 이름 기반 검색 fallback
            if not matched_item_seq:
                try:
                    kw_result = await search_permit_by_keywords(request, name, user_id="ocr-system")
                    if kw_result.get("items"):
                        matched_item_seq = kw_result["items"][0].get("itemSeq")
                except Exception:
                    pass

            # (3) item_seq가 확보된 경우 summary 추가
            summary_data = {}
            if matched_item_seq:
                try:
                    summary_data = await get_permit_summary(matched_item_seq)
                    item_seq_list.append(matched_item_seq)
                except Exception:
                    summary_data = {}

            final_items.append({
                "보험코드": code,
                "약품명": name,
                "item_seq": matched_item_seq,
                "summary": summary_data
            })

        elapsed = round(time.time() - start_time, 3)

        # ✅ 3. 결과 리턴
        return {
            "message": "OCR 및 item_seq 매핑 완료",
            "processing_time_sec": elapsed,
            "total_items": len(final_items),
            "results": final_items,
            "item_seqs": item_seq_list,  # /api/v2/log 통합조회용
        }

    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OCR 처리 중 오류 발생: {str(e)}")