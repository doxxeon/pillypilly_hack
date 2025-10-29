from fastapi import APIRouter, Request, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional, List
from app.services.log_service import log_favorite_to_mongo
from app.core.dependencies import get_current_user
from app.db.mongodb import favorite_collection
from app.utils.logger import logger_favorite
from app.db.crud.user_auth import upsert_anonymous_user


router = APIRouter()

# ──────────────────────────────────────────────
# 즐겨찾기 요청 바디용 스키마
# ──────────────────────────────────────────────
class FavoriteRequest(BaseModel):
    folder_name: str
    item_seq: str
    item_name: str
    image_url: Optional[str] = None
    source: Optional[str] = "app"

# ──────────────────────────────────────────────
# 즐겨찾기 로그 저장 엔드포인트
# ──────────────────────────────────────────────
@router.post("/favorite")
async def save_favorite_log_api(
    request: Request, 
    payload: FavoriteRequest,
    user_id: str = Depends(get_current_user)
):
    await upsert_anonymous_user(user_id, request)
    try:
        await log_favorite_to_mongo(
            request=request,
            folder_name=payload.folder_name,
            item_seq=payload.item_seq,
            item_name=payload.item_name,
            image_url=payload.image_url,
            source=payload.source,
            user_id=user_id
        )

        logger_favorite.info(
            f"[즐겨찾기 저장] | USER_ID={user_id} | item_seq={payload.item_seq} | folder={payload.folder_name}"
        )

        return {
            "message": "즐겨찾기 로그 저장 완료",
            "folderName": payload.folder_name,
            "itemSeq": payload.item_seq,
            "itemName": payload.item_name,
            "imageUrl": payload.image_url,
            "source": payload.source
        }

    except Exception as e:
        logger_favorite.warning(
            f"즐겨찾기 저장 실패 | USER_ID={user_id} | item_seq={payload.item_seq} | {str(e)}"
        )
        raise HTTPException(status_code=500, detail="즐겨찾기 저장 중 오류 발생")

# ──────────────────────────────────────────────
# 단일 약물 즐겨찾기 삭제용 요청 바디
# ──────────────────────────────────────────────
class FavoriteDeleteRequest(BaseModel):
    folder_name: str
    item_seq: str

@router.delete("/favorite")
async def delete_favorite_log_api(
    request: Request,
    payload: FavoriteDeleteRequest,
    user_id: str = Depends(get_current_user)
):
    await upsert_anonymous_user(user_id, request)
    delete_result = await favorite_collection.delete_one({
        "user_id": user_id,
        "folder_name": payload.folder_name,
        "item_seq": payload.item_seq
    })

    if delete_result.deleted_count == 0:
        logger_favorite.warning(f"즐겨찾기 삭제 실패 | USER_ID={user_id} | item_seq={payload.item_seq} | 존재하지 않음")
        raise HTTPException(status_code=404, detail="해당 즐겨찾기 항목이 존재하지 않음")

    logger_favorite.info(f"[즐겨찾기 약물 삭제] | USER_ID={user_id} | item_seq={payload.item_seq}")
    return {
        "message": "즐겨찾기 로그 삭제 완료",
        "deleted_item_seq": payload.item_seq
    }

# ──────────────────────────────────────────────
# 폴더 전체 삭제 요청 바디
# ──────────────────────────────────────────────
class FolderDeleteRequest(BaseModel):
    folder_name: str

@router.post("/favorite/folder/delete")
async def delete_favorite_folder_api(
    request: Request,
    payload: FolderDeleteRequest,
    user_id: str = Depends(get_current_user)
):
    await upsert_anonymous_user(user_id, request)
    delete_result = await favorite_collection.delete_many({
        "user_id": user_id,
        "folder_name": payload.folder_name
    })

    if delete_result.deleted_count == 0:
        logger_favorite.warning(f"즐겨찾기 폴더 삭제 실패 | USER_ID={user_id} | folder_name={payload.folder_name} | 항목 없음")
        raise HTTPException(status_code=404, detail="해당 폴더 또는 항목이 존재하지 않음")

    logger_favorite.info(f"[즐겨찾기 폴더 삭제] | USER_ID={user_id} | folder_name={payload.folder_name} | 삭제된 항목 수={delete_result.deleted_count}")
    return {
        "message": "폴더 및 해당 즐겨찾기 항목 전체 삭제 완료",
        "deleted_folder": payload.folder_name,
        "deleted_count": delete_result.deleted_count
    }