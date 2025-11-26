from google.cloud import vision
import io
import cv2
import numpy as np
import os
import re
from app.core.config import settings
from app.utils.logger import logger_dateex, logger_error

os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = settings.google_vision_key_path
client = vision.ImageAnnotatorClient()


def imread_unicode(path):
    """한글 경로 이미지 읽기"""
    with open(path, "rb") as stream:
        bytes_array = bytearray(stream.read())
    np_array = np.asarray(bytes_array, dtype=np.uint8)
    return cv2.imdecode(np_array, cv2.IMREAD_COLOR)


def extract_text_blocks(image_path=None, image_array=None):
    """
    Google Vision OCR을 이용하여 이미지에서 텍스트 블록 추출
    image_path: 이미지 파일 경로 (기존 방식)
    image_array: numpy 배열 이미지 (회전된 이미지용)
    """
    if image_array is not None:
        _, encoded_image = cv2.imencode('.jpg', image_array)
        content = encoded_image.tobytes()
    else:
        with io.open(image_path, 'rb') as f:
            content = f.read()

    image = vision.Image(content=content)
    response = client.text_detection(image=image)
    texts = response.text_annotations
    if not texts:
        return []

    return texts[1:]


def _extract_date_from_text(full_text):
    """
    텍스트에서 날짜를 추출하는 헬퍼 함수
    """
    date_pattern_4digit = r"\d{4}[./-]\d{2}[./-]\d{2}"
    matches = re.findall(date_pattern_4digit, full_text)
    
    if matches:
        result = matches[0]
        logger_dateex.info(f"[유통기한 추출] 4자리 연도 패턴 매칭: {result}")
        return result
    
    date_pattern_2digit = r"\d{2}[./-]\d{2}[./-]\d{2}"
    matches_2digit = re.findall(date_pattern_2digit, full_text)
    
    if matches_2digit:
        date_str = matches_2digit[0]
        separator = re.search(r"[./-]", date_str).group()
        parts = date_str.split(separator)
        if len(parts) == 3:
            year_2digit = parts[0]
            month = parts[1]
            day = parts[2]
            year_4digit = f"20{year_2digit}"
            result = f"{year_4digit}{separator}{month}{separator}{day}"
            logger_dateex.info(f"[유통기한 추출] 2자리 연도 패턴 매칭 및 변환: {date_str} -> {result}")
            return result
        
    return None


def extract_expiry_date_from_box(image_path):
    """
    약봉투 이미지에서 사용기한/유통기한 추출
    OCR 결과가 없거나 키워드를 찾지 못하면 이미지를 90도씩 회전하여 재시도
    """
    logger_dateex.info(f"[유통기한 추출] 시작: {image_path}")
    
    img = imread_unicode(image_path)
    if img is None:
        error_msg = "이미지를 읽을 수 없습니다."
        logger_dateex.error(f"[유통기한 추출] {error_msg}: {image_path}")
        logger_error.error(f"[유통기한 추출] {error_msg}: {image_path}")
        return "이미지를 읽을 수 없습니다."

    ocr_results = extract_text_blocks(image_path=image_path)
    
    # OCR 결과가 없거나 키워드가 없으면 회전 시도
    should_rotate = False
    found_keyword = False
    if not ocr_results:
        logger_dateex.info("[유통기한 추출] OCR 결과가 없어 이미지 회전 시도")
        should_rotate = True
    else:
        full_text = "".join([t.description.replace(" ", "") for t in ocr_results])
        logger_dateex.info(f"[유통기한 추출] OCR 텍스트 (앞부분): {full_text[:200]}...")
        
        if not any(keyword in full_text for keyword in ["사용기한", "유통기한", "유효기한", "유효기간"]):
            logger_dateex.info("[유통기한 추출] 키워드를 찾지 못해 이미지 회전 시도")
            should_rotate = True
        else:
            # 키워드가 발견되었으므로 날짜 추출 시도
            logger_dateex.info("[유통기한 추출] 사용기한/유통기한 키워드 발견")
            found_keyword = True
            date_result = _extract_date_from_text(full_text)
            if date_result:
                return date_result

    # 원본에서 키워드를 찾았지만 날짜를 못 찾은 경우 (회전 시도 없이 바로 반환)
    if found_keyword:
        warning_msg = "사용기한 글씨는 존재하지만 날짜를 찾지 못했습니다. 다른 면을 촬영해주세요."
        logger_dateex.warning(f"[유통기한 추출] {warning_msg}")
        return "사용기한 글씨는 존재하지만 날짜를 찾지 못했습니다. 다른 면을 촬영해주세요."

    # 회전 시도
    if should_rotate:
        for angle in [90, 180, 270]:
            logger_dateex.info(f"[유통기한 추출] 이미지 {angle}도 회전하여 OCR 재시도")
            h, w = img.shape[:2]
            center = (w // 2, h // 2)
            rotation_matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
            rotated_img = cv2.warpAffine(img, rotation_matrix, (w, h))
            
            ocr_results = extract_text_blocks(image_array=rotated_img)
            
            if ocr_results:
                full_text = "".join([t.description.replace(" ", "") for t in ocr_results])
                logger_dateex.info(f"[유통기한 추출] {angle}도 회전 후 OCR 텍스트 (앞부분): {full_text[:200]}...")
                
                if any(keyword in full_text for keyword in ["사용기한", "유통기한", "유효기한", "유효기간"]):
                    logger_dateex.info(f"[유통기한 추출] {angle}도 회전 후 사용기한/유통기한 키워드 발견")
                    date_result = _extract_date_from_text(full_text)
                    if date_result:
                        return date_result
                    warning_msg = "사용기한 글씨는 존재하지만 날짜를 찾지 못했습니다. 다른 면을 촬영해주세요."
                    logger_dateex.warning(f"[유통기한 추출] {warning_msg}")
                    return "사용기한 글씨는 존재하지만 날짜를 찾지 못했습니다. 다른 면을 촬영해주세요."
    
        warning_msg = "사용기한 정보를 찾지 못했습니다. 다른 면을 촬영해주세요."
        logger_dateex.warning(f"[유통기한 추출] {warning_msg}")
        return "사용기한 정보를 찾지 못했습니다. 다른 면을 촬영해주세요."


def get_expiry_date(image_path):
    try:
        result = extract_expiry_date_from_box(image_path)
        logger_dateex.info(f"[유통기한 추출] 완료: {result}")
        return result
    except Exception as e:
        error_msg = f"유통기한 추출 중 오류 발생: {str(e)}"
        logger_dateex.error(f"[유통기한 추출] {error_msg}")
        logger_error.error(f"[유통기한 추출] {error_msg}")
        raise
