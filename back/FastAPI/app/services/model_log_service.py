# app/services/model_log_service.py
# 이미지 기반 예측 결과를 GridFS로 MongoDB에 저장

from motor.motor_asyncio import AsyncIOMotorGridFSBucket
from bson import ObjectId
from datetime import datetime
from app.db.mongodb import db
from app.db.mongodb import model_collection
from fastapi import HTTPException

# GridFS 버킷 객체 생성
fs_bucket = AsyncIOMotorGridFSBucket(db)

# ──────────────────────────────────────────────
# 모델 예측 결과 저장
# ──────────────────────────────────────────────
async def log_model_result_to_mongo(
    user_id: str,
    image_bytes: bytes,
    filename: str,
    top_k: list,
    summary: list,
    ocr_keywords: list
):
    now = datetime.now()

    try:
        upload_stream = fs_bucket.open_upload_stream(filename)
        await upload_stream.write(image_bytes)
        await upload_stream.close()
        image_file_id = upload_stream._id

        doc = {
            "user_id": user_id,
            "image_file_id": image_file_id,
            "filename": filename,
            "top_k": top_k,
            "summary": summary,
            "ocr_keywords": ocr_keywords,
            "timestamp": now
        }
        await model_collection.insert_one(doc)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"모델 로그 저장 실패: {e}")