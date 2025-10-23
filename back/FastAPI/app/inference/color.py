#IMAGE_COLOR 알약 이미지 중심색 추출하기

import os
import json
import numpy as np
from PIL import Image
from collections import Counter
from sklearn.cluster import KMeans

def get_dominant_color(image: Image.Image, crop_ratio: float = 0.2, k: int = 3, topn: int = 2):
    """KMeans를 활용하여 중심부 dominant color top-n 추출"""
    img_np = np.array(image.convert("RGB"))
    h, w, _ = img_np.shape

    # 중심 crop
    ch = int(h * crop_ratio)
    cw = int(w * crop_ratio)
    start_y = (h - ch) // 2
    start_x = (w - cw) // 2
    cropped = img_np[start_y:start_y + ch, start_x:start_x + cw].reshape(-1, 3)

    # KMeans 클러스터링
    kmeans = KMeans(n_clusters=k, n_init=10, random_state=42)
    kmeans.fit(cropped)

    # 클러스터 비율 순서대로 topn 추출
    cluster_freq = Counter(kmeans.labels_)
    top_clusters = [cid for cid, _ in cluster_freq.most_common(topn)]
    colors = [kmeans.cluster_centers_[cid].astype(int).tolist() for cid in top_clusters]
    return colors

def main():
    input_dir = r"C:\Users\302-26\pilly-pilly\FastAPI\app\inference\image_color"
    output_json = r"C:\Users\302-26\pilly-pilly\FastAPI\app\inference\color_map2.json"
    color_map = {}

    image_files = [f for f in os.listdir(input_dir) if f.endswith(".png")]

    print(f"[INFO] 총 {len(image_files)}장의 이미지를 처리합니다.\n")

    for idx, filename in enumerate(image_files, 1):
        item_seq = filename.replace(".png", "")
        img_path = os.path.join(input_dir, filename)

        try:
            image = Image.open(img_path)
            dominant_color = get_dominant_color(image)

            color_map[item_seq] = dominant_color
            print(f"[{idx:03d}] {item_seq} → 대표색상: {dominant_color}")

        except Exception as e:
            print(f"[{idx:03d}] {item_seq} 처리 실패: {e}")
            continue

    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(color_map, f, indent=2, ensure_ascii=False)

    print(f"\n color_map.json 생성 완료: {output_json}")

if __name__ == "__main__":
    main()