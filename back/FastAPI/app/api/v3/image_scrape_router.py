# app/api/v2/image_scrape_router.py
from __future__ import annotations
from typing import AsyncGenerator, Optional
from fastapi import APIRouter, HTTPException, Query, Depends, Request
from starlette.responses import StreamingResponse
import anyio
import httpx

from app.services.image_scrape_service import get_or_fetch_image
from app.core.dependencies import get_current_user
from app.services.token_service import verify_access_token

router = APIRouter()


async def _iter_gridfs(stream) -> AsyncGenerator[bytes, None]:
    """GridFS 파일을 chunk 단위로 스트리밍."""
    read = 0
    length = getattr(stream, "length", None)
    while True:
        chunk = await stream.readchunk()
        if not chunk:
            break
        read += len(chunk)
        yield chunk
        if length is not None and read >= length:
            break


@router.get("/image-scrape", summary="이미지 스크래핑")
async def get_image(
    request: Request,
    item_seq: str,
    refresh: bool = Query(False, description="true면 캐시 무시하고 재스크랩 시도"),
    user_id: str = Depends(get_current_user)
):
    """
    프록시 스트리밍:
    - GridFS에 저장된 이미지를 스트리밍으로 내려줌
    - 캐시 만료 또는 refresh=true면 스크래핑 → 저장 → 스트리밍
    """
    try:
        # 전체 요청 상한 20초
        with anyio.move_on_after(60.0) as scope:
            stream, ctype, meta = await get_or_fetch_image(item_seq, force_refresh=refresh)
        if scope.cancel_called:
            raise HTTPException(status_code=504, detail="upstream timeout")
    except (httpx.ReadTimeout, httpx.ConnectTimeout):
        raise HTTPException(status_code=504, detail="upstream timeout")

    if not stream or not ctype:
        raise HTTPException(status_code=404, detail="image not found")

    headers = {
        "Cache-Control": "public, max-age=86400",  # 프론트 캐싱(하루)
        "X-Image-From": "cache" if not refresh else "scraped",
        "X-Image-Source": meta.get("source", ""),
    }
    return StreamingResponse(_iter_gridfs(stream), media_type=ctype, headers=headers)

