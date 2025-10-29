# app/inference/image_model.py
import os
import time
import numpy as np
import torch
from ultralytics import YOLO
from PIL import Image, ImageOps
from difflib import SequenceMatcher

# ✅ (3) Pillow 10/하위 호환: 리사이즈 보간 상수 일원화
try:
    from PIL import Image as PILImage
    RESAMPLING = PILImage.Resampling.BICUBIC  # Pillow >= 10
except Exception:
    RESAMPLING = Image.BICUBIC                # Pillow < 10 호환

from app.utils.model_utils import calculate_color_similarity
from app.utils.ocr_utils import detect_text_pill
from app.utils.logger import logger_model
from app.core.errors import ModelInferenceError


# ✅ 모델 경로 (변경 없음)
detect_model_path = "app/models/best_detec.pt"
cls_model_path    = "app/models/best_cls.pt"
type_model_path   = "app/models/3type_best.pt"

# ✅ 모델 로딩 (변경 없음)
det_model  = YOLO(detect_model_path)
cls_model  = YOLO(cls_model_path)
type_model = YOLO(type_model_path)


# ✅ (1) EXIF 정규화: '눈으로 보이는 방향'으로 회전 반영 + RGB 통일 + EXIF 제거
def normalize_exif(image: Image.Image) -> Image.Image:
    """
    EXIF Orientation을 실제 픽셀에 적용해 '눈으로 보이는 방향'으로 맞춤.
    이후 RGB로 통일하고 EXIF 제거해 재-회전을 방지.
    """
    img = ImageOps.exif_transpose(image)
    img = img.convert("RGB")
    img.info.pop("exif", None)
    return img


# ✅ (2) BBox 안전성 강화: 경계 클리핑 + 정수화
def get_main_bbox(image: Image.Image):
    """
    감지 모델로 최고 신뢰도 박스를 선택하고,
    이미지 경계를 벗어나지 않도록 좌표를 클리핑/정수화.
    """
    results = det_model.predict(image, verbose=False)[0]
    if results.boxes is None or len(results.boxes.xyxy) == 0:
        return None

    confidences = results.boxes.conf
    bboxes = results.boxes.xyxy
    max_idx = torch.argmax(confidences).item()
    x1, y1, x2, y2 = bboxes[max_idx].cpu().tolist()

    w, h = image.size
    x1 = int(max(0, min(x1, w - 1)))
    x2 = int(max(0, min(x2, w - 1)))
    y1 = int(max(0, min(y1, h - 1)))
    y2 = int(max(0, min(y2, h - 1)))
    if x2 <= x1 or y2 <= y1:
        return None
    return [x1, y1, x2, y2]


# ✅ (3) 리사이즈 시 Pillow 10 호환 상수 사용 + 레터박스(640x640) 동일
def preprocess_image(image: Image.Image, bbox: list, save_debug: bool = True) -> Image.Image:
    """
    감지된 bbox로 크롭 → 짧은 변 기준 400으로 리사이즈 → 640x640 캔버스 중앙 정렬(레터박스).
    """
    x1, y1, x2, y2 = map(int, bbox)
    cropped = image.crop((x1, y1, x2, y2))

    width, height = cropped.size
    if width >= height:
        new_w, new_h = 400, int(400 * height / width)
    else:
        new_w, new_h = int(400 * width / height), 400

    resized = cropped.resize((new_w, new_h), RESAMPLING)

    final_image = Image.new("RGB", (640, 640), (0, 0, 0))
    final_image.paste(resized, ((640 - new_w) // 2, (640 - new_h) // 2))

    if save_debug:
        os.makedirs("app/inference/output_pre", exist_ok=True)
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        final_image.save(f"app/inference/output_pre/output_{timestamp}.png")

    return final_image

# ✅ OCR 글자 유사도
def text_similarity(s1, s2):
    return SequenceMatcher(None, s1, s2).ratio()

# ✅ (1)(4)(5)(7) EXIF 정규화 이미지를 파이프라인 전 구간에서 일관 사용
# ✅ (5) 운영 로깅 개선: user_id 포함
def predict_pill_with_ocr_color(
        image: Image.Image, 
        color_json: dict, 
        label_json: dict, 
        type_json: dict,   # 3type 필터링용
        mode="cosine",
        alpha=0.3, 
        beta=0.2, 
        gamma=0.5,
        user_id: str = None):
    """
    최종 반환값(스펙 유지):
      - scored: List[dict(item_seq, final_score, yolo_score, ocr_score, color_score)] (상위 20)
      - bbox: [x1, y1, x2, y2]
      - ocr_keywords: List[str]
    """
    total_start = time.time()

    # ✅ 0. EXIF 방향 정규화 (가장 먼저!)
    image = normalize_exif(image)

    # ✅ 1. YOLO Detection + Preprocessing (정규화된 이미지 사용)
    det_start = time.time()
    bbox = get_main_bbox(image)
    if bbox is None:
        logger_model.warning("❌ Bounding box 추출 실패")
        # 예외처리
        raise ModelInferenceError("No bounding box detected", context={"stage": "detect"})
    processed = preprocess_image(image, bbox)
    logger_model.info(f"[YOLO-Detect] 처리 시간: {round(time.time() - det_start, 4)}초")

    # ✅ 2. 3type_cls 모델로 타입 예측 (정규화+전처리 이미지를 사용)
    type_start = time.time()
    type_results = type_model.predict(processed, verbose=False)[0]
    top_idx = int(type_results.probs.top1)
    predicted_type = type_model.names[top_idx]
    logger_model.info(f"[3type Cls] 예측 타입: {predicted_type}")
    logger_model.info(f"[3type Cls] 처리 시간: {round(time.time() - type_start, 4)}초")

    # ✅ 3. YOLO Classification
    cls_start = time.time()
    results = cls_model.predict(processed, verbose=False)[0]
    if not hasattr(results, "probs") or results.probs is None:
        logger_model.warning("⚠️ YOLO 분류 확률(probs) 없음")
        # 예외처리
        raise ModelInferenceError("No classification probabilities", context={"stage": "classify"})
    probs_tensor = results.probs.data
    class_names = cls_model.names
    logger_model.info(f"[YOLO-Cls] 처리 시간: {round(time.time() - cls_start, 4)}초")

    # ✅ 4. 색상 추출 (정규화된 원본 이미지에서 bbox 영역 중심부 평균 RGB)
    color_start = time.time()
    cropped_np = np.array(image.crop(bbox))
    h, w, _ = cropped_np.shape
    ch, cw = int(h * 0.2), int(w * 0.2)
    sh, sw = (h - ch) // 2, (w - cw) // 2
    center_crop = cropped_np[sh:sh + ch, sw:sw + cw]
    mean_rgb = np.mean(center_crop, axis=(0, 1))
    logger_model.info(f"[색상 추출] 처리 시간: {round(time.time() - color_start, 4)}초")

    # ✅ 5. OCR 텍스트 감지 (정규화된 원본 이미지 사용)
    ocr_start = time.time()
    ocr_keywords = detect_text_pill(image)
    ocr_text = "".join(ocr_keywords) if isinstance(ocr_keywords, list) else str(ocr_keywords)
    print(f"OCR 키워드 추출 결과: {ocr_keywords}")
    logger_model.info(f"[OCR 분석] 처리 시간: {round(time.time() - ocr_start, 4)}초")

    # ✅ 6. 점수 계산: 3type_cls 예측 타입과 type_json에 정의된 타입이 일치하는 후보만 계산
    score_start = time.time()
    scored = []
    for idx in range(len(probs_tensor)):
        item_seq = class_names[idx]

        # 타입 미일치 후보는 필터링
        if type_json.get(item_seq) != predicted_type:
            continue

        yolo_score = float(probs_tensor[idx].item())
        ocr_score = text_similarity(ocr_text.upper(), label_json.get(item_seq, "").upper())
        color_score = float(calculate_color_similarity(mean_rgb, color_json.get(item_seq, [0, 0, 0]), mode))
        final_score = alpha * yolo_score + beta * ocr_score + gamma * color_score
        scored.append((item_seq, final_score, yolo_score, ocr_score, color_score))

    if not scored:
        logger_model.warning("❌ 필터링 후 후보 없음")
        # 예외처리
        raise ModelInferenceError("No candidates after filtering", context={"stage": "postprocess", "predicted_type": predicted_type})

    scored.sort(key=lambda x: x[1], reverse=True)

    # 상위 20개 결과만 리턴
    scored = [
        {
            "item_seq": item,
            "final_score": round(final or 0.0, 4),
            "yolo_score": round(yolo or 0.0, 4),
            "ocr_score": ocr or 0.0,
            "color_score": round(color or 0.0, 4)
        } for item, final, yolo, ocr, color in scored[:20]
    ]
    logger_model.info(f"[점수 계산] 처리 시간: {round(time.time() - score_start, 4)}초")
    logger_model.info(f"[전체 추론 시간]: user_id={user_id}, {round(time.time() - total_start, 4)}초")

    return scored, bbox, ocr_keywords