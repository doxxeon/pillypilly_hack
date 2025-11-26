# app/api/v3/expiry_date_router.py
from __future__ import annotations

import os
import re
import time
from pathlib import Path
from typing import Optional
from datetime import datetime

from fastapi import (
    APIRouter,
    UploadFile,
    File,
    HTTPException,
    Request,
    Depends,
)

from app.inference.expiry_date_extractor import get_expiry_date
from app.core.dependencies import get_current_user
from app.db.crud.user_auth import upsert_anonymous_user
from app.core.errors import ExternalApiError

router = APIRouter()

BASE_DIR = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = BASE_DIR / "inference" / "expiry_date_uploaded"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


def parse_date(date_str: str) -> Optional[datetime]:
    """
    날짜 문자열을 datetime으로 변환
    지원 형식: YYYY.MM.DD, YYYY/MM/DD, YYYY-MM-DD
    """
    if not date_str:
        return None
    
    normalized = date_str.replace(".", "-").replace("/", "-")
    
    patterns = [
        r"(\d{4})-(\d{2})-(\d{2})",
        r"(\d{4})(\d{2})(\d{2})",  # YYYYMMDD 형식도 지원
    ]
    
    for pattern in patterns:
        match = re.match(pattern, normalized)
        if match:
            try:
                year = int(match.group(1))
                month = int(match.group(2))
                day = int(match.group(3))
                return datetime(year, month, day)
            except ValueError:
                continue
    
    return None


@router.post("/expiry-date-check")
async def check_expiry_date(
    request: Request,
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user),
):
    """
    [기능]
    약상자 이미지를 업로드하면 유통기한을 추출하고,
    현재 시간과 비교하여 유통기한이 지났는지 확인합니다.

    [요청 파라미터]
    - file (필수, form-data, 파일):
      약상자 이미지 파일(JPG, PNG 등)

    [응답 데이터]
    - expiry_date (str | null):
      추출된 유통기한 날짜 (YYYY-MM-DD 형식) 또는 null

    - is_expired (bool):
      유통기한이 지났는지 여부 (날짜가 추출된 경우에만 의미 있음)

    - message (str):
      사용자에게 표시할 메시지
        - 유통기한이 정상적으로 추출된 경우: "유통기한이 {날짜}까지 남았습니다." 또는 "유통기한이 {날짜}에 지났습니다."
        - 유통기한을 찾을 수 없는 경우: "유통기한 정보를 찾을 수 없습니다. 다른 면을 촬영해주세요."

    - status (str):
      "SUCCESS" | "NOT_FOUND" | "ERROR"
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

        # 유통기한 추출
        try:
            expiry_result = get_expiry_date(str(save_path))
        except Exception as e:
            raise ExternalApiError(
                f"유통기한 추출 중 오류: {str(e)}",
                code="EXPIRY_EXTRACTION_ERROR",
                context={"error_type": type(e).__name__},
            )

        now = datetime.now()
        expiry_date = None
        is_expired = False
        message = ""
        status = "SUCCESS"

        # 에러 메시지 확인 (유통기한을 찾을 수 없는 경우)
        if "❌" in expiry_result or "찾지 못했습니다" in expiry_result or "촬영해주세요" in expiry_result:
            status = "NOT_FOUND"
            message = expiry_result
            return {
                "expiry_date": None,
                "is_expired": False,
                "message": message,
                "status": status,
                "processing_time_sec": round(time.time() - start_time, 3),
            }

        # 날짜 파싱
        expiry_date_obj = parse_date(expiry_result)
        
        if expiry_date_obj is None:
            # 날짜 형식이 맞지 않는 경우
            status = "NOT_FOUND"
            message = "유통기한 날짜 형식을 인식할 수 없습니다. 다른 면을 촬영해주세요."
            return {
                "expiry_date": None,
                "is_expired": False,
                "message": message,
                "status": status,
                "processing_time_sec": round(time.time() - start_time, 3),
            }

        expiry_date = expiry_date_obj.strftime("%Y-%m-%d")
        
        # 유통기한 비교
        is_expired = expiry_date_obj < now
        
        if is_expired:
            message = f"유통기한이 {expiry_date}에 지났습니다. 복용하지 마세요."
        else:
            message = f"유통기한이 {expiry_date}까지 남았습니다. 복용 가능합니다."

        return {
            "expiry_date": expiry_date,
            "is_expired": is_expired,
            "message": message,
            "status": status,
            "processing_time_sec": round(time.time() - start_time, 3),
        }

    except (ExternalApiError, HTTPException):
        raise
    except Exception as e:
        raise ExternalApiError(
            f"예상치 못한 오류: {str(e)}",
            code="EXPIRY_CHECK_ERROR",
            context={"error_type": type(e).__name__},
        )

