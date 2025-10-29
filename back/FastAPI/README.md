📁 pilly-pilly/FastAPI   
   
├── .env                      # 환경변수 설정 파일 (API 키 등 보안 정보)   
├── .gitignore   
├── README.md   
├── requirements.txt          # Python 의존성 패키지 목록   
├── requirements2.txt         # 추가 Python 의존성 패키지 목록   
├── run.py                    # FastAPI 실행 진입점 (uvicorn)     
   
├── 📁 app                    # FastAPI 애플리케이션 메인 디렉토리   
│   ├── main.py               # FastAPI 인스턴스 및 라우터 등록   
│   ├── __init__.py           # Python 패키지 초기화   
   
│   ├── 📁 core               # 공통 설정 및 의존성 관리   
│   │   ├── config.py         # 환경변수 로딩 및 기본 설정   
│   │   ├── dependencies.py   # 의존성 주입 함수 정의   
│   │   ├── errors.py         # 커스텀 에러 클래스 정의   
│   │   └── rate_limit.py     # 요청 제한 및 동시성 제어   
   
│   ├── 📁 api                # API 라우터 모음   
│   │   ├── __init__.py       # API 패키지 초기화   
│   │   └── 📁 v2             # v2 버전 API 라우터들   
│   │       ├── __init__.py              # v2 패키지 초기화   
│   │       ├── admin_page.py            # 관리자 페이지 및 통계 API   
│   │       ├── auth_router.py           # JWT 인증 라우터   
│   │       ├── favorite_log_router.py   # 즐겨찾기 등록/조회 라우터   
│   │       ├── gemini_chatbot.py        # Gemini 기반 챗봇 응답 라우터   
│   │       ├── identify_feature_based.py # 특징 기반 알약 식별 라우터   
│   │       ├── image_based.py           # 이미지 기반 알약 식별 라우터   
│   │       ├── image_scrape_router.py   # 이미지 스크래핑 라우터   
│   │       ├── keyword_feature_based.py # 키워드 기반 검색 라우터   
│   │       └── log_router.py            # 로그 저장용 라우터   
   
│   ├── 📁 services           # 외부 서비스 연동 모듈   
│   │   ├── __init__.py                  # 서비스 패키지 초기화   
│   │   ├── permit_service.py            # 의약품 허가 정보 조회   
│   │   ├── e_drug_service.py            # e약은요 상세정보 조회   
│   │   ├── dur_service.py               # DUR(병용금기 등) 정보 조회   
│   │   ├── identify_feature_service.py  # 낱알 특징 기반 식별 로직   
│   │   ├── image_scrape_service.py      # MFDS 이미지 스크래핑 서비스   
│   │   ├── log_service.py               # 로그 저장 서비스   
│   │   ├── model_log_service.py         # AI 모델 추론 로그 서비스   
│   │   ├── token_service.py             # JWT 토큰 관리 서비스   
│   │   └── gemini_client.py             # Gemini API 통신 모듈   
   
│   ├── 📁 inference          # AI 모델 추론 관련 모듈   
│   │   ├── __init__.py                  # 추론 패키지 초기화   
│   │   ├── image_model.py               # 이미지 기반 알약 식별 통합 모델   
│   │   └── resources/                   # class/color 매핑 JSON 포함   
│   │       ├── class_mapping.json       # 클래스 매핑 데이터   
│   │       ├── color_map2.json          # 색상 매핑 데이터   
│   │       ├── label_data.json          # 라벨 데이터   
│   │       └── 3type_label.json        # 3타입 라벨 데이터   
   
│   ├── 📁 models             # 학습된 모델 파일 보관 폴더   
│   │   ├── 3type_best.pt               # 3타입 분류 모델   
│   │   ├── best_cls.pt                 # 최고 성능 분류 모델   
│   │   └── best_detec.pt               # 최고 성능 검출 모델   
   
│   ├── 📁 db                 # DB 연동 및 모델 정의   
│   │   ├── __init__.py                  # DB 패키지 초기화   
│   │   ├── mongodb.py                   # MongoDB 커넥션   
│   │   ├── models.py                    # Pydantic 기반 DB 모델   
│   │   └── 📁 crud                      # CRUD 작업 모듈   
│   │       ├── __init__.py              # CRUD 패키지 초기화   
│   │       ├── admin_action.py          # 관리자 액션 로그 CRUD   
│   │       ├── chatbot_log.py           # 챗봇 로그 CRUD   
│   │       ├── error_log.py             # 에러 로그 CRUD   
│   │       ├── favorite_log.py          # 즐겨찾기 로그 CRUD   
│   │       ├── image_scrape_cache.py    # 이미지 스크래핑 캐시 CRUD   
│   │       ├── search_log.py            # 검색 로그 CRUD   
│   │       └── user_auth.py             # 사용자 인증 CRUD   
   
│   ├── 📁 schemas            # 요청/응답용 데이터 모델 정의   
│   │   ├── __init__.py                  # 스키마 패키지 초기화   
│   │   └── response_models.py           # 응답 JSON 구조 정의   
   
│   ├── 📁 utils              # 유틸리티 함수 모음   
│   │   ├── __init__.py                  # 유틸리티 패키지 초기화   
│   │   ├── formatter.py                 # 날짜, 텍스트 포맷   
│   │   ├── logger.py                    # 로깅 설정   
│   │   ├── model_utils.py               # 모델 관련 보조 함수   
│   │   ├── ocr_utils.py                 # OCR 관련 유틸   
│   │   └── request_utils.py             # API 요청 보조 함수   
   
│   └── 📁 credentials        # API 키 및 인증 정보   
│       ├── gemini-key.json              # Gemini API 키   
│       └── Google Cloud.json            # Google Cloud 인증 정보   
   
├── 📁 tts_server             # TTS 음성 변환 서브시스템 (RealTime_zeroshot_TTS_ko)   
│   ├── 📁 app                       # FastAPI 기반 TTS API 구성 모듈   
│   │   ├── __init__.py             
│   │   ├── custom_tts.py           # RealTime_zeroshot_TTS_ko 기반 음성 합성 클래스 정의   
│   │   ├── sample_iena.m4a         # 사용자 샘플 음성 파일 (reference audio)   
│   │   ├── tts_router.py           # `/tts` 라우팅 처리 → 사용자 텍스트 입력 → 음성 생성   
│   │   └── 📁 utils   
│   │       ├── __init__.py          # TTS 유틸리티 패키지 초기화   
│   │       └── logger.py            # 로깅 설정 및 로그 저장 유틸   
│   ├── main.py                     # TTS 서버 실행 진입점   
│   ├── run.py                      # (선택적)uvicorn 수동 실행용 CLI 스크립트    
└── └── requirements.txt             # TTS 서버 의존성 패키지 목록   
   