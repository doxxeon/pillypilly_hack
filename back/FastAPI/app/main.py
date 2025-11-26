# app/main.py
from app.core.config import settings
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.v3.auth_router import router as auth_router
from app.api.v3.log_router import router as log_router
from app.api.v3.image_based import router as image_router
from app.api.v3.identify_feature_based import router as identify_feature_router
from app.api.v3.keyword_feature_based import router as text_feature_based
from app.api.v3.image_scrape_router import router as image_scrape
from app.api.v3.dur_router import router as dur_router
from app.api.v3.prescription_ocr_router2 import router as prescription_ocr_router
from app.api.v3.drug_bag_router_split import router as drugbag_split_router
from app.api.v3.expiry_date_router import router as expiry_date_router
from app.core.errors import register_exception_handlers
from app.core.rate_limit import RateLimitMiddleware
import logging
import os 


# 전역 로깅 설정
os.makedirs("logs", exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler("logs/inference.log", encoding="utf-8"),
        logging.StreamHandler()
    ]
) 
  
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
  
app = FastAPI(
    title="Pilly Pilly API",
    version="3.0.0",
    description="알약 식별 및 정보 조회 API",
) 

# 에러 핸들러 등록
register_exception_handlers(app) 

# CORS 미들웨어 설정
origins = [origin.strip() for origin in settings.allowed_origins.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*", "X-ADMIN-KEY", "Content-Type", "Authorization"],
)

# 전역 레이트리밋 미들웨어
app.add_middleware(
    RateLimitMiddleware,
    user_limit=200, user_window=60,  # 사용자 기준 분당 200회
    ip_limit=100,  ip_window=60,      # IP 기준 분당 100회
)
 
# 라우터 등록
app.include_router(auth_router, tags=["토큰 발급"])
app.include_router(log_router, prefix="/api/v3", tags=["item_seq에 대한 공공 API 통합 조회 및 로그 저장"])
app.include_router(identify_feature_router, prefix="/api/v3", tags=["알약 외형 기반 식별 검색 및 요약조회"])
app.include_router(text_feature_based, tags=["키워드 통합검색 및 요약조회"])
app.include_router(dur_router, prefix="/api/v3", tags=["DUR 단일 유형 조회"])
app.include_router(image_router, prefix="/api/v3", tags=["이미지 기반 알약 예측 및 요약조회"])
app.include_router(prescription_ocr_router, prefix="/api/v3", tags=["처방전 OCR 분석"])
app.include_router(drugbag_split_router, prefix="/api/v3", tags=["약봉투 OCR 분할 분석"])
app.include_router(expiry_date_router, prefix="/api/v3", tags=["유통기한 확인"])
app.include_router(image_scrape, tags=["이미지 스크래핑 조회"])