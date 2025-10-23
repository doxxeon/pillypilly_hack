#FastAPI\app\api\v2\gemini_chatbot.py
import time
from fastapi import APIRouter, Request, HTTPException, Depends
from typing import Dict, Any
from pydantic import BaseModel
from app.services.gemini_client import parse_drug_info_json, ask_gemini
from app.services.log_service import log_chatbot_to_mongo
from app.core.dependencies import get_current_user 
from app.db.crud.user_auth import upsert_anonymous_user
from app.core.rate_limit import rate_limit_user


router = APIRouter()

# ──────────────────────────────────────────────
# 요청 모델
# ──────────────────────────────────────────────

class PromptRequest(BaseModel):
    drug_info: Dict[str, Any]
    user_input: str

# ──────────────────────────────────────────────
# Gemini 추천 챗봇 엔드포인트
# ──────────────────────────────────────────────
@router.post("/chatbot", summary="약정보+사용자 질문",
             dependencies=[Depends(rate_limit_user("chat", limit=5, window_s=60))],  # 분당 5회/유저
             )
async def get_chat_recommendation(
    request: Request, 
    payload: PromptRequest, 
    user_id: str = Depends(get_current_user)
    ) -> Dict:
    start_time = time.time()
    await upsert_anonymous_user(user_id, request)
    # 파싱
    drug_summary = parse_drug_info_json(payload.drug_info)
    if drug_summary.startswith("[파싱 오류]"):
        # 예외처리
        raise HTTPException(status_code=400, detail=drug_summary)

    # Gemini 응답 - await 추가
    answer = await ask_gemini(drug_summary, payload.user_input)

    # 로그 저장
    await log_chatbot_to_mongo(
        request=request,
        drug_info=payload.drug_info,
        drug_summary=drug_summary,
        user_input=payload.user_input,
        answer=answer,
        user_id = user_id
    )

    elapsed = round(time.time() - start_time, 4)
    print(f"🤖 [API /챗봇-사용자 질문] 처리 시간: {elapsed}초")

    return {
        "answer": answer
    }
