# 환경변수 불러오기 및 설정
# 📁 app/core/config.py
from pydantic_settings import BaseSettings 
from pydantic import Field, AliasChoices
from dotenv import load_dotenv
import os

load_dotenv()

class Settings(BaseSettings):
    service_key: str
    mongodb_user: str
    mongodb_pass: str
    mongodb_host: str
    mongodb_port: int
    mongodb_uri: str
    mongodb_db_name: str
    mongodb_db_pill_name: str
    mongodb_collection_name: str
    mongodb_collection_name2: str
    mongodb_collection_name3: str
    mongodb_collection_name4: str
    mongodb_collection_name5: str
    mongodb_collection_name6: str
    mongodb_collection_name7: str
    mongodb_collection_name8: str = 'error_logs'
    mongodb_identify_name: str
    mongodb_permit_name: str
    mongodb_permit_name2: str
    mongodb_edrug_name: str
    mongodb_dur_combination: str
    mongodb_dur_pregnant: str
    mongodb_dur_age: str
    mongodb_dur_term: str
    mongodb_dur_elderly: str
    mongodb_dur_dosage: str

    gemini_key_path: str
    google_api_key: str 
    ocr_key_path: str = os.getenv("OCR_KEY_PATH")
    google_vision_key_path: str = os.getenv("GOOGLE_VISION_KEY_PATH")
    allowed_origins: str
    allowed_origins_tts: str
    jwt_secret_key: str
    jwt_refresh_secret_key: str
    jwt_algorithm: str
    jwt_exp_minutes: int
    jwt_refresh_exp_days: int 
    jwt_issuer: str
    admin_key: str

    gridfs_bucket: str = os.getenv("GRIDFS_BUCKET", "pill_image_files")
    meta_coll: str = os.getenv("META_COLL", "pill_images")

    class Config:
        env_file = ".env"  # .env 파일에서 자동으로 로드

# 인스턴스 생성
settings = Settings()