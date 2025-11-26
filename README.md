# 💊 PillyPilly - 알약 정보 조회 및 처방전 분석 앱

장애인 해커톤 프로젝트로 개발된 **접근성을 고려한 알약 정보 조회 및 처방전 분석 모바일 애플리케이션**입니다.

## 📱 주요 기능

### 1. 의약품 검색
- **음성 검색**: 음성으로 약 이름을 말하면 검색
- **텍스트 검색**: 텍스트로 약 이름 입력하여 검색
- **이미지 검색**: 알약 사진을 촬영하여 검색

### 2. 처방전/약봉투 분석
- **처방전 OCR**: 처방전 이미지를 촬영하거나 갤러리에서 선택하여 약 목록 자동 추출
- **약봉투 OCR**: 약봉투 이미지를 분석하여 약 정보 추출
- **알약 촬영**: 인식된 약들을 순서대로 촬영하여 확인
- **자동 회전 재시도**: 이미지 인식 실패 시 자동으로 회전하여 재시도 (최대 3회)

### 3. 약 상자 인식
- **QR/바코드 스캔**: 약 상자의 QR코드 또는 바코드를 스캔하여 약 정보 조회
- **유효기간 인식**: 약 상자 앞면/뒷면을 촬영하여 유효기간 자동 추출

### 4. 처방전/약봉투 보관함
- 분석한 처방전과 약봉투 정보를 저장하여 나중에 다시 확인 가능
- 저장된 처방전 목록 조회 및 삭제

### 5. 접근성 기능
- **음성 안내**: 화면 전환 및 주요 기능에 대한 음성 안내 (On/Off 가능)
- **폰트 크기 조절**: 사용자가 원하는 크기로 폰트 조절 가능
- **고대비 모드**: 시각 장애인을 위한 고대비 색상 모드
- **진동 피드백**: 주요 액션에 대한 햅틱 피드백 제공
- **스크린 리더 지원**: Talkback/VoiceOver 완전 지원

## 🏗️ 프로젝트 구조

```
pillypilly_hack/
├── front/              # Flutter 프론트엔드
│   ├── lib/
│   │   ├── screens/    # 화면 구성
│   │   ├── services/  # 비즈니스 로직
│   │   ├── widgets/   # 재사용 가능한 위젯
│   │   └── utils/     # 유틸리티
│   └── pubspec.yaml
│
└── back/               # FastAPI 백엔드
    └── FastAPI/
        ├── app/
        │   ├── api/    # API 라우터
        │   ├── services/ # 서비스 로직
        │   ├── inference/ # AI/ML 모델
        │   └── db/     # 데이터베이스
        └── requirements.txt
```

## 🛠️ 기술 스택

### Frontend
- **Flutter** 3.8.1+
- **Provider** - 상태 관리
- **Camera** - 카메라 기능
- **Flutter TTS** - 텍스트 음성 변환
- **Speech to Text** - 음성 인식
- **Google ML Kit** - 바코드/텍스트 인식
- **Dio** - HTTP 클라이언트
- **SQFlite** - 로컬 데이터베이스

### Backend
- **FastAPI** - Python 웹 프레임워크
- **Pydantic** - 데이터 검증
- **SQLAlchemy** - ORM
- **OCR 모델** - 처방전/약봉투 텍스트 추출
- **이미지 처리** - OpenCV, PIL

## 📋 사전 요구사항

### Frontend
- Flutter SDK 3.8.1 이상
- Android Studio / Xcode (각 플랫폼 개발용)
- Android SDK / iOS 개발 환경

### Backend
- Python 3.9 이상
- pip 또는 poetry

## 🚀 설치 및 실행

### Frontend 설정

1. **저장소 클론**
```bash
cd front
```

2. **의존성 설치**
```bash
flutter pub get
```

3. **환경 변수 설정**
```bash
# .env 파일 생성
cp .env.example .env

# .env 파일에 API_BASE_URL 설정
API_BASE_URL=https://your-api-url.com
```

4. **앱 실행**
```bash
# Android
flutter run

# iOS
flutter run -d ios

# APK 빌드
flutter build apk --release
```

### Backend 설정

1. **저장소 클론**
```bash
cd back/FastAPI
```

2. **가상 환경 생성 및 활성화**
```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
```

3. **의존성 설치**
```bash
pip install -r requirements.txt
```

4. **환경 변수 설정**
```bash
# .env 파일 생성 및 설정
# 필요한 환경 변수들을 설정
```

5. **서버 실행**
```bash
python run.py
# 또는
uvicorn app.main:app --reload
```

## 📖 사용 방법

### 의약품 검색
1. 메인 화면에서 "의약품 검색하기" 선택
2. 음성 또는 텍스트로 약 이름 입력
3. 검색 결과에서 약 선택하여 상세 정보 확인

### 처방전 분석
1. 메인 화면에서 "처방전 약봉투 분석" 선택
2. "처방전" 또는 "약봉투" 선택
3. 카메라로 촬영하거나 갤러리에서 이미지 선택
4. "분석하기" 버튼 클릭
5. 인식된 약 목록 확인 및 알약 촬영 진행
6. 결과를 보관함에 저장 (선택사항)

### 약 상자 인식
1. 메인 화면에서 "약 상자 인식" 선택
2. QR/바코드 스캔 또는 유효기간 인식 선택
3. 카메라로 스캔/촬영
4. 약 정보 확인

## ⚙️ 설정

### 접근성 설정
- **음성 안내**: On/Off 토글
- **폰트 크기**: 슬라이더로 조절 (1.0x ~ 2.0x)
- **고대비 모드**: On/Off 토글

설정 화면에서 접근성 옵션을 조절할 수 있습니다.

## 🔧 개발

### 코드 스타일
- Flutter: `flutter_lints` 규칙 준수
- Python: PEP 8 스타일 가이드 준수

### 주요 디렉토리 설명

#### Frontend (`front/lib/`)
- `screens/`: 각 화면의 UI 구성
  - `main_screen.dart`: 메인 화면
  - `search_screens/`: 검색 관련 화면
  - `upload_page_screens/`: 처방전/약봉투 분석 화면
  - `box_screens/`: 약 상자 인식 화면
  - `keeping_screens/`: 보관함 화면
  - `setting_screens/`: 설정 화면
- `services/`: 비즈니스 로직 및 API 통신
- `widgets/`: 재사용 가능한 위젯 컴포넌트

#### Backend (`back/FastAPI/app/`)
- `api/v3/`: API 엔드포인트 라우터
- `services/`: 비즈니스 로직
- `inference/`: AI/ML 모델 추론
- `db/`: 데이터베이스 모델 및 연결

## 📞 문의

osak7806@gmail.com
000602jh@naver.com
doxxeon@gmail.com

---

**PillyPilly** - 더 나은 약물 관리를 위한 접근성 중심 솔루션 💊

