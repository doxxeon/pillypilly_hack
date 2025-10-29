from app.db.models import FavoriteLog
from app.db.mongodb import favorite_collection
from app.utils.formatter import seoul_now

async def insert_favorite_log(user_id: str, folder_name: str, item_seq: str, item_name: str, image_url: str, source: str = "app"):
    log = FavoriteLog(
        user_id=user_id,
        folder_name=folder_name,
        item_seq=item_seq,
        item_name=item_name,
        image_url=image_url,
        source=source,
        timestamp=seoul_now()
    )
    await favorite_collection.insert_one(log.model_dump())