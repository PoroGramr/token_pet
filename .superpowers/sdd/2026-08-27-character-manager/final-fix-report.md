# Character Manager Final Fix Report

- 기준 커밋: `07f2440`
- 구현 커밋: `34718ba` (`fix: harden character data recovery`)
- 작성일: 2026-08-27

## 1. `frameCount` validation trap/OOM 방지

### RED

- `frameCount = -1`인 profile validation을 실행하자 `Range requires lowerBound <= upperBound` fatal error와 exit 133을 재현했다.
- `frameCount = Int.max`인 profile을 JSON encode/decode한 뒤 validation하는 회귀 조건도 함께 추가했다.

### GREEN / 변경

- `CharacterProfileValidator`가 `(3...4).contains(frameCount)`인 경우에만 `Array(0..<frameCount)`를 생성한다.
- 잘못된 frame count에는 `frameCount`, `frameOrder` 오류를 반환하고 range/대형 배열을 만들지 않는다.

### 테스트

- `TokenPetCoreTests`: 음수 profile과 `Int.max` JSON profile 모두 crash 없이 literal error 목록을 반환한다.

## 2. 저장 asset의 실제 PNG/decode/240×240 검증

### RED

- 손상 데이터, 1×1 PNG, 240×240 JPEG를 `.png` 이름으로 source/display에 넣어도 save가 성공했다.
- 같은 파일을 디스크에 주입해도 `list()`에 노출되고 `load()`가 성공했으며, 손상된 selected profile도 built-in fallback되지 않았다.

### GREEN / 변경

- `CharacterPNGAssetValidator`를 공통 경계로 추가했다.
- ImageIO의 실제 source type이 `public.png`인지, 단일 이미지가 즉시 decode되는지, decoded 크기가 정확히 240×240인지 검사한다.
- `CharacterRuntimeAssetValidator`가 source와 display 양쪽의 count/order/image validity를 검사한다.
- `CharacterStore.readAssets`가 동일 validator를 사용하므로 save staging, list, load가 같은 유효성 경계를 공유한다.
- CharacterStore 테스트의 문자열/1×1 정상 fixture를 deterministic 240×240 PNG fixture로 교체했다.

### 테스트

- `TokenPetCharacterStoreTests`: 손상/1×1/JPEG 위장 데이터를 source와 display 각각에 대해 save 거부, 기존 byte 보존, list 제외, load 거부로 검증했다.
- 손상된 selected profile이 `CharacterMenuResolver`를 통해 built-in으로 fallback되고 persisted selection이 정리되는지 검증했다.

## 3. commit 실패 및 orphan backup 복구

### RED

- commit boundary가 실제 target을 backup으로 이동한 뒤 throw하면 target이 사라지고 backup만 남았다.
- replacement까지 target에 설치한 뒤 throw하면 실패했는데도 새 asset이 남았다.
- 기존 startup cleanup은 valid target 여부와 무관하게 backup을 삭제했다.

### GREEN / 변경

- commit throw catch가 expected UUID와 실제 asset validity를 확인한 valid backup을 old target으로 우선 복원한다.
- throw 시 새 target이 이미 있더라도 old backup을 우선하며, backup이 없으면 기존 target을 보존한다.
- startup recovery는 backup 파일명의 profile UUID/nonce 형식, symlink containment, profile UUID, 실제 PNG asset validity를 확인한다.
- valid target이 있을 때만 valid old backup을 정리한다.
- target이 없거나 invalid이고 backup이 valid하면 backup을 target으로 복구한다.
- invalid backup은 유일한 사본일 가능성을 고려해 삭제하지 않는다.
- invalid target은 valid backup 복구 전에 `.invalid-target-*`로 이동해 데이터를 보존한다.
- backup cleanup failure는 save 성공으로 처리하는 기존 정책을 유지한다.

### 테스트

- `TokenPetCharacterStoreTests`: target→backup 후 throw와 target→backup→replacement 설치 후 throw 모두 기존 asset의 byte-for-byte 복원을 검증했다.
- valid target/valid backup, missing target/valid backup, invalid target/valid backup, missing target/invalid backup의 startup recovery 분기를 검증했다.
- 기존 cleanup failure와 staging cleanup 테스트도 유지했다.

## 4. JPEG EXIF orientation 6/8 적용

### RED

- orientation metadata 6/8이 있는 80×40 JPEG가 모두 가로 aspect-fit으로 남았고 marker 위치도 동일했다.

### GREEN / 변경

- `CGImageSourceCreateThumbnailAtIndex`에 `kCGImageSourceCreateThumbnailWithTransform`을 적용해 EXIF 방향을 먼저 반영한다.
- 방향 적용 후의 CGImage 크기를 기준으로 기존 square aspect-fit과 PNG normalize를 수행한다.

### 테스트

- `TokenPetCoreTests`: orientation 6/8이 세로 content와 가로 margin을 만들고, upper-left marker가 각각 upper-right/lower-left로 이동하는지 검증했다.
- 기존 non-square JPEG, alpha PNG, 240×240 normalize 테스트를 유지했다.
- 밝은 source 영역이 background removal OFF에서 alpha 255, ON에서 alpha 0인지 추가 검증했다.

## 5. dirty selection/close 상태 전이

### RED

- 기존 `confirmDiscardIfNeeded()`가 replacement load 전에 `isDirty = false`로 변경했다.
- `reloadProfiles()`는 target load 실패를 무시하고 success를 반환했고, close controller는 cancel/reload 결과와 무관하게 창을 닫았다.
- failure-preserving 상태 전이를 검증할 순수 seam이 없었다.

### GREEN / 변경

- `confirmDiscardIfNeeded()`는 승인 여부만 반환하며 dirty state를 변경하지 않는다.
- `loadSelection`, `reloadProfiles`, `cancelChanges`가 성공 `Bool`을 반환한다.
- selection은 target load 성공 후에만 clean state로 전환하며 실패 시 기존 selected ID, draft, dirty state를 보존하고 오류를 표시한다.
- create 경로는 승인 후 새 dirty draft로 전환한다.
- close는 discard 승인 뒤 clean reload가 성공한 경우에만 허용하며, 실패 시 dirty draft와 창을 유지한다.
- `CharacterEditorStateTransitions` 순수 reducer seam을 추가했다.

### 테스트

- `TokenPetCoreTests`: switch target load failure가 기존 selected/draft/dirty를 보존하는지, close reload failure가 dirty를 보존하고 close를 거부하는지 검증했다.
- successful selection, create-new, successful clean close 분기도 함께 검증했다.

## 전체 검증

다음 명령을 구현 완료 상태에서 fresh run했고 모두 exit 0이었다.

```text
swift run TokenPetCoreTests
swift run TokenPetServiceTests
swift run TokenPetCharacterStoreTests
swift build --product TokenPet
./scripts/build_app.sh
./scripts/test_bundle.sh
git diff --check
```

- `TokenPetCoreTests`: `All TokenPetCore tests passed`
- `TokenPetServiceTests`: `All TokenPet service tests passed`
- `TokenPetCharacterStoreTests`: `PASS: TokenPetCharacterStoreTests`
- bundle: `TokenPet bundle verification passed`
- `img/5.png`: absent 상태 유지, 복원하지 않음

## 남은 우려 / Deferred

- 고해상도 이미지의 background 처리가 main actor에서 수행되는 성능 문제는 이번 데이터 안정성 범위 밖의 Minor로 deferred한다.
- 복구 시 보존한 `.invalid-target-*`와 invalid `.backup-*`는 자동 삭제하지 않으므로 장기간에는 수동 진단/정리 정책이 필요할 수 있다. 이는 유일한 사용자 asset 사본을 잃지 않기 위한 의도적인 선택이다.
- UI test backup과 실제 `Application Support` 사용자 데이터는 변경하지 않았다.
