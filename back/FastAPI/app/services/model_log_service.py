#이미지 기반 예측 결과 + 이미지 자체를 GridFS로 MongoDB에 저장
# 📄 app/services/image_log_service.py
# =====================================
# 1. GridFS 저장 함수 작성
# =====================================

from motor.motor_asyncio import AsyncIOMotorGridFSBucket
from bson import ObjectId
from datetime import datetime
from app.db.mongodb import db  # db: AsyncIOMotorDatabase
from app.db.mongodb import model_collection
from fastapi import HTTPException  

#버킷 객체 생성
fs_bucket = AsyncIOMotorGridFSBucket(db)

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
        upload_stream = fs_bucket.open_upload_stream(filename) #파일 업로드 스트림 열기
        await upload_stream.write(image_bytes) # 이미지 바이너리 저장
        await upload_stream.close()  #이미지 업로드
        image_file_id = upload_stream._id #이미지 filf_id 가져오기

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
        # 예외처리
        raise HTTPException(status_code=500, detail=f"모델 로그 저장 실패: {e}")