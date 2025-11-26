# app/services/image_scrape_service.py
from __future__ import annotations

import base64
import re
from datetime import datetime, timezone, timedelta
from typing import Optional, Tuple, Dict, Any
from urllib.parse import urljoin
import asyncio

import httpx
from bs4 import BeautifulSoup
from fastapi import HTTPException

from app.db.crud.image_scrape_cache import get_meta, open_stream_by_item_seq, save_bytes

# ──────────────────────────────────────────────
# 기본 설정
# ──────────────────────────────────────────────
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PillResolverBot/1.0"
BASE_MFDS = "https://nedrug.mfds.go.kr"

DEFAULT_HEADERS: Dict[str, str] = {
    "User-Agent": UA,
    "Referer": BASE_MFDS,
    "Accept-Language": "ko-KR,ko;q=0.9",
}

# httpx 기본 타임아웃/커넥션 제한
DEFAULT_TIMEOUT = httpx.Timeout(connect=3.0, read=5.0, write=5.0, pool=5.0)
DEFAULT_LIMITS = httpx.Limits(max_connections=20, max_keepalive_connections=10, keepalive_expiry=30.0)

DATA_URI_RE = re.compile(
    r'data:image/(png|jpe?g|gif|webp);base64,([A-Za-z0-9+/=\s]+)',
    re.I | re.DOTALL,
)

# 캐시 TTL (24시간)
REFRESH_TTL = timedelta(hours=24)


def _utcnow() -> datetime:
    """현재 UTC 시간을 timezone-aware로 반환."""
    return datetime.now(timezone.utc)


def _is_fresh(updated_at: Optional[datetime]) -> bool:
    """메타데이터가 최신인지 확인."""
    if not updated_at:
        return False

    # updated_at이 timezone-naive인 경우 UTC로 가정하고 timezone-aware로 변환
    if updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)

    return (_utcnow() - updated_at) < REFRESH_TTL


def _set_reasonable_encoding(resp: httpx.Response, fallback: str = "utf-8") -> None:
    """응답에서 charset 추론"""
    if resp.encoding:
        return
    ctype = resp.headers.get("Content-Type", "")
    if "euc-kr" in ctype.lower() or "cp949" in ctype.lower():
        resp.encoding = "euc-kr"
        return
    head = resp.content[:2048].decode("utf-8", errors="ignore")
    m = re.search(r'charset=([\w\-]+)', head, re.I)
    resp.encoding = m.group(1) if m else fallback


async def _get_with_retry(
    client: httpx.AsyncClient,
    url: str,
    params: Optional[Dict] = None,
    tries: int = 2,
) -> Optional[httpx.Response]:
    """
    재시도 포함 GET. ReadTimeout/ConnectTimeout일 때만 재시도.
    """
    last_exc = None
    for i in range(tries):
        try:
            return await client.get(url, params=params)
        except (httpx.ReadTimeout, httpx.ConnectTimeout) as e:
            last_exc = e
            await asyncio.sleep(0.3 * (i + 1))
    return None


async def _fetch_image_bytes(client: httpx.AsyncClient, url: str) -> Optional[Tuple[bytes, str]]:
    """이미지 URL을 받아 바이트+콘텐츠타입 가져오기."""
    r = await _get_with_retry(client, url)
    if r is None or r.status_code != 200:
        return None
    ctype = r.headers.get("Content-Type", "")
    if not ctype.lower().startswith("image/"):
        return None
    return r.content, ctype.split(";")[0].strip()


def _decode_data_uri(data_uri: str) -> Optional[Tuple[bytes, str]]:
    m = DATA_URI_RE.search(data_uri)
    if not m:
        return None
    mime = m.group(1).lower()
    b64 = re.sub(r"\s+", "", m.group(2))
    try:
        data = base64.b64decode(b64, validate=False)
        if len(data) < 1024:
            return None
        ctype = "image/jpeg" if mime in ("jpg", "jpeg") else f"image/{mime}"
        return data, ctype
    except Exception:
        return None


async def scrape_mfds_image(item_seq: str) -> Optional[Tuple[bytes, str, str]]:
    """
    MFDS 상세 페이지에서 이미지 바이트 추출.
    return: (bytes, content_type, source_tag) or None
    """
    async with httpx.AsyncClient(
        headers=DEFAULT_HEADERS,
        follow_redirects=True,
        timeout=DEFAULT_TIMEOUT,
        limits=DEFAULT_LIMITS,
    ) as client:
        # 상세 페이지 접근
        r = await _get_with_retry(
            client,
            f"{BASE_MFDS}/pbp/CCBBB01/getItemDetail",
            params={"itemSeq": item_seq},
            tries=2,
        )
        if r is None or r.status_code != 200:
            return None

        _set_reasonable_encoding(r)
        html = r.text
        soup = BeautifulSoup(html, "lxml")

        # 1) data:image 직접
        for img in soup.select("img[src]"):
            src = img.get("src", "")
            if src.startswith("data:image/"):
                got = _decode_data_uri(src)
                if got:
                    data, ctype = got
                    return data, ctype, "mfds_datauri"

        # 2) itemImageDownload 링크
        for img in soup.select("img[src]"):
            src = img.get("src", "")
            if "itemImageDownload" in src:
                abs_url = src if src.startswith("http") else urljoin(BASE_MFDS, src)
                got = await _fetch_image_bytes(client, abs_url)
                if got:
                    data, ctype = got
                    return data, ctype, "mfds_download"

        # 3) HTML 정규식 fallback
        m = re.search(
            r"(?:https?:)?//nedrug\.mfds\.go\.kr[^\s\"'<>)]*itemImageDownload[^\s\"'<>)]*|/pbp/cmn/itemImageDownload[^\s\"'<>)]*",
            html,
            re.I,
        )
        if m:
            raw = m.group(0).replace("\\/", "/")
            abs_url = raw if raw.startswith("http") else urljoin(BASE_MFDS, raw)
            got = await _fetch_image_bytes(client, abs_url)
            if got:
                data, ctype = got
                return data, ctype, "mfds_html_fallback"

        # 4) HTML 내 data:image 스캔
        m2 = DATA_URI_RE.search(html)
        if m2:
            got = _decode_data_uri(m2.group(0))
            if got:
                data, ctype = got
                return data, ctype, "mfds_datauri_html"

    return None


async def get_or_fetch_image(
    item_seq: str,
    force_refresh: bool = False,
) -> Tuple[Any, str, Dict[str, Any]]:
    """
    이미지를 캐시에서 가져오거나, 필요시 스크래핑.
    return: (stream, content_type, meta_info)
    """
    # 1) 기존 캐시 메타 조회
    meta = await get_meta(item_seq)

    # 캐시가 있고 fresh하며 강제 새로고침이 아니면 캐시 반환
    if meta and not force_refresh and _is_fresh(meta.get("updatedAt")):
        stream = await open_stream_by_item_seq(item_seq)
        if stream:
            stream, meta = stream
            return stream, meta.get("contentType", "image/jpeg"), meta

    # 2) 스크래핑 시도
    result = await scrape_mfds_image(item_seq)

    if not result:
        # 외부 타임아웃/실패
        if meta:
            # 캐시 있으면 그대로 반환
            stream = await open_stream_by_item_seq(item_seq)
            if stream:
                stream, meta = stream
                return stream, meta.get("contentType", "image/jpeg"), meta
        # 캐시 없으면 504
        raise HTTPException(status_code=404, detail="upstream timeout or error")

    data, content_type, source = result

    # 3) GridFS에 저장
    meta = await save_bytes(
        item_seq=item_seq,
        data=data,
        content_type=content_type,
        source=source,
    )

    # 4) 새로 저장된 이미지 스트림 열기
    stream = await open_stream_by_item_seq(item_seq)
    if stream:
        stream, meta = stream
        return stream, meta.get("contentType", "image/jpeg"), meta

    # 5) 저장 실패 시: 캐시 있으면 캐시 반환, 없으면 500
    if meta:
        stream = await open_stream_by_item_seq(item_seq)
        if stream:
            stream, meta = stream
            return stream, meta.get("contentType", "image/jpeg"), meta

    raise HTTPException(status_code=500, detail="cache save failed")
