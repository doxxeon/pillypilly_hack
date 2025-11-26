# app/db/mongodb.py
# 연결 설정 및 클라이언트 관리

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorGridFSBucket
from app.core.config import settings
from app.db.models import SearchLog, FavoriteLog, ChatbotLog

# ──────────────────────────────────────────────
# MongoDB 연결
# ──────────────────────────────────────────────
client = AsyncIOMotorClient(settings.mongodb_uri)
db = client[settings.mongodb_db_name]  # 로그 저장
pill_db = client[settings.mongodb_db_pill_name]  # 데이터 저장

# ──────────────────────────────────────────────
# 로그 컬렉션
# ──────────────────────────────────────────────
searchlog_collection = db[settings.mongodb_collection_name]  # 기존 서비스 전체 로그
favorite_collection = db[settings.mongodb_collection_name2]  # 즐겨찾기
chatbot_collection = db[settings.mongodb_collection_name3]  # 챗봇
auth_collection = db[settings.mongodb_collection_name4]  # 사용자인증
refresh_tokens_collection = db[settings.mongodb_collection_name7]  # 리프레시 토큰 저장
model_collection = db[settings.mongodb_collection_name5]  # 모델 추론 결과
audit_collection = db[settings.mongodb_collection_name6]  # 감사 로그 전용
error_logs_collection = db[settings.mongodb_collection_name8]  # 에러처리
prescription_model_log_collection = db[settings.mongodb_collection_name9]  # 처방전 OCR 로그
prescriptions_sessions_collection = db["prescriptions_sessions"]
pill_images_collection = db["pill_images"]

# ──────────────────────────────────────────────
# 데이터 컬렉션
# ──────────────────────────────────────────────
itentify_all_collection = pill_db[settings.mongodb_identify_name]  # 식별검색 전체 데이터
permit_info_all_collection = pill_db[settings.mongodb_permit_name]  # 허가목록 데이터
permit_detail_collection = pill_db[settings.mongodb_permit_name2]  # 허가상세정보 데이터
edrug_collection = pill_db[settings.mongodb_edrug_name]  # e약은요 데이터
dur_comb_collection = pill_db[settings.mongodb_dur_combination]  # DUR 병용금기
dur_preg_collection = pill_db[settings.mongodb_dur_pregnant]  # DUR 임부금기
dur_age_collection = pill_db[settings.mongodb_dur_age]  # DUR 연령금기
dur_term_collection = pill_db[settings.mongodb_dur_term]  # DUR 기간금기
dur_elderly_collection = pill_db[settings.mongodb_dur_elderly]  # DUR 노인주의
dur_dosage_collection = pill_db[settings.mongodb_dur_dosage]  # DUR 용량주의

# ──────────────────────────────────────────────
# GridFS 버킷 + 메타 컬렉션
# ──────────────────────────────────────────────
gridfs_bucket = AsyncIOMotorGridFSBucket(
    pill_db,
    bucket_name=settings.gridfs_bucket,
)
image_meta_collection = pill_db[settings.meta_coll]

# ──────────────────────────────────────────────
# 초기 인덱스 준비
# ──────────────────────────────────────────────
async def init_image_indexes():
    await image_meta_collection.create_index("itemSeq", unique=True)
    await image_meta_collection.create_index("updatedAt")




