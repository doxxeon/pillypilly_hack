from google.cloud import vision
import io
import cv2
import numpy as np
import os
import re
from pathlib import Path
import time
from app.core.config import settings

# ✅ Google Cloud Vision 인증 (사용 전 JSON 경로 수정)
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = settings.google_vision_key_path
client = vision.ImageAnnotatorClient()

INFER_BASE_DIR = Path(__file__).resolve().parent  # app/inference
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
        raise FileNotFoundError(f"입력 이미지가 없습니다: {image_path}")

    img = imread_unicode(image_path)
    if img is None:
        raise ValueError(f"이미지를 읽을 수 없습니다: {image_path}")

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
        gray, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        15, 5
    )

    # 5️⃣ Morphology (글자 두껍게)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    gray = cv2.dilate(gray, kernel, iterations=1)

    # 6️⃣ 결과 저장
    ts = int(time.time() * 1000)
    processed_path = PROCESSED_DIR / f"{image_path.stem}_proc_{ts}.jpg"
    cv2.imwrite(processed_path, gray)
    return str(processed_path)


# ---------- Google OCR ----------
def extract_text_from_image(image_path):
    with io.open(image_path, 'rb') as image_file:
        content = image_file.read()

    image = vision.Image(content=content)
    response = client.text_detection(image=image)
    if response.error.message:
        raise RuntimeError(response.error.message)

    texts = response.text_annotations
    if not texts:
        return "", []

    full_text = texts[0].description
    boxes = [(t.description, [(v.x, v.y) for v in t.bounding_poly.vertices]) for t in texts[1:]]
    return full_text, boxes


# ---------- 보험코드 + 약품명 추출 ----------
def extract_drug_names(full_text):
    """처방 의약품의 명칭 구간에서 (보험코드, 약품명) 추출"""
    start_match = re.search(r"처방\s*의약품의\s*명칭", full_text)
    if not start_match:
        return []

    start_idx = start_match.end()
    end_match = re.search(r"(조제약사|주의사항|복약지도|비고|Signature|서명)", full_text)
    end_idx = end_match.start() if end_match else len(full_text)

    drug_section = full_text[start_idx:end_idx]

    pattern = r"(\d{6,9})\s*([가-힣A-Za-z0-9\-]+(?:정|캡슐|필름|산|액|시럽|현탁액|연고|크림|겔|정제|정캡슐|환))(?:\s*\d*\.?\d*\s*(?:mg|ml|g))?"
    matches = re.findall(pattern, drug_section)

    # 중복 제거
    drugs = list({code: name for code, name in matches}.items())
    return drugs


# ---------- 메인 함수 (하나로 실행 가능) ----------
def extract_drug_info(image_path: str):
    """
    입력: 처방전 이미지 경로
    출력: [(보험코드, 약품명), ...]
    """
    try:
        processed_path = preprocess_image(image_path)
        full_text, _ = extract_text_from_image(processed_path)
        drug_list = extract_drug_names(full_text)

        return drug_list

    except FileNotFoundError as e:
        raise FileNotFoundError(f"이미지 파일이 존재하지 않습니다: {str(e)}")

    except RuntimeError as e:
        raise RuntimeError(f"OCR 처리 중 오류 발생: {e}")

    except Exception as e:
        raise Exception(f"처방전 분석 중 알 수 없는 오류 발생: {e}")



# ---------- 실행 예시 ----------
'''
from prescription_ocr import extract_drug_info

result = extract_drug_info("처방전 경로")

for code, name in result:
    print(code, name)

결과 예시)
670700376 바이겔크림
653402930 록페린정
'''