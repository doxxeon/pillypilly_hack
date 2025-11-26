# app/api/v3/image_based.py
import time
import io
import os
import json
import asyncio
import traceback
from datetime import datetime
from typing import Optional

from fastapi import (
    APIRouter,
    UploadFile,
    File,
    HTTPException,
    Request,
    Depends,
    Form,
    BackgroundTasks,
)
from PIL import Image

from app.core.dependencies import get_current_user
from app.inference.image_model import predict_pill_with_ocr_color
from app.services.permit_service import get_permit_summary
from app.db.crud.user_auth import upsert_anonymous_user
from app.services.model_log_service import log_model_result_to_mongo
from app.core.errors import ModelInferenceError, ExternalApiError
from app.core.rate_limit import rate_limit_user, concurrency_limit

# 세션/이미지 진행 CRUD
from app.db.crud.prescription_model_log import (
    upsert_pill_image_queued,
    mark_pill_running,
    save_pill_inference_done,
    increment_received_count,
    increment_completed_count,
    touch_expected_count,
    get_rx_set,
)

from app.services.rerank import rerank_with_rx

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


@router.post(
    "/image-search",
    summary="이미지 기반 알약 예측 및 요약 조회",
    dependencies=[
        Depends(rate_limit_user("image_search", limit=15, window_s=60)),
        Depends(concurrency_limit("image_search", per_user=1, global_limit=4)),
    ],
)
async def image_search_summary(
    request: Request,
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user),
    prescription_id: Optional[str] = Form(None),
    order_index: Optional[int] = Form(None),
    expected_count: Optional[int] = Form(None),
    run_async: Optional[bool] = Form(True),

    background_tasks: BackgroundTasks = None,
):
    """
    [기능]
    처방전 세션 모드에서 업로드된 이미지를 비동기로 처리하는 백그라운드 작업입니다.

    [동작 설명]
    1) 해당 이미지의 상태를 RUNNING으로 변경
    2) YOLO + OCR + 색상 기반 예측 수행
    3) 모델 결과를 다음 정보로 저장:
       - raw_top20: 모델이 예측한 상위 후보들
       - reranked: 처방 정보 기반 재랭킹 결과
       - selected: 최종 선택된 결과 1개
       - error 발생 시 status=ERROR 로 저장
    4) 처리 완료 후 세션의 completed_count 증가
       (실패도 완료로 간주)

    [프론트 영향]
    - 프론트는 즉시 결과를 받을 수 없으며,
      이후 /prescriptions/{id}/results 를 주기적으로 조회해
      전체 처리된 이미지를 모니터링하면 됨.
    """
    start_time = time.time()
    await upsert_anonymous_user(user_id, request)

    # 공통: 이미지 저장
    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="빈 파일입니다.")
    try:
        Image.open(io.BytesIO(image_bytes)).convert("RGB")  # 형식 점검
    except Exception:
        raise HTTPException(status_code=400, detail="이미지 열기 실패")

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    orig_ext = os.path.splitext(file.filename)[1].lower()
    filename = f"{timestamp}{orig_ext}"
    save_path = os.path.join(UPLOAD_DIR, filename)
    with open(save_path, "wb") as f:
        f.write(image_bytes)

    # ─────────────────────────────────────────
    # A) 세션 미연계 → 기존 동기 파이프라인 유지
    # ─────────────────────────────────────────
    if not prescription_id:
        try:
            img = Image.open(save_path).convert("RGB")
            result = predict_pill_with_ocr_color(
                img,
                color_json,
                label_json,
                type_json,
                mode="cosine",
                user_id=user_id,
            )
            if result is None or result[0] is None:
                raise ModelInferenceError(
                    "알약 식별 실패 (bbox 없음 또는 예측 실패)",
                    context={"reason": "no_result"},
                )
            (
                scored,
                bbox,
                ocr_keywords,
                color_vector,
                predicted_type,
            ) = result
            if not scored:
                raise ModelInferenceError(
                    "알약 식별 실패 (score 결과 없음)",
                    context={"reason": "no_candidates"},
                )

            # 정규화된 predictions (itemSeq는 문자열)
            predictions = [
                {
                    "itemSeq": str(x["item_seq"]),
                    "finalScore": float(x.get("final_score", 0.0)),
                    "yoloScore": float(x.get("yolo_score", 0.0)),
                    "ocrScore": float(x.get("ocr_score", 0.0)),
                    "colorScore": float(x.get("color_score", 0.0)),
                }
                for x in scored
                if x.get("item_seq") is not None
            ]

            mapped_item_seqs = [
                class_mapping.get(p["itemSeq"], p["itemSeq"]) for p in predictions
            ]
            summary_list = await asyncio.gather(
                *[get_permit_summary(seq) for seq in mapped_item_seqs]
            )

            await log_model_result_to_mongo(
                user_id=user_id,
                image_bytes=image_bytes,
                filename=filename,
                top_k=predictions,
                summary=summary_list,
                ocr_keywords=ocr_keywords,
            )

            return {
                "message": f"ocr 결과: {ocr_keywords}",
                "top_k": predictions,
                "summary": summary_list,
            }
        except Exception as e:
            raise ExternalApiError(
                f"이미지 인식 처리 중 오류: {str(e)}",
                code="IMAGE_INFERENCE_ERROR",
                context={"error_type": type(e).__name__},
            )

    # ─────────────────────────────────────────
    # B) 세션 연계(비동기) 경로
    # ─────────────────────────────────────────
    if order_index is None:
        raise HTTPException(
            status_code=400,
            detail="order_index가 필요합니다. (0..N-1)",
        )

    # 세션 expected_count 없으면 최초 1회 채움
    if expected_count is not None:
        try:
            await touch_expected_count(prescription_id, int(expected_count))
        except Exception:
            pass

    # 큐잉 + 수신 카운터 증가
    await upsert_pill_image_queued(prescription_id, int(order_index), save_path)
    await increment_received_count(prescription_id)

    # 백그라운드 태스크 등록 (동기 모델을 스레드로 오프로딩)
    background_tasks.add_task(
        _process_image_async_task,
        prescription_id,
        int(order_index),
        save_path,
        user_id,
    )

    return {
        "message": "queued",
        "prescription_id": prescription_id,
        "order_index": int(order_index),
        "expected_count": expected_count,
        "status": "PROCESSING",
    }


async def _process_image_async_task(
    prescription_id: str,
    order_index: int,
    image_path: str,
    user_id: str,
):
    """
    [기능 개요]
    처방전 세션 모드에서 업로드된 이미지를
    비동기로 처리하는 백그라운드 작업입니다.

    [동작 설명]
    1) 해당 이미지의 상태를 RUNNING으로 변경
    2) YOLO + OCR + 색상 기반 예측 수행
    3) 모델 결과를 다음 정보로 저장:
       - raw_top20: 모델이 예측한 상위 후보들
       - reranked: 처방 정보 기반 재랭킹 결과
       - selected: 최종 선택된 결과 1개
       - error 발생 시 status=ERROR 로 저장
    4) 처리 완료 후 세션의 completed_count 증가
       (실패도 완료로 간주)

    [프론트 영향]
    - 프론트는 즉시 결과를 받을 수 없으며,
      이후 /prescriptions/{id}/results 를 주기적으로 조회해
      전체 처리된 이미지를 모니터링하면 됨.
    """
    try:
        await mark_pill_running(prescription_id, order_index)

        def _run_sync():
            img = Image.open(image_path).convert("RGB")
            return predict_pill_with_ocr_color(
                img,
                color_json,
                label_json,
                type_json,
                mode="cosine",
                user_id=user_id,
            )

        result = await asyncio.to_thread(_run_sync)
        if result is None or result[0] is None:
            raise ModelInferenceError(
                "알약 식별 실패 (bbox 없음 또는 예측 실패)",
                context={"reason": "no_result"},
            )

        (
            scored,
            bbox,
            ocr_keywords,
            color_vector,
            predicted_type,
        ) = result

        # ★ scored를 문자열 기반 normalized 리스트로 변환
        normalized_scored = []
        for x in (scored or []):
            seq = x.get("item_seq")
            if seq is None:
                continue
            normalized_scored.append(
                {
                    "item_seq": str(seq).strip(),
                    "final_score": float(x.get("final_score", 0.0)),
                    "yolo_score": float(x.get("yolo_score", 0.0)),
                    "ocr_score": float(x.get("ocr_score", 0.0)),
                    "color_score": float(x.get("color_score", 0.0)),
                }
            )

        # raw_top20 (item_seq는 문자열)
        raw_top20 = [
            {
                "item_seq": y["item_seq"],
                "final_score": y["final_score"],
            }
            for y in normalized_scored
        ]

        # 세션의 rx_set 조회
        rx_set = await get_rx_set(prescription_id)

        # ★ 정규화된 scored를 넘겨서 처방 교집합 기준 재랭킹
        reranked, selected = rerank_with_rx(
            normalized_scored,
            rx_set,
            prescription_id=prescription_id,
        )

        await save_pill_inference_done(
            prescription_id,
            order_index,
            inference={
                "raw_top20": raw_top20,
                "reranked": reranked,
                "selected": selected or {},
                "ocr_keywords": ocr_keywords,
                "color_vector": color_vector,
                "pill_type": predicted_type,
            },
            image_path=image_path,
            status="DONE",
        )
        await increment_completed_count(prescription_id)

    except Exception as e:
        err_msg = f"{type(e).__name__}: {str(e)}"
        await save_pill_inference_done(
            prescription_id,
            order_index,
            inference={"error": err_msg, "trace": traceback.format_exc()[-1000:]},
            image_path=image_path,
            status="ERROR",
        )
        await increment_completed_count(prescription_id)
