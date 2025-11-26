# app/inference/drug_bag_split_ocr.py

import cv2
import os
import time
import re
import numpy as np
from typing import List, Dict
from google.cloud import vision
from app.core.config import settings
from app.utils.logger import logger_drugbag, logger_error

os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = settings.google_vision_key_path
client = vision.ImageAnnotatorClient()


def safe_crop(img, x1, y1, x2, y2, min_w: int = 10, min_h: int = 10):
    h, w = img.shape[:2]
    x1 = max(0, min(x1, w - 1))
    x2 = max(0, min(x2, w))
    y1 = max(0, min(y1, h - 1))
    y2 = max(0, min(y2, h))

    if x2 - x1 < min_w or y2 - y1 < min_h:
        raise ValueError(
            f"잘못된 crop 영역: ({x1},{y1})-({x2},{y2}), size=({x2-x1},{y2-y1})"
        )
    return img[y1:y2, x1:x2]


# -----------------------------
# 이미지 전처리
# -----------------------------
def preprocess_for_ocr(img):
    """
    원본 이미지를 OCR에 최적화된 전처리 수행
    """
    if img is None:
        raise ValueError("빈 이미지에 전처리 시도")
    
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.resize(gray, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
    gray = cv2.bilateralFilter(gray, 9, 75, 75)
    
    gray = cv2.adaptiveThreshold(
        gray, 255,
        cv2.ADAPTIVE_THRESH_MEAN_C,
        cv2.THRESH_BINARY,
        19, 7,
    )
    
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    gray = cv2.dilate(gray, kernel, iterations=1)
    
    return gray


# -----------------------------
# OCR 호출
# -----------------------------
def run_ocr_image(img):
    if img is None or img.size == 0:
        raise ValueError("빈 이미지에 OCR 시도")

    ok, buf = cv2.imencode(".jpg", img)
    if not ok:
        raise ValueError("이미지 인코딩 실패")

    image = vision.Image(content=buf.tobytes())
    res = client.text_detection(image=image)

    texts = res.text_annotations
    if not texts:
        return "", []

    full = texts[0].description
    boxes = []
    for t in texts[1:]:
        pts = [(v.x, v.y) for v in t.bounding_poly.vertices]
        boxes.append({"text": t.description, "bbox": pts})
    return full, boxes


def find_table_header_row(boxes) -> Dict:
    """
    OCR box 중에서 '약품명'과 '투약량/횟수/일수/총투'를 찾는다.
    """
    name_keywords = ["약품명"]
    dose_keywords = ["투약량"]
    count_keywords = ["횟수"]
    day_keywords = ["일수", "임수"]
    
    name_boxes = []
    num_boxes = []
    
    for b in boxes:
        txt = b["text"]
        clean_txt = re.sub(r"[()/]", "", txt)
        
        if any(k in clean_txt for k in name_keywords):
            if "복약안내" not in clean_txt and "안내" not in txt:
                name_boxes.append(b)
        
        if any(k in clean_txt for k in (dose_keywords + count_keywords + day_keywords)):
            if "복약안내" not in clean_txt:
                num_boxes.append(b)
    
    if not name_boxes:
        raise ValueError("약품명 헤더를 찾지 못했습니다.")
    if not num_boxes:
        raise ValueError("투약량/횟수/일수 헤더를 찾지 못했습니다.")
    header_row_boxes = name_boxes + num_boxes

    return header_row_boxes


def split_header_boxes(header_row_boxes):
    """헤더 박스를 약품명과 숫자 헤더로 분리"""
    name_keywords = ["약품명", "약 품 명"]
    num_keywords = ["투약량", "횟수", "일수", "임수"]

    name_boxes = []
    num_boxes = []

    for b in header_row_boxes:
        txt = b["text"]
        clean_txt = re.sub(r"[()/]", "", txt)
        
        if any(k in clean_txt for k in name_keywords):
            if "복약안내" not in clean_txt:
                name_boxes.append(b)
        if any(k in clean_txt for k in num_keywords):
            if "복약안내" not in clean_txt:
                num_boxes.append(b)

    if not name_boxes:
        raise ValueError("헤더 행에서 약품명 박스를 찾지 못했습니다.")
    if not num_boxes:
        raise ValueError("헤더 행에서 투약량/횟수/일수 박스를 찾지 못했습니다.")

    return name_boxes, num_boxes


def parse_drug_names_from_boxes(boxes):
    """
    약품명 영역 박스 → 줄(y) 단위 그룹 → x 정렬 → 문자열 → 약이름 추출
    """
    if not boxes:
        return []

    line_gap = 25
    rows = {}
    for b in boxes:
        pts = b["bbox"]
        y_top = min(p[1] for p in pts)
        bucket = int(y_top / line_gap)
        rows.setdefault(bucket, []).append(b)

    lines = []
    for bucket in sorted(rows.keys()):
        row_boxes = rows[bucket]
        row_boxes = sorted(row_boxes, key=lambda bb: min(p[0] for p in bb["bbox"]))
        line = " ".join(bb["text"] for bb in row_boxes)
        lines.append(line)

    filter_words = ["전액", "규정", "계산", "필름", "코팅정", "금액", "총수납금액", 
                    "본인부담금", "보험자부담금", "비급여", "현금영수증", "영수증",
                    "사업자등록번호", "사업장소재지", "신분확인번호", "현금승인번호",
                    "발행일", "조제일자", "교부번호", "복약안내", "안내", "주의사항",
                    "본인", "다른", "사람", "같이", "처방", "조재", "약봉투", "기재",
                    "용법", "용량", "처방기간내", "복용", "하세요", "주의", "시트르산",
                    "질환", "항산", "1캡슐", "회정", "산염", "자나그병", "녹내장환", "1정", "와병",
                    "녹내장", "대장증후군", "환자", "병력", "증상", "복부", "팽만감", "알러지",
    ]
    
    form_suffix = r"(서방정|서방|정제|정|캡슐|캅셀|필름|산|액|시럽|현탁액|연고|크림|환|병|점안액|현탁액|미서)"
    pattern = rf"([가-힣A-Za-z0-9\s]+?{form_suffix}\d*)"

    names = []
    for line in lines:
        for m in re.findall(pattern, line):
            raw = m[0] if isinstance(m, tuple) else m
            raw = re.split(r"[\[\(]", raw)[0]
            raw = re.sub(r"\s+", "", raw)
            raw = re.sub(r"\d+(mg|MG|g|G|ml|ML|밀리그램|밀리그람)$", "", raw)
            should_filter = False
            for filter_word in filter_words:
                if filter_word in raw:
                    should_filter = True
                    break
            
            if should_filter:
                continue
                
            if len(raw) >= 3:
                names.append(raw)

    uniq = list(dict.fromkeys(names))

    return uniq

def remove_overlapping_drug_names(drug_names: List[str], min_overlap: int = 5) -> List[str]:
    """
    약품명 리스트에서 서로 5글자 이상 겹치는 경우
    첫 번째로 등장한 약품명만 남기고 이후 겹치는 항목은 제거.

    예:
        ["타스펜이알서방정", "이알서방정", "타스펜이알서방정서방"]
        -> ["타스펜이알서방정"]
    """
    if not drug_names or len(drug_names) <= 1:
        return drug_names

    def has_overlap(a: str, b: str, k: int) -> bool:
        """
        두 문자열 a, b 사이에 길이 k 이상 연속으로 겹치는 부분 문자열이 있는지 검사
        """
        if len(a) < k or len(b) < k:
            return False

        # 항상 a를 더 긴 문자열로 맞추기
        if len(a) < len(b):
            a, b = b, a

        # a에서 길이 k 이상의 모든 부분 문자열을 만들어 b에 포함되는지 체크
        for length in range(len(b), k - 1, -1):
            for i in range(0, len(a) - length + 1):
                sub = a[i : i + length]
                if sub in b:
                    return True
        return False

    result: List[str] = []

    for i, name in enumerate(drug_names):
        skip = False
        for kept in result:
            if has_overlap(kept, name, min_overlap):
                # 이미 result에 있는 이름과 5글자 이상 겹치면 현재 name은 버림
                logger_drugbag.info(
                    f"[약봉투 OCR] 중복 약품명 제거: '{name}' (기존 '{kept}'와 {min_overlap}글자 이상 겹침)"
                )
                skip = True
                break

        if not skip:
            result.append(name)

    return result


# -----------------------------
# 메인 함수
# -----------------------------
def extract_drugbag_split(image_path: str):
    total_start = time.time()
    logger_drugbag.info(f"[약봉투 OCR] 시작: {image_path}")

    img_original = cv2.imread(image_path)
    if img_original is None:
        error_msg = f"이미지 로드 실패: {image_path}"
        logger_drugbag.error(f"[약봉투 OCR] {error_msg}")
        logger_error.error(f"[약봉투 OCR] {error_msg}")
        raise ValueError(error_msg)

    preprocess_start = time.time()
    img_preprocessed = preprocess_for_ocr(img_original)
    logger_drugbag.info(f"[약봉투 OCR] 전처리 완료: elapsed={round(time.time() - preprocess_start, 4)}초")

    # 원본 이미지로 먼저 시도
    ocr_start = time.time()
    full_text, boxes = run_ocr_image(img_preprocessed)
    logger_drugbag.info(f"[약봉투 OCR] Vision OCR 완료: box_count={len(boxes)}, elapsed={round(time.time() - ocr_start, 4)}초")

    header_row_boxes = None
    try:
        header_row_boxes = find_table_header_row(boxes)
        logger_drugbag.info(f"[약봉투 OCR] 헤더 탐색 완료: header_count={len(header_row_boxes)}")
    except ValueError as e:
        logger_drugbag.warning(f"[약봉투 OCR] 원본 이미지에서 헤더 탐색 실패: {str(e)}, 이미지 회전 재시도")
        
        # 이미지 회전하여 재시도 (90도, 180도, 270도)
        h, w = img_original.shape[:2]
        for angle in [90, 180, 270]:
            logger_drugbag.info(f"[약봉투 OCR] 이미지 {angle}도 회전하여 OCR 재시도")
            # 이미지 회전
            center = (w // 2, h // 2)
            rotation_matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
            rotated_img = cv2.warpAffine(img_original, rotation_matrix, (w, h))
            
            # 회전된 이미지 전처리 및 OCR
            rotated_preprocessed = preprocess_for_ocr(rotated_img)
            full_text, boxes = run_ocr_image(rotated_preprocessed)
            logger_drugbag.info(f"[약봉투 OCR] {angle}도 회전 후 OCR 완료: box_count={len(boxes)}")
            
            try:
                header_row_boxes = find_table_header_row(boxes)
                logger_drugbag.info(f"[약봉투 OCR] {angle}도 회전 후 헤더 탐색 성공: header_count={len(header_row_boxes)}")
                # 회전된 이미지로 성공했으므로 전처리된 이미지도 업데이트
                img_preprocessed = rotated_preprocessed
                break
            except ValueError:
                continue
        
        # 모든 회전 시도 후에도 실패
        if header_row_boxes is None:
            error_msg = "약품명 헤더를 찾지 못했습니다. (모든 회전 시도 실패)"
            logger_drugbag.error(f"[약봉투 OCR] {error_msg}")
            logger_error.error(f"[약봉투 OCR] {error_msg}")
            raise ValueError(error_msg)

    name_header_boxes, num_header_boxes = split_header_boxes(header_row_boxes)
    all_header_pts = [p for b in header_row_boxes for p in b["bbox"]]
    y_header_bottom = max(p[1] for p in all_header_pts)
    h, w = img_preprocessed.shape[:2]
    crop_top = y_header_bottom - 30
    crop_bottom = h - 10

    # name 영역의 Y crop bottom 찾기: "보충하면 좋은 영양소" 또는 "본인의 약은" 텍스트가 있으면 그 위까지만 crop
    name_crop_bottom = crop_bottom
    stop_keywords = ["영양소", "본인의"]
    for b in boxes:
        txt = b["text"]
        if any(keyword in txt for keyword in stop_keywords):
            # 해당 텍스트의 상단 y 좌표를 찾아서 crop_bottom으로 설정
            pts = b["bbox"]
            y_top = min(p[1] for p in pts)
            if y_top > crop_top:  # 헤더 아래에 있어야 함
                name_crop_bottom = y_top - 10  # 약간의 여유 공간
                logger_drugbag.info(f"[약봉투 OCR] 중단 키워드 발견: '{txt}', name_crop_bottom={name_crop_bottom}")
                break

    name_pts = [p for b in name_header_boxes for p in b["bbox"]]
    name_x_min = min(p[0] for p in name_pts)

    num_pts = [p for b in num_header_boxes for p in b["bbox"]]
    num_x_min = min(p[0] for p in num_pts)

    name_x_min_from_header = min(p[0] for p in name_pts)
    name_x1 = max(0, name_x_min_from_header - 400)
    name_x2 = min(w, num_x_min + 450)

    # name은 찾은 키워드 위까지만 crop
    name_crop_pre = safe_crop(img_preprocessed, name_x1, crop_top, name_x2, name_crop_bottom)

    # 디버그 저장 (전처리된 crop 이미지)
    debug_dir_name = r"D:\pilly-pilly_h\FastAPI\app\inference\split_name"
    os.makedirs(debug_dir_name, exist_ok=True)
    ts = int(time.time() * 1000)
    name_path = os.path.join(debug_dir_name, f"name_{ts}.jpg")
    cv2.imwrite(name_path, name_crop_pre)
    
    crop_ocr_start = time.time()
    name_full, name_boxes = run_ocr_image(name_crop_pre)
    logger_drugbag.info(
        f"[약봉투 OCR] Name Crop OCR 완료: name_box_count={len(name_boxes)}, elapsed={round(time.time() - crop_ocr_start, 4)}초"
    )

    parse_start = time.time()
    drug_names = parse_drug_names_from_boxes(name_boxes)
    logger_drugbag.info(f"[약봉투 OCR] 약품명 파싱 완료: count={len(drug_names)}, names={drug_names}")
    drug_names = remove_overlapping_drug_names(drug_names, min_overlap=5)
    logger_drugbag.info(f"[약봉투 OCR] 5글자 이상 중복 제거 후 약품명: count={len(drug_names)}, names={drug_names}")
    logger_drugbag.info(f"[약봉투 OCR] 파싱 단계 완료: elapsed={round(time.time() - parse_start, 4)}초")

    rows = []
    for i, name in enumerate(drug_names):
        row = {
            "drugName": name,
            "onceDose": None,
            "dayDose": None,
            "days": None,
            "totalCount": None,
        }
        rows.append(row)
    
    if rows:
        print(rows[-1])

    logger_drugbag.info(f"[약봉투 OCR] 전체 완료: total_elapsed={round(time.time() - total_start, 4)}초, drug_count={len(rows)}")
    return {"rows": rows}
