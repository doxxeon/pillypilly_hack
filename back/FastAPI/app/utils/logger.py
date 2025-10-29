# 로그 저장
# app/utils/logger.py
import logging
from logging.handlers import RotatingFileHandler

# ─────────────────────────────
# 로거 설정
# ─────────────────────────────
# 전역 로거
logger = logging.getLogger("uvicorn")
logger.setLevel(logging.DEBUG)

if not logger.handlers:
    handler = logging.StreamHandler()
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s - %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)

# 챗봇
logger_gemini = logging.getLogger("gemini_logger")
logger_gemini.setLevel(logging.INFO)

if not logger_gemini.hasHandlers():
    file_handler = logging.FileHandler("logs/gemini_chat.log", encoding='utf-8')  # 💡 다른 파일명
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)
    logger_gemini.addHandler(file_handler)


# 약제 정보
logger_drugs = logging.getLogger("drugs_logger")
logger_drugs.setLevel(logging.INFO)

if not logger_drugs.hasHandlers():
    file_handler = logging.FileHandler("logs/drugs.log", encoding="utf-8")
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)
    logger_drugs.addHandler(file_handler)


# 즐겨찾기
logger_favorite = logging.getLogger("favorite_logger")
logger_favorite.setLevel(logging.INFO)
if not logger_favorite.hasHandlers():
    file_handler = logging.FileHandler("logs/favorite.log", encoding="utf-8")
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)
    logger_favorite.addHandler(file_handler)


#인증
logger_auth = logging.getLogger("auth_logger")
logger_auth.setLevel(logging.INFO)
if not logger_auth.hasHandlers():
    file_handler = logging.FileHandler("logs/auth.log", encoding="utf-8")
    formatter = logging.Formatter("[%(asctime)s] %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)
    logger_auth.addHandler(file_handler)


#모델 알고리즘
logger_model = logging.getLogger("model_logger")
logger_model.setLevel(logging.INFO)
if not logger_model.hasHandlers():
    file_handler = logging.FileHandler("logs/model_ai.log", encoding="utf-8")
    formatter = logging.Formatter("%(asctime)s | %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)
    logger_model.addHandler(file_handler)

# 에러
logger_error = logging.getLogger("error_logger")
logger_error.setLevel(logging.INFO)
if not logger_error.hasHandlers():
    fh = RotatingFileHandler("logs/errors.log", maxBytes=10_000_000, backupCount=5, encoding="utf-8")
    fmt = logging.Formatter("[%(asctime)s] %(levelname)s - %(message)s")
    fh.setFormatter(fmt)
    logger_error.addHandler(fh)