from app.db.models import SearchLog
from app.db.mongodb import searchlog_collection

async def insert_search_log(user_id: str, query: dict, results: dict):
    log = SearchLog(
        user_id=user_id, 
        query=query, 
        results=results)
    await searchlog_collection.insert_one(log.model_dump())
