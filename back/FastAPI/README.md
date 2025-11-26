📁 pilly-pilly/FastAPI   
   
├── .env                      # 환경변수 설정 파일 (API 키 등 보안 정보)   
├── README.md   
├── requirements.txt          # Python 의존성 패키지 목록   
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
│   │   └── 📁 v3             # v3 버전 API 라우터들   
│   │       ├── __init__.py                  # v3 패키지 초기화   
│   │       ├── auth_router.py              # JWT 인증 라우터   
│   │       ├── drug_bag_router_split.py     # 약봉지 분할 OCR 라우터   
│   │       ├── dur_router.py                # DUR 정보 조회 라우터   
│   │       ├── expiry_date_router.py        # 유효기간 추출 라우터   
│   │       ├── favorite_log_router.py       # 즐겨찾기 등록/조회 라우터   
│   │       ├── gemini_chatbot.py           # Gemini 기반 챗봇 응답 라우터   
│   │       ├── identify_feature_based.py   # 특징 기반 알약 식별 라우터   
│   │       ├── image_based.py              # 이미지 기반 알약 식별 라우터   
│   │       ├── image_scrape_router.py      # 이미지 스크래핑 라우터   
│   │       ├── keyword_feature_based.py    # 키워드 기반 검색 라우터   
│   │       ├── log_router.py               # 로그 저장용 라우터   
│   │       └── prescription_ocr_router2.py # 처방전 OCR 라우터   
   
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
│   │   ├── gemini_client.py             # Gemini API 통신 모듈   
│   │   └── rerank.py                    # 검색 결과 재순위화 서비스   
   
│   ├── 📁 inference          # AI 모델 추론 관련 모듈   
│   │   ├── __init__.py                  # 추론 패키지 초기화   
│   │   ├── image_model.py               # 이미지 기반 알약 식별 통합 모델   
│   │   ├── color.py                     # 색상 분석 모듈   
│   │   ├── drug_bag_split_ocr.py        # 약봉지 분할 OCR 모듈   
│   │   ├── expiry_date_extractor.py     # 유효기간 추출 모듈   
│   │   ├── prescription_ocr.py          # 처방전 OCR 모듈   
│   │   └── 📁 resources                 # class/color 매핑 JSON 포함     
   
│   ├── 📁 models             # 학습된 모델 파일 보관 폴더   
   
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
│   │       ├── prescription_model_log.py # 처방전 모델 로그 CRUD   
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
   