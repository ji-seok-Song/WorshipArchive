# 찬양서랍 1.0 App Store 배포 체크리스트

기준일: 2026년 9월 16일

## 현재 기술 설정

- 앱 이름: `찬양서랍`
- Bundle ID: `com.jacky.WorshipArchive`
- iCloud 컨테이너: `iCloud.com.jacky.WorshipArchive`
- 버전: `1.0`
- 빌드: `52`
- 지원 기기: iPhone, iPad
- 최소 OS: iOS/iPadOS 26.0
- 추적, 광고, 제3자 분석 SDK: 없음
- 비면제 암호화: 사용 안 함. 운영체제가 제공하는 CloudKit 통신만 사용
- 개인정보 매니페스트: 파일 시각 API `C617.1`, 추적 및 개발자 수집 없음

최소 OS가 26.0이므로 그보다 이전 OS 사용자는 앱을 설치할 수 없다. 첫 출시 범위를 넓히려면 별도의 하위 OS 호환 작업이 필요하다.

## 2026년 9월 16일 최종 로컬 검증 결과

- 개인정보 매니페스트, Info.plist, Entitlements, 프로젝트 파일 형식 검사 통과
- iOS 26.0 시뮬레이터 전체 자동 테스트 `103/103` 통과
- iOS 26.5 시뮬레이터 전체 자동 테스트 `103/103` 통과
- iPhone·iPad용 Release `1.0 (52)` 아카이브 생성 성공
- App Store Connect 배포 방식으로 서명된 IPA 내보내기 성공
- 배포 프로파일 `iOS Team Store Provisioning Profile: com.jacky.WorshipArchive` 적용 확인
- `aps-environment=production`, CloudKit `Production`, `get-task-allow=false` 확인
- 앱 아이콘, 개인정보 매니페스트, 버전, 최소 OS 26.0, iPhone·iPad 지원 정보 포함 확인
- 내보낸 앱 번들의 코드 서명 무결성 검사 통과

로컬 빌드·테스트·Archive·App Store용 내보내기 검사는 완료했다. App Store Connect 서버 업로드 검증과 심사 제출은 계정 로그인이 필요한 단계이므로 사용자가 Xcode Organizer 또는 App Store Connect에서 최종 확인 후 진행한다.

재현 가능한 내보내기 설정은 `Configuration/AppStoreExportOptions.plist`에 저장되어 있으며 CloudKit Production 환경, 자동 서명, dSYM 업로드를 사용한다.

## App Store 표시 정보

복사해서 사용할 최종 입력본은 [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md)에 정리되어 있다.

### 기본 정보

- 이름: `찬양서랍`
- 부제: `찬양 악보를 곡별로 정리하고 찾기`
- 기본 카테고리: 음악
- 보조 카테고리: 생산성

### 홍보 문구

여러 곡이 담긴 찬양 악보 PDF를 한 번만 추가하세요. 곡별 페이지를 확인해 저장하고 제목, 원본 PDF 이름, 키로 빠르게 다시 찾을 수 있습니다.

### 설명

찬양서랍은 여러 곡이 함께 들어 있는 찬양 악보 PDF를 곡 단위로 정리해 주는 iPhone·iPad 앱입니다.

PDF를 추가하면 내장 텍스트와 기기 내 문자 인식을 이용해 곡 제목, 페이지 범위, 키를 제안합니다. 결과를 직접 확인하고 수정한 뒤 저장할 수 있어 자동 인식이 완벽하지 않은 악보도 안전하게 정리할 수 있습니다.

주요 기능

- 여러 곡이 담긴 PDF를 한 번에 가져오기
- 곡 제목, 페이지 범위, 키 자동 제안 및 저장 전 수정
- 곡 제목과 원본 PDF 이름 검색
- 키별 라이브러리 필터
- 곡을 누르면 해당 곡 페이지만 바로 열기
- 곡 페이지만 별도 PDF로 만들어 공유
- 즐겨찾기와 마지막으로 본 페이지 기억
- 기기에 먼저 저장하고 iCloud로 기기 간 동기화
- 다른 PDF 앱의 공유 메뉴에서 바로 가져오기

악보는 사용자의 기기에서 분석되며 광고나 사용자 추적 기능을 사용하지 않습니다.

### 키워드

`찬양,악보,PDF,콘티,예배,CCM,교회,찬송,키,라이브러리`

## App Review 메모

앱 자체 로그인은 필요하지 않습니다. iCloud에 로그인하지 않아도 로컬 저장 기능을 사용할 수 있습니다.

검토 방법:

1. 홈 또는 라이브러리의 PDF 추가 버튼으로 여러 페이지 PDF를 선택합니다.
2. 분석이 끝나면 제안된 곡 제목, 키, 페이지 범위를 확인하고 저장합니다.
3. 라이브러리에서 곡을 누르면 해당 곡의 페이지만 표시됩니다.
4. 뷰어의 공유 버튼으로 해당 곡 페이지만 포함된 PDF를 공유할 수 있습니다.
5. 파일 또는 Goodnotes 같은 앱의 공유 메뉴에서도 PDF를 찬양서랍으로 열 수 있습니다.

앱은 악보 콘텐츠를 자체 제공하거나 배포하지 않습니다. 모든 PDF는 사용자가 직접 선택하며, 사용자는 가져오고 공유하는 콘텐츠에 필요한 권리를 보유해야 합니다. Vision OCR은 기기 안에서 실행됩니다.

## App Store Connect에서 사용자가 입력할 항목

- [ ] 앱 레코드를 Bundle ID `com.jacky.WorshipArchive`로 생성
- [ ] SKU 입력
- [ ] 기본 언어를 한국어로 선택
- [ ] 카테고리와 연령 등급 설문 완료
- [ ] 저작권 표기 입력
- [x] 개인정보처리방침과 지원 문서에 운영자명·이메일 반영
- [ ] GitHub Pages 배포 후 `https://ji-seok-song.github.io/WorshipArchive/privacy/` 공개 접속 확인
- [ ] 지원 URL `https://ji-seok-song.github.io/WorshipArchive/support/` 입력
- [ ] 개인정보처리방침 URL `https://ji-seok-song.github.io/WorshipArchive/privacy/` 입력
- [ ] App Privacy에서 현재 코드 기준 `개발자가 수집하는 데이터 없음` 선택
- [ ] 콘텐츠 권리 질문에는 사용자 제공 PDF를 다루는 점을 고려해 답변하고, 위 Review 메모를 함께 제공
- [ ] 가격 및 배포 국가 선택
- [ ] iPhone과 iPad 스크린샷 업로드
- [ ] 설명, 키워드, 홍보 문구 입력
- [ ] 빌드를 선택하고 App Review 연락처 입력

## CloudKit 운영 전환

App Store 빌드는 CloudKit의 Production 환경만 사용한다. 업로드 전에 아래를 완료한다.

- [ ] 개발용 앱에서 SwiftData 모델과 PDF 자산 업로드를 각각 한 번 이상 실행해 Development 스키마 생성
- [ ] CloudKit Console에서 `iCloud.com.jacky.WorshipArchive` 선택
- [ ] Development 환경에 SwiftData 레코드 타입과 `WAPDFAsset` 타입이 존재하는지 확인
- [ ] `WAPDFAsset`에 `checksum`, `fileSize`, `pageCount`, `schemaVersion`, `pdf` 필드가 있는지 확인
- [ ] Deploy Schema Changes로 Development 스키마를 Production에 배포
- [ ] Production에서 새 iCloud 계정으로 업로드, 다운로드, 삭제 및 기기 간 동기화 확인

스키마 배포는 레코드 구조만 복사하며 Development의 테스트 데이터는 Production으로 복사하지 않는다.

## 스크린샷 준비

iPhone과 iPad를 모두 지원하므로 두 기기군의 스크린샷이 필요하다.

추천 장면:

1. PDF 추가가 보이는 홈
2. 자동 분석 결과를 확인하고 수정하는 화면
3. 키 필터가 적용된 라이브러리
4. 곡 페이지만 열린 악보 뷰어
5. 곡별 PDF 공유 화면

실제 저작권 악보, 실명, 개인 메모가 포함된 자료 대신 직접 만든 샘플 또는 사용 허가를 받은 자료를 사용한다.

## TestFlight 최종 점검

- [ ] 새 설치 상태에서 첫 PDF 가져오기
- [ ] 1페이지 곡과 여러 페이지 곡의 범위 확인
- [ ] 제목과 키 수정, 곡 삭제
- [ ] 제목 및 PDF 이름 검색, 키 필터
- [ ] 곡별 PDF 공유
- [ ] Goodnotes 또는 파일 앱에서 `찬양서랍`으로 열기
- [ ] iCloud 로그인 상태에서 두 기기 동기화
- [ ] iCloud 로그아웃 또는 오프라인 상태에서 로컬 이용
- [ ] 손상된 PDF와 중복 PDF 오류 안내
- [ ] iPhone과 iPad의 세로·가로 레이아웃
- [ ] 개인정보처리방침과 지원 페이지의 공개 접속

위 검증이 끝난 빌드를 TestFlight 내부 테스트로 먼저 배포한 뒤 App Review에 제출한다.
