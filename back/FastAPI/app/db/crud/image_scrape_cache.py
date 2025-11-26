# app/db/crud/image_store.py
from __future__ import annotations

import io
import hashlib
from datetime import datetime, timezone
from typing import Optional, Tuple, Dict, Any

from bson import ObjectId
from app.db.mongodb import gridfs_bucket, image_meta_collection


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _sha256(data: bytes) -> str:
    h = hashlib.sha256()
    h.update(data)
    return h.hexdigest()


async def get_meta(item_seq: str) -> Optional[Dict[str, Any]]:
    """itemSeq로 메타 문서 조회."""
    return await image_meta_collection.find_one({"itemSeq": item_seq})


async def open_stream_by_file_id(file_id: ObjectId) -> Any:
    """GridFS 파일 스트림 열기."""
    return await gridfs_bucket.open_download_stream(file_id)


async def open_stream_by_item_seq(item_seq: str) -> Optional[Tuple[Any, Dict[str, Any]]]:
    """메타 → GridFS 스트림 열기 (없으면 None)."""
    meta = await get_meta(item_seq)
    if not meta or not meta.get("fileId"):
        return None
    stream = await open_stream_by_file_id(meta["fileId"])
    return stream, meta


async def save_bytes(
    item_seq: str,
    data: bytes,
    content_type: str,
    source: str,
    filename: Optional[str] = None,
) -> Dict[str, Any]:
    """
    이미지를 GridFS에 저장하고 메타 upsert.
    기존 파일이 있으면 안전하게 교체(구 파일 삭제).
    """
    sha = _sha256(data)
    length = len(data)
    filename = filename or f"{item_seq}"

    # 기존 메타 조회
    prev = await get_meta(item_seq)
    prev_file_id = prev.get("fileId") if prev else None

    # 업로드 (중요: content_type 인자 X, 바이트는 BytesIO로!)
    file_id: ObjectId = await gridfs_bucket.upload_from_stream(
        filename,
        io.BytesIO(data),   # ← bytes를 스트림으로 감싸서 전달
        metadata={
            "itemSeq": item_seq,
            "contentType": content_type,  # ← MIME은 metadata에
            "length": length,
            "sha256": sha,
            "source": source,
            "uploadedAt": _utcnow(),
        },
    )

    # 메타 upsert
    meta = {
        "itemSeq": item_seq,
        "fileId": file_id,
        "contentType": content_type,
        "length": length,
        "sha256": sha,
        "source": source,
        "updatedAt": _utcnow(),
    }
    await image_meta_collection.update_one(
        {"itemSeq": item_seq},
        {"$set": meta},
        upsert=True,
    )

    # 이전 파일 정리
    if prev_file_id and prev_file_id != file_id:
        try:
            await gridfs_bucket.delete(prev_file_id)
        except Exception:
            pass

    return meta
