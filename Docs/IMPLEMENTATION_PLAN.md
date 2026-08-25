# 찬양서랍 구현 계획

## 제품 목표

첫 번째 버전은 아래의 한 흐름을 끝까지 완성하는 데 집중한다.

`PDF 선택 → 원본 보관 → 페이지 분석 → 곡 범위 제안 → 사용자 확인 → 라이브러리 등록 → 검색 → 열기·곡 PDF 공유`

## 현재 결정

- Xcode 프로젝트에 설정된 iOS/iPadOS 26.5를 우선 유지한다.
- 로컬 데이터는 SwiftData, PDF 표시는 PDFKit, 문자 인식은 Vision을 사용한다.
- PDF 내장 텍스트를 먼저 사용하고 텍스트가 부족한 페이지만 OCR한다.
- 자동 인식 결과는 확정하지 않고 제목·키·페이지 범위를 편집하는 확인 단계를 거친다.
- 원본 PDF 하나에 여러 `ScoreVersion` 페이지 범위를 연결한다.
- 같은 제목의 곡은 자동 병합하지 않고 이후 사용자에게 병합 후보만 제안한다.
- 키는 악보 버전에 저장하고 곡의 대표 키는 연결된 악보에서 표시한다.
- 즐겨찾기는 곡 단위로, 마지막으로 본 페이지는 악보 버전 단위로 저장한다.
- 검색은 곡 제목, 원본 PDF 이름, 키에 집중한다.
- 곡 페이지 범위는 원본 품질을 유지한 별도 PDF로 추출해 시스템 공유 시트로 전달한다.
- 첫 가져오기 방식은 파일 앱의 PDF 선택으로 제한한다. 공유 확장·사진·카메라는 핵심 흐름이 안정된 뒤 추가한다.
- CloudKit은 로컬 핵심 흐름과 데이터 모델이 안정된 뒤 연결한다.

## 커밋 단위와 완료 조건

각 작업은 구현, 관련 검증, `git diff --check`, 커밋까지 한 단위로 끝낸다. 커밋 후 작업 트리는 깨끗해야 한다.

1. `docs: add implementation roadmap`
   - MVP 범위, 기술 결정, 커밋 규칙을 저장소에 기록한다.
2. `feat: add adaptive app navigation shell`
   - 홈, 검색, 라이브러리, 설정 화면 사이를 이동할 수 있다.
   - iPhone과 iPad에서 레이아웃이 깨지지 않는다.
3. `feat: define local archive data model`
   - 원본 문서, 페이지 분석, 곡, 악보 버전, 뷰어 상태를 저장할 수 있다.
4. `feat: add sandboxed PDF document storage`
   - 가져온 파일을 앱 전용 폴더에 원본 그대로 복사하고 중복을 식별한다.
5. `feat: import PDF files from document picker`
   - PDF만 선택할 수 있고 손상 파일과 접근 실패를 사용자에게 알린다.
6. `feat: extract embedded text from PDF pages`
   - 페이지별 텍스트와 진행 상태를 생성한다.
7. `feat: add Vision OCR fallback`
   - 내장 텍스트가 부족한 페이지를 한국어·영어 OCR로 보완하고 재시도할 수 있다.
8. `feat: suggest song titles and page ranges`
   - 제목 후보와 곡 시작 페이지를 신뢰도와 함께 제안한다.
9. `feat: add analysis review flow`
   - 곡 추가·삭제와 제목·키·페이지 범위 수정 후에만 저장한다.
10. `feat: build searchable song library`
    - 곡 제목·원본 PDF 이름 검색, 키 필터, 즐겨찾기가 동작한다.
11. `feat: open song ranges in PDF viewer`
    - 선택한 곡의 시작 페이지로 열고 마지막 페이지를 기억한다.
12. `feat: simplify search around songs, PDF names, and keys`
    - 가사·예배 기록 없이 곡 제목, 원본 PDF 이름, 키를 중심으로 빠르게 찾는다.
13. `feat: sync archives with CloudKit`
    - 로컬 전용 모드를 유지하면서 메타데이터와 PDF 자산을 동기화한다.
14. `feat: support offline access and adaptive iPad viewing`
    - 내려받은 악보를 오프라인에서 열고 iPad 연주 모드를 제공한다.
15. `feat: export and share individual song PDFs`
    - 곡의 페이지 범위만 새 PDF로 만들고 공유 후 임시 파일을 정리한다.

## 검증 전략

- 기능 커밋마다 iOS Simulator용 Debug 빌드를 실행한다.
- 순수 로직은 테스트 타깃을 추가한 뒤 단위 테스트로 검증한다.
- 실제 저작권 악보나 개인 PDF는 저장소에 넣지 않고 작은 합성 PDF를 테스트 픽스처로 사용한다.
- PDF 가져오기, 권한, OCR 실패, 손상 문서, 오프라인 상태를 오류 시나리오에 포함한다.

## 후순위

공유 확장, 사진 가져오기, 문서 스캔, 자동 키 추천, 필기, 블루투스 페달, 셋리스트 협업, 음원 연결은 핵심 흐름 이후 별도 커밋으로 개발한다.
