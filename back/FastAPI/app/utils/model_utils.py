# app/utils/model_utils.py
from PIL import Image
import numpy as np
from sklearn.cluster import KMeans
from numpy import dot
from numpy.linalg import norm
from collections import Counter

# ──────────────────────────────────────────────
# 주요 색상 추출
# ──────────────────────────────────────────────
def get_dominant_color(image: Image.Image, crop_ratio: float = 0.3, k: int = 3):
    img_np = np.array(image.convert("RGB"))
    h, w, _ = img_np.shape

    # 중앙 부분 크롭
    ch = int(h * crop_ratio)
    cw = int(w * crop_ratio)
    start_y = (h - ch) // 2
    start_x = (w - cw) // 2
    cropped = img_np[start_y:start_y + ch, start_x:start_x + cw].reshape(-1, 3)

    # KMeans 적용
    kmeans = KMeans(n_clusters=k, n_init=10, random_state=42)
    kmeans.fit(cropped)

    # 가장 빈도 높은 클러스터 번호를 찾기
    dominant_cluster = Counter(kmeans.labels_).most_common(1)[0][0]

    # dominant color 추출
    dominant_color = kmeans.cluster_centers_[dominant_cluster]
    return tuple(map(int, dominant_color))

# ──────────────────────────────────────────────
# 색상 유사도 계산
# ──────────────────────────────────────────────
def calculate_color_similarity(color1: tuple, color2, mode: str = "mse") -> float:
    """
    color1: (3,) shape
    color2: (3,) or (N,3) shape → 자동 처리
    """
    vec1 = np.array(color1)
    vec2 = np.array(color2)

    if vec2.ndim == 2:  # (N,3)인 경우 → 각 색상과 비교 후 평균
        similarities = [
            calculate_color_similarity(vec1, c, mode)
            for c in vec2
        ]
        return float(np.mean(similarities))

    if mode == "cosine":
        if norm(vec1) == 0 or norm(vec2) == 0:
            return 0.0
        return dot(vec1, vec2) / (norm(vec1) * norm(vec2))
    else:
        mse = np.mean((vec1 - vec2) ** 2)
        return mse
