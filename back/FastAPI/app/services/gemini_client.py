# 생성형 챗봇
# FastAPI\app\services\gemini_client.py
# FastAPI\app\services\gemini_client.py
import time
import httpx
import asyncio
from app.core.config import settings
from google.api_core.exceptions import GoogleAPIError
from typing import Dict, Any
from app.utils.logger import logger_gemini
from app.core.errors import ExternalApiError

# ──────────────────────────────────────────────
# Gemini 설정
# ──────────────────────────────────────────────
import google.generativeai as genai
genai.configure(api_key=settings.google_api_key)
model = genai.GenerativeModel("models/gemini-2.5-flash")

# httpx 설정
HTTP_TIMEOUT = httpx.Timeout(connect=3.0, read=10.0, write=5.0, pool=5.0)
HTTP_LIMITS = httpx.Limits(max_connections=20, max_keepalive_connections=10, keepalive_expiry=30.0)

# ──────────────────────────────────────────────
# 질문 처리 함수: 
# prompt: 약 정보(통합)+ 사용자 입력 값 
# ──────────────────────────────────────────────
async def ask_gemini(drug_summary: str, user_input: str) -> str:
    prompt = f"""다음은 의약품에 대한 상세 정보입니다. 이 정보를 바탕으로 아래 질문에 대해 **사용자가 이해하기 쉬운 자연스러운 5문장이내로 요약**해 주세요.
    약물의 일반적인 부작용이나 안내 사항을 중심으로, 응답해주세요. 정보 요약은 사용자에게 핵심만 전달하되, 필요 시 예시를 들어 설명해도 좋습니다. 질문이 의약품과 무관한 경우에는 정중히 안내해 주세요.

약 정보:
{drug_summary}

질문:
{user_input}
"""
    try:
        start_time = time.time()
        
        # 비동기 httpx로 Gemini API 호출
        async with httpx.AsyncClient(timeout=HTTP_TIMEOUT, limits=HTTP_LIMITS) as client:
            # Gemini API는 REST API가 아니므로 기존 방식 유지하되 비동기 컨텍스트에서 실행
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, model.generate_content, prompt)
            
        elapsed = round(time.time() - start_time, 4)
        logger_gemini.info(f"[Gemini] 응답 시간: {elapsed}초")
        return response.text.strip()
        
    except GoogleAPIError as api_err:
        logger_gemini.error(f"[Gemini API 오류]: {api_err.message}")
        # 예외처리
        raise ExternalApiError("Gemini API error", status_code=502, context={"msg": api_err.message})
    except Exception as e:
        logger_gemini.error(f"[예외 발생]: {str(e)}")
        # 예외처리
        raise ExternalApiError("Gemini client failure", status_code=502, context={"msg": str(e)})

# ──────────────────────────────────────────────
# drug_info 요청 처리 함수: 
# prompt: 약 정보(통합)+ 사용자 입력 값 
# ──────────────────────────────────────────────

def parse_drug_info_json(drug_info: Dict[str, Any]) -> str:
    try:
        # STEP 1. results에서 첫 번째 itemSeq 블록 추출
        if "results" in drug_info and isinstance(drug_info["results"], dict):
            results_values = list(drug_info["results"].values())
            if not results_values:
                return "[파싱 오류] results 내부에 약 정보가 없습니다."
            drug_info = results_values[0]
        else:
            return "[파싱 오류] results 키가 없거나 형식이 잘못됨"

        # STEP 2. 주요 블록 접근
        permit_detail = drug_info.get("permit", {}).get("permitDetail", {})
        dur_info = drug_info.get("dur", {})

        # STEP 3. 기본정보 파싱
        name = permit_detail.get("ITEM_NAME", "")
        eng_name = permit_detail.get("ITEM_ENG_NAME", "")
        manufacturer = permit_detail.get("ENTP_NAME", "")
        manufacturer_eng = permit_detail.get("ENTP_ENG_NAME", "")
        valid_term = permit_detail.get("VALID_TERM", "")
        storage_method = permit_detail.get("STORAGE_METHOD", "")
        ingredient = permit_detail.get("MAIN_ITEM_INGR", "")
        ingredient_eng = permit_detail.get("MAIN_INGR_ENG", "")
        additive = permit_detail.get("ADDITIVE_NAME", "")
        efficacy = permit_detail.get("EE_TEXT", "")
        usage = permit_detail.get("UD_TEXT", "")
        precautions = permit_detail.get("NB_TEXT", "")

        # STEP 4. DUR 정보 파싱
        dur_sections = []
        for dur_key, entries in dur_info.items():
            if not isinstance(entries, list) or not entries:
                continue
            section_title = dur_key
            summaries = []
            for entry in entries:
                item_name = entry.get("itemName") or entry.get("mixtureItemName", "")
                reason = entry.get("prohibitContent") or entry.get("prohibitReason", "")
                if item_name or reason:
                    summaries.append(f"{item_name} - {reason}".strip(" -"))
            if summaries:
                dur_sections.append(f"{section_title}: {', '.join(summaries)}")

        # STEP 5. 최종 요약 구성
        summary_lines = list(filter(None, [
            f"제품명: {name}",
            f"영문명: {eng_name}",
            f"제조사: {manufacturer} ({manufacturer_eng})",
            f"유효기간: {valid_term}",
            f"보관방법: {storage_method}",
            f"주성분: {ingredient} ({ingredient_eng})",
            f"첨가제: {additive}",
            f"효능효과: {efficacy}",
            f"용법용량: {usage}",
            f"사용상 주의사항: {precautions}",
        ])) + dur_sections

        return "\n".join(summary_lines).strip()

    except Exception as e:
        return f"[파싱 오류] {str(e)}"
