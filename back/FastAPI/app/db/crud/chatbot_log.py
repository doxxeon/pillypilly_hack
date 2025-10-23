from typing import Dict, Any
from app.db.models import ChatbotLog
from app.db.mongodb import chatbot_collection
from app.utils.formatter import seoul_now

async def insert_chatbot_log(user_id: str, drug_info: Dict[str, Any], drug_summary: str, user_input: str, answer: str, source: str = "chatbot"):
    log = ChatbotLog(
        user_id=user_id,
        drug_info=drug_info,
        drug_summary=drug_summary,
        user_input=user_input,
        answer=answer,
        source=source,
        timestamp=seoul_now()
    )
    await chatbot_collection.insert_one(log.model_dump())