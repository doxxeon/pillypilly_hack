# app/api/v3/image_based.py
import time
import io
import os
import json
import asyncio
from fastapi import APIRouter, UploadFile, File, HTTPException, Request, Depends
from PIL import Image
from app.core.dependencies import get_current_user
from app.inference.image_model import predict_pill_with_ocr_color  
from app.services.permit_service import get_permit_summary
from datetime import datetime
from app.db.crud.user_auth import upsert_anonymous_user
from app.services.model_log_service import log_model_result_to_mongo
from app.core.errors import ModelInferenceError, ExternalApiError
from app.core.rate_limit import rate_limit_user, concurrency_limit

router = APIRouter()

UPLOAD_DIR = "app/inference/imput_img"
os.makedirs(UPLOAD_DIR, exist_ok=True)

with open("app/inference/resources/label_data.json", "r", encoding="utf-8") as f:
    label_json = json.load(f)
with open("app/inference/resources/class_mapping.json", "r", encoding="utf-8") as f:
    class_mapping = json.load(f)
with open("app/inference/resources/color_map2.json", "r", encoding="utf-8") as f:
    color_json = json.load(f)
with open("app/inference/resources/3type_label.json", "r", encoding="utf-8") as f:
    type_json = json.load(f)

@router.post("/image-search", summary="이미지 기반 알약 예측 및 요약 조회",
                 dependencies=[
                    Depends(rate_limit_user("image_search", limit=5, window_s=60)),   # 분당 5회/유저
                    Depends(concurrency_limit("image_search", per_user=1, global_limit=4)),  # 동시에 유저당 1개, 전체 4개
                ],
    ) 
async def image_search_summary(
    request: Request, 
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user)
):
    start_time = time.time()
    await upsert_anonymous_user(user_id, request)
    try:
        image_bytes = await file.read()
        try:
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"이미지 열기 실패: {str(e)}")

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{timestamp}_{file.filename}"
        save_path = os.path.join(UPLOAD_DIR, filename)
        with open(save_path, "wb") as f:
            f.write(image_bytes)
        print(f"✅ 업로드 이미지 저장: {save_path}")

        # ✅ 예측 수행
        result = predict_pill_with_ocr_color(image, color_json, label_json, type_json, mode="cosine", user_id=user_id)

        # ✅ 결과 유효성 검사
        if result is None or result[0] is None:
            # 예외처리
            raise ModelInferenceError("알약 식별 실패 (bbox 없음 또는 예측 실패)", context={"reason": "no_result"})

        scored, bbox, ocr_keywords = result

        if not scored:
            # 예외처리
            raise ModelInferenceError("알약 식별 실패 (score 결과 없음)", context={"reason": "no_candidates"})

        # ✅ 결과 리스트 구성
        item_seq_list = [x["item_seq"] for x in scored]
        predictions = [
            {
                "itemSeq": x["item_seq"],
                "finalScore": x["final_score"],
                "yoloScore": x["yolo_score"],
                "ocrScore": x["ocr_score"],
                "colorScore": x["color_score"]
            } for x in scored
        ]

        # ✅ 요약 정보 조회
        mapped_item_seqs = [class_mapping.get(seq["itemSeq"], seq["itemSeq"]) for seq in predictions]
        summary_list = await asyncio.gather(*[get_permit_summary(seq) for seq in mapped_item_seqs])

        # ✅ 예측 결과 MongoDB 저장 (이 위치에 추가)
        await log_model_result_to_mongo(
            user_id=user_id,
            image_bytes=image_bytes,
            filename=filename,
            top_k=predictions,
            summary=summary_list,
            ocr_keywords=ocr_keywords
        )

        elapsed = round(time.time() - start_time, 4)
        print(f"📌 [API /image_search] 처리 시간: {elapsed}초")

        return {
            "message": f"ocr 결과: {ocr_keywords}",
            "top_k": predictions,
            "summary": summary_list
        }

    except Exception:
        # 예외처리
        raise
