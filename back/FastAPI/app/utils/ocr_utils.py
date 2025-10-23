import os
import io
import re
from typing import List
from PIL import Image
from google.cloud import vision
from app.core.config import settings

# Google Cloud Vision API 인증 키 경로 설정
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = settings.ocr_key_path
vision_client = vision.ImageAnnotatorClient()

def detect_text_pill(image: Image.Image) -> List[str]:
    """
    입력된 이미지에서 텍스트 인식 (OCR) 후 키워드 리스트 반환
    """
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    content = buf.getvalue()
    image_proto = vision.Image(content=content)
    response = vision_client.text_detection(image=image_proto)

    if response.error.message:
        print(f"OCR 오류: {response.error.message}")
        return []

    texts = response.text_annotations
    if not texts:
        return []

    raw_keywords = texts[0].description.strip().split()

    # 리스트 컴프리헨션으로 필터링: 'pill' 또는 '숫자+%' 제거
    keywords = [
        word.upper()
        for word in raw_keywords
        if word.lower() != "pill" and not re.fullmatch(r"\d+(\.\d+)?%", word)
    ]

    return keywords