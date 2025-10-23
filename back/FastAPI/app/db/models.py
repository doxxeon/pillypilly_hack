# 저장할 로그 데이터 모델
#FastAPI\app\db\models.py
from pydantic import BaseModel, Field
from typing import List, Dict, Optional, Any
from datetime import datetime
from pytz import timezone

#한국 서울시간 적용
def seoul_now():
    return datetime.now(timezone('Asia/Seoul'))

# 검색 기록 로그
class SearchLog(BaseModel):
    user_id: str
    query: Dict[str, str]             # 예: {"source": "permit", "item_seq": "1234"}
    results: Dict[str, Any]          # 예: {"permit": {...}, "dur": {...}}
    timestamp: datetime = Field(default_factory=seoul_now)

# 즐겨찾기 로그
class FavoriteLog(BaseModel):
    user_id: Optional[str] = None                    # 로그인 X 사용자 대응 가능성 고려
    folder_name: str
    item_seq: str                                     # 알약 고유 코드
    item_name: str
    image_url: str                                    # 알약 이름
    source: Optional[str] = "favorite_serch" 
    timestamp: datetime = Field(default_factory=seoul_now)
                      

# chat-bot 로그
class ChatbotLog(BaseModel):
    user_id: str
    drug_info: Dict[str, Any]
    drug_summary: str
    user_input: str 
    answer: str
    source: Optional[str] = "chatbot"
    timestamp: datetime = Field(default_factory=seoul_now)