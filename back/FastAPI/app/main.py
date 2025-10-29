# app/main.py
from app.core.config import settings
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from app.api.v3.auth_router import router as auth_router
from app.api.v3.log_router import router as log_router
from app.api.v3.favorite_log_router import router as favorite_router
from app.api.v3.image_based import router as image_router
from app.api.v3.identify_feature_based import router as identify_feature_router
from app.api.v3.gemini_chatbot import router as gemini_chatbot
from app.api.v3.keyword_feature_based import router as text_feature_based
from app.api.v3.image_scrape_router import router as image_scrape
from app.api.v3.dur_router import router as dur_router
from app.api.v3.prescription_ocr_router import router as prescription_ocr_router
from app.core.errors import register_exception_handlers
from app.core.rate_limit import RateLimitMiddleware
from starlette.staticfiles import StaticFiles
import logging
import os 
  
  
#전역 로깅 설정
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
    title="PilypPilly API",
    version="2.0.0",
    description="시각장애인 대상 의약품 복용 안전 시스템",
) 
#에러 전담 핸들러
register_exception_handlers(app) 

# 1) CORS 미들웨어 설정
origins = [origin.strip() for origin in settings.allowed_origins.split(",")]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*", "X-ADMIN-KEY", "Content-Type", "Authorization"],
)

# 2) 전역 레이트리밋(실행 제한)
app.add_middleware(
    RateLimitMiddleware,
    user_limit=200, user_window=60,  # 사용자 기준 분당 100회
    ip_limit=200,  ip_window=60,      # IP 기준 분당 60회
)
 
# 어플 라우터
app.include_router(auth_router, tags=["토큰 발급"])
app.include_router(log_router, prefix="/api/v3", tags=["item_seq에 대한 공공 API 통합 조회 및 로그 저장"])
app.include_router(image_router, prefix="/api/v3", tags=["이미지 기반 알약 예측 및 요약조회"])
app.include_router(identify_feature_router, prefix="/api/v3", tags=["알약 외형 기반 식별 검색 및 요약조회"])
app.include_router(text_feature_based, tags=["키워드 통합검색 및 요약조회"])
app.include_router(dur_router, prefix="/api/v3", tags=["DUR 단일 유형 조회"])
app.include_router(gemini_chatbot, prefix="/api/v3", tags=["Gemini 챗봇"])
app.include_router(prescription_ocr_router, prefix="/api/v3", tags=["처방전 OCR 분석"])
app.include_router(favorite_router, prefix="/api/v3", tags=["즐겨찾기 저장"])
app.include_router(image_scrape, tags=["이미지 스크래핑 조회"])


#웹 라우터
#app.include_router(admin, tags=["관리자페이지"])