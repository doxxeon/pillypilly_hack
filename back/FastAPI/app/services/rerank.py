# app/services/rerank.py
from typing import List, Tuple, Dict, Any, Optional, Set


def rerank_with_rx(
    scored: List[Dict[str, Any]],
    rx_set: Set[str],
    prescription_id: Optional[str] = None,
) -> Tuple[List[Dict[str, Any]], Optional[Dict[str, Any]]]:
    """
    규칙:
    1) scored ∩ rx_set 있으면: 교집합만 점수 내림차순 → selected = 0번
       reranked = [교집합] + [비교집합]
    2) 교집합 없으면: rx_set을 후보군으로 대체(score=0.0, source='from_prescription')
       selected = 첫 항목(사전 정의 우선순위 가능)
    """

    def _debug_print(message: str) -> None:
        if prescription_id:
            print(f"[rerank][{prescription_id}] {message}")

    def _norm_seq(v: Any) -> Optional[str]:
        """item_seq/ rx_set 항목을 str로 정규화"""
        if v is None:
            return None
        s = str(v).strip()
        return s if s else None

    rx_set_norm: Set[str] = set()
    for r in rx_set or []:
        n = _norm_seq(r)
        if n is not None:
            rx_set_norm.add(n)

    def _as_dict(c: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        모델 결과 한 건을 내부 공통 포맷으로 변환
        - {"item_seq": str, "score": float, "source": "default"}
        """
        s = _norm_seq(c.get("item_seq"))
        if s is None:
            return None
        return {
            "item_seq": s,
            "score": float(c.get("final_score", 0.0)),
            "source": "default",
        }

    # scored → base 리스트로 정규화
    base: List[Dict[str, Any]] = []
    for c in (scored or []):
        d = _as_dict(c)
        if d:
            base.append(d)

    # 1) 교집합 우선
    matches: List[Dict[str, Any]] = [
        c for c in base if c["item_seq"] in rx_set_norm
    ]

    if matches:
        # 점수 내림차순 정렬
        matches.sort(key=lambda x: x["score"], reverse=True)
        others = [c for c in base if c["item_seq"] not in rx_set_norm]

        reranked: List[Dict[str, Any]] = (
            [
                {
                    "item_seq": m["item_seq"],
                    "score": m["score"],
                    "source": "match_prescription",
                }
                for m in matches
            ]
            + others
        )

        selected: Dict[str, Any] = {
            "item_seq": matches[0]["item_seq"],
            "drug_name": None,
            "timing": None,
            "reason": "모델/처방 교집합 최고 점수",
        }
        _debug_print(
            f"matched {len(matches)} / {len(base)} candidates "
            f"(rx={len(rx_set_norm)}). top={selected['item_seq']}"
        )
        return reranked, selected

    # 2) 교집합이 전혀 없으면 → 처방전 기반 추정
    if rx_set_norm:
        fallback: List[Dict[str, Any]] = [
            {
                "item_seq": x,
                "score": 0.0,
                "source": "from_prescription",
            }
            for x in rx_set_norm
        ]
        selected = {
            "item_seq": fallback[0]["item_seq"],
            "drug_name": None,
            "timing": None,
            "reason": "모델 후보와 미일치 → 처방전 기반 추정",
        }
        _debug_print(
            "no intersection with rx_set → fallback to prescription list "
            f"(rx={len(rx_set_norm)}, scored={len(base)})"
        )
        return fallback, selected

    # 3) rx_set 자체가 비어 있으면 → 처방 미연계, raw 그대로
    reranked = base
    selected = base[0] if base else None
    if selected is not None and "reason" not in selected:
        selected["reason"] = "처방전 미연계 기본 선택"
    _debug_print(
        f"rx_set empty, returning raw candidates (count={len(base)})"
    )
    return reranked, selected
