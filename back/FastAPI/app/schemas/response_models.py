# app/schemas/response_models.py
# 응답 JSON 모델 정의

from pydantic import BaseModel
from typing import List, Optional

# ──────────────────────────────────────────────
# 응답 모델 정의
# ──────────────────────────────────────────────
class PermitPrecautions(BaseModel):
    contraindications: List[str]
    warnings: List[str]

class PermitDetail(BaseModel):
    itemName: str
    engName: Optional[str]
    manufacturer: Optional[str]
    permitDate: Optional[str]
    consignManufacturer: Optional[str]
    drugType: Optional[str]
    chart: Optional[str]
    packUnit: Optional[str]
    validTerm: Optional[str]
    storageMethod: Optional[str]
    mainIngredient: Optional[str]
    mainIngredientEng: Optional[str]
    materialInfo: List[str]
    excipients: List[str]
    efficacy: List[str]
    dosage: List[str]
    precautions: PermitPrecautions
