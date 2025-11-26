from google.cloud import vision
import io
import cv2
import numpy as np
import os
import re
from pathlib import Path
import time
from app.core.config import settings
from app.utils.logger import logger_prescription, logger_error

# Google Cloud Vision 인증
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = settings.google_vision_key_path
client = vision.ImageAnnotatorClient()

INFER_BASE_DIR = Path(__file__).resolve().parent
PROCESSED_DIR = INFER_BASE_DIR / "ocr-processed"
PROCESSED_DIR.mkdir(parents=True, exist_ok=True)


# ---------- 한글 경로 이미지 읽기 ----------
def imread_unicode(path):
    with open(path, "rb") as stream:
        bytes_array = bytearray(stream.read())
    np_array = np.asarray(bytes_array, dtype=np.uint8)
    return cv2.imdecode(np_array, cv2.IMREAD_COLOR)


# ---------- 이미지 전처리 ----------
def preprocess_image(image_path):
    """OCR 전처리: 해상도 확대 + 대비 강화 + 이진화 + 글자 두껍게"""
    image_path = Path(image_path)
    if not image_path.exists():
        logger_prescription.error(f"❌ 입력 이미지가 없습니다: {image_path}")
        raise FileNotFoundError(f"입력 이미지가 없습니다: {image_path}")

    img = imread_unicode(image_path)
    if img is None:
        logger_prescription.error(f"❌ 이미지를 읽을 수 없습니다: {image_path}")
        raise ValueError(f"이미지를 읽을 수 없습니다: {image_path}")

    start = time.time()
    # 1️⃣ 그레이스케일
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 2️⃣ 해상도 확대
    scale_percent = 150
    width = int(gray.shape[1] * scale_percent / 100)
    height = int(gray.shape[0] * scale_percent / 100)
    gray = cv2.resize(gray, (width, height), interpolation=cv2.INTER_CUBIC)

    # 3️⃣ 블러로 잡음 제거
    gray = cv2.bilateralFilter(gray, 9, 75, 75)

    # 4️⃣ Adaptive Threshold (얇은 글자 강조)
    gray = cv2.adaptiveThreshold(
        gray,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        15,
        5,
    )

    # 5️⃣ Morphology (글자 두껍게)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    gray = cv2.dilate(gray, kernel, iterations=1)

    # 6️⃣ 결과 저장
    ts = int(time.time() * 1000)
    processed_path = PROCESSED_DIR / f"{image_path.stem}_proc_{ts}.jpg"
    cv2.imwrite(processed_path, gray)

    logger_prescription.info(
        f"[처방전 OCR] 전처리 완료: src={image_path}, proc={processed_path}, "
        f"elapsed={round(time.time() - start, 4)}초"
    )
    return str(processed_path)


# ---------- Google OCR ----------
def extract_text_from_image(image_path):
    start = time.time()
    with io.open(image_path, "rb") as image_file:
        content = image_file.read()

    image = vision.Image(content=content)
    response = client.text_detection(image=image)
    if response.error.message:
        logger_prescription.error(
            f"[처방전 OCR] Vision API 오류: {response.error.message}"
        )
        raise RuntimeError(response.error.message)

    texts = response.text_annotations
    if not texts:
        logger_prescription.warning(
            f"[처방전 OCR] OCR 결과 없음: image_path={image_path}"
        )
        return "", []

    full_text = texts[0].description
    boxes = [
        (t.description, [(v.x, v.y) for v in t.bounding_poly.vertices])
        for t in texts[1:]
    ]

    logger_prescription.info(
        f"[처방전 OCR] Vision OCR 완료"
        f"box_count={len(boxes)}, elapsed={round(time.time() - start, 4)}초"
    )
    return full_text, boxes


# ---------- 보험코드 + 약품명 + 용량 숫자들 추출 ----------
def extract_drug_names(full_text):
    import re

    # --- 처방 구간 자르기 ---
    start_match = re.search(r"처방\s*의약품의\s*명칭", full_text)
    if not start_match:
        logger_prescription.warning(
            "[처방전 OCR] '처방 의약품의 명칭' 구간 미발견, 약품 파싱 스킵"
        )
        return []

    start_idx = start_match.end()
    end_match = re.search(r"(조제약사|주의사항|복약지도|비고|Signature|서명)", full_text)
    end_idx = end_match.start() if end_match else len(full_text)
    drug_section = full_text[start_idx:end_idx]

    # --- 패턴 정의 ---
    FORM = r"(?:정|캡슐|캅셀|필름|산|액|시럽|현탁액|연고|크림|정제|환|병)"
    DOSE = r"(\d+(?:\.\d+)?\s*(?:mg|ml|g|㎎|㎖))"  # capture group
    NAME = rf"[가-힣A-Za-z0-9\-/\.\(\)\s]+?{FORM}"

    # --- Full pattern (code + name + dose + once/day/total) ---
    pattern_full = (
        rf"(\d{{6,9}})\s*"        # code
        rf"({NAME})"              # name
        rf"(?:\s*{DOSE})?"        # optional dose
        r"\s+(\d+(?:\.\d+)?)"     # once
        r"\s+(\d+(?:\.\d+)?)"     # day
        r"\s+(\d+(?:\.\d+)?)"     # total
    )

    matches_full = re.findall(pattern_full, drug_section)
    drugs = []
    seen = set()

    # ======================
    # 1) Full match 처리
    # ======================
    if matches_full:
        for m in matches_full:
            # m = (code, raw_name, dose?, once, day, total)
            row = list(m)

            # row = [code, name, dose?, once, day, total]
            code = row[0]
            raw_name = row[1]
            dose = row[2] or ""   # dose가 None/""일 수 있음
            once = row[3]
            day = row[4]
            total = row[5]

            if code in seen:
                continue
            seen.add(code)

            # --- name 내부에서 dose가 붙어있는 경우 분리 ---
            if not dose:
                m2 = re.search(DOSE, raw_name)
                if m2:
                    dose = m2.group(1)
                    raw_name = raw_name.replace(dose, "")

            # --- /1정 /1캅셀 /5ml/병 제거 ---
            name = raw_name
            name = re.sub(r"/\s*\d*\s*(정|캅셀|캡슐|병)", "", name)
            name = re.sub(r"/\s*\d+\.?\d*\s*(mg|ml|g|㎎|㎖)", "", name)
            name = name.strip()

            drugs.append(
                (
                    code.strip(),
                    name,
                    dose.strip(),
                    once.strip(),
                    day.strip(),
                    total.strip(),
                )
            )

        logger_prescription.info(
            f"[처방전 OCR] Full 패턴 파싱 완료: drug_count={len(drugs)}"
        )
        return drugs

    # ======================
    # 2) fallback: 약명만 있을 때
    # ======================
    pattern_simple = rf"(\d{{6,9}})\s*({NAME})(?:\s*{DOSE})?"
    matches_simple = re.findall(pattern_simple, drug_section)

    for m in matches_simple:
        row = list(m)

        code = row[0]
        raw_name = row[1]
        dose = row[2] if len(row) > 2 else ""

        if code in seen:
            continue
        seen.add(code)

        # name 내부에서 dose 분리
        if not dose:
            m2 = re.search(DOSE, raw_name)
            if m2:
                dose = m2.group(1)
                raw_name = raw_name.replace(dose, "")

        name = raw_name
        name = re.sub(r"/\s*\d*\s*(정|캅셀|캡슐|병)", "", name)
        name = re.sub(r"/\s*\d+\.?\d*\s*(mg|ml|g|㎎|㎖)", "", name)
        name = name.strip()

        drugs.append((code.strip(), name, dose.strip(), "", "", ""))

    logger_prescription.info(
        f"[처방전 OCR] Simple 패턴 파싱 완료: drug_count={len(drugs)}"
    )
    return drugs


# ---------- 메인 함수 ----------
def extract_drug_info(image_path: str):
    """
    입력: 처방전 이미지 경로
    출력: [(보험코드, 약품명, 1회투약량, 1일투여횟수, 총투약일수), ...]
    """
    total_start = time.time()
    logger_prescription.info(f"[처방전 OCR] 시작")

    try:
        processed_path = preprocess_image(image_path)

        ocr_start = time.time()
        full_text, _ = extract_text_from_image(processed_path)
        logger_prescription.info(
            f"[처방전 OCR] OCR 완료: elapsed={round(time.time() - ocr_start, 4)}초"
        )

        parse_start = time.time()
        drug_list = extract_drug_names(full_text)
        logger_prescription.info(
            f"[처방전 OCR] 약품 파싱 완료: count={len(drug_list)}, "
            f"elapsed={round(time.time() - parse_start, 4)}초"
        )

        logger_prescription.info(
            f"[처방전 OCR] 전체 완료: "
            f"total_elapsed={round(time.time() - total_start, 4)}초"
        )
        return drug_list

    except FileNotFoundError as e:
        msg = f"이미지 파일이 존재하지 않습니다: {str(e)}"
        logger_prescription.error(f"[처방전 OCR] FileNotFoundError: {msg}")
        logger_error.error(f"[처방전 OCR] FileNotFoundError: {msg}")
        raise FileNotFoundError(msg)

    except RuntimeError as e:
        msg = f"OCR 처리 중 오류 발생: {e}"
        logger_prescription.error(f"[처방전 OCR] RuntimeError: {msg}")
        logger_error.error(f"[처방전 OCR] RuntimeError: {msg}")
        raise RuntimeError(msg)

    except Exception as e:
        msg = f"처방전 분석 중 알 수 없는 오류 발생: {e}"
        logger_prescription.error(f"[처방전 OCR] UnexpectedError: {msg}")
        logger_error.error(f"[처방전 OCR] UnexpectedError: {msg}")
        raise Exception(msg)

