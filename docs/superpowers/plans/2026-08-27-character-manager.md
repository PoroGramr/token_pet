# TokenPet Character Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이미지 3~4장을 캐릭터로 등록하고 여러 캐릭터를 전환하며, 실제 애니메이션 미리보기에서 퍼센트 위치와 글자 크기를 편집하는 macOS 관리 창을 구현한다.

**Architecture:** `TokenPetCore`에 캐릭터 프로필, 프레임 처리, 원자적 파일 저장소와 좌표 계산을 둔다. AppKit 실행 타깃은 SwiftUI 기반 관리 창을 열고, 기존 `PetView`와 동일한 렌더링 모델을 사용해 미리보기와 위젯을 일치시킨다. 선택 변경은 `CharacterRepository`를 통해 즉시 위젯과 우클릭 메뉴에 반영한다.

**Tech Stack:** Swift 6.2, Swift Package Manager, AppKit, SwiftUI, CoreGraphics, ImageIO, UniformTypeIdentifiers

**Spec:** `docs/superpowers/specs/2026-08-27-character-manager-design.md`

## Global Constraints

- macOS 14 이상, Apple Silicon, 외부 패키지 의존성 없음.
- 사용자 입력은 PNG, JPG, JPEG 정확히 3장 또는 4장.
- 사용자 애니메이션은 3fps 왕복 재생, 기본 번들 캐릭터는 4프레임 `[1,2,3,4,3,2]`로 재생.
- 저장 프레임은 240×240 PNG, 위젯은 120×120pt.
- 퍼센트 위치는 0~1 정규화 좌표, 글자 크기는 10~36pt.
- 사용자 데이터 루트는 `~/Library/Application Support/TokenPet/Characters`.
- 기본 캐릭터는 읽기 전용이며 삭제할 수 없음.
- 이미지 처리·저장 실패 시 기존 프로필과 실행 중 캐릭터를 보존.

---

## File Structure

- Create `Sources/TokenPetCore/CharacterProfile.swift`: 프로필 모델, 검증, 왕복 순서, 퍼센트 레이아웃 계산.
- Modify `Sources/TokenPetCore/FrameImageProcessor.swift`: 배경 제거 전 정규화와 선택적 밝은 배경 제거.
- Create `Sources/TokenPetCore/CharacterStore.swift`: 사용자 프로필 CRUD, 원자적 디렉터리 교체, 선택 ID.
- Create `Sources/TokenPet/CharacterRepository.swift`: 번들 기본 캐릭터와 사용자 캐릭터를 런타임 `NSImage` 모델로 변환.
- Modify `Sources/TokenPet/PetView.swift`: 고정 번들 프레임 대신 동적 캐릭터와 공유 퍼센트 레이아웃 렌더링.
- Create `Sources/TokenPet/CharacterManagerModel.swift`: 편집 세션 상태, 검증, 가져오기, 순서 변경, 저장·삭제.
- Create `Sources/TokenPet/CharacterManagerView.swift`: SwiftUI 관리 창, 프레임 목록, 미리보기 드래그 편집.
- Create `Sources/TokenPet/CharacterEditorWindowController.swift`: SwiftUI 관리 창의 AppKit 생명주기.
- Modify `Sources/TokenPet/PetPanelController.swift`: 캐릭터 선택 하위 메뉴와 관리 창 열기.
- Modify `Sources/TokenPet/AppDelegate.swift`: 저장소 주입과 즉시 런타임 갱신.
- Modify `Tests/TokenPetCoreTests/main.swift`: 프로필·좌표·이미지 처리 단위 테스트.
- Create `Tests/TokenPetCharacterStoreTests/main.swift`: 임시 루트 기반 저장소 통합 테스트.
- Modify `Package.swift`: 저장소 테스트 실행 타깃 추가.
- Modify `README.md`: 캐릭터 등록·전환 사용법과 저장 위치.

### Task 1: Character profile, animation, and percent layout

**Files:**
- Create: `Sources/TokenPetCore/CharacterProfile.swift`
- Modify: `Sources/TokenPetCore/FrameImageProcessor.swift`
- Modify: `Tests/TokenPetCoreTests/main.swift`

**Interfaces:**
- Produces: `CharacterProfile`, `NormalizedPoint`, `CharacterProfileValidator.validate(_:existingNames:)`, `FrameSequence.indices(frameCount:)`, `PercentLayout.origin(...)`.
- Consumes: 기존 `FrameImageProcessor`, `FrameSequence.framesPerSecond`.

- [ ] **Step 1: Write failing profile and layout tests**

```swift
let threeFrame = CharacterProfile(
    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    name: "Cat",
    frameCount: 3,
    frameOrder: [0, 1, 2],
    removesLightBackground: false,
    percentPosition: NormalizedPoint(x: 0.5, y: 0.58),
    percentFontSize: 22,
    framesPerSecond: 3,
    schemaVersion: 1
)
runner.expectEqual(FrameSequence.indices(frameCount: 3), [0, 1, 2, 1], "3-frame ping-pong")
runner.expectEqual(FrameSequence.indices(frameCount: 4), [0, 1, 2, 3, 2, 1], "4-frame ping-pong")
runner.expectEqual(try JSONDecoder().decode(CharacterProfile.self, from: JSONEncoder().encode(threeFrame)), threeFrame, "profile round trip")
runner.expectEqual(PercentLayout.clampedPosition(NormalizedPoint(x: 2, y: -1)), NormalizedPoint(x: 1, y: 0), "position clamp")
```

- [ ] **Step 2: Run the core runner and confirm RED**

Run: `swift run TokenPetCoreTests`

Expected: compilation fails because `CharacterProfile`, `NormalizedPoint`, and the new `FrameSequence` overload do not exist.

- [ ] **Step 3: Implement the profile contracts**

```swift
public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
}

public struct CharacterProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var frameCount: Int
    public var frameOrder: [Int]
    public var removesLightBackground: Bool
    public var percentPosition: NormalizedPoint
    public var percentFontSize: Double
    public var framesPerSecond: Int
    public var schemaVersion: Int
}

public enum FrameSequence {
    public static let framesPerSecond = 3
    public static func indices(frameCount: Int) -> [Int] {
        guard frameCount > 1 else { return Array(0..<max(0, frameCount)) }
        return Array(0..<frameCount) + Array(stride(from: frameCount - 2, through: 1, by: -1))
    }
}
```

Validation must reject names outside 1...40 trimmed characters, duplicate case-insensitive names, user frame counts outside 3...4, non-permutations in `frameOrder`, positions outside 0...1, font sizes outside 10...36, FPS other than 3, and schema versions other than 1.

- [ ] **Step 4: Run tests and confirm GREEN**

Run: `swift run TokenPetCoreTests`

Expected: all existing and new profile/layout tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TokenPetCore/CharacterProfile.swift Sources/TokenPetCore/FrameImageProcessor.swift Tests/TokenPetCoreTests/main.swift
git commit -m "feat: add character profile model"
```

### Task 2: Reversible frame processing

**Files:**
- Modify: `Sources/TokenPetCore/FrameImageProcessor.swift`
- Modify: `Tests/TokenPetCoreTests/main.swift`

**Interfaces:**
- Produces: `FrameImageProcessor.makeNormalizedSourcePNG(from:pixelSize:)` and `makeDisplayPNG(fromNormalizedSource:removingLightBackground:)`.
- Consumes: `FrameImageProcessor.makeTransparentImage(from:)` and the existing connected-edge background algorithm.

- [ ] **Step 1: Write failing reversible-processing tests**

```swift
func decodePNG(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw FrameImageError.invalidImage
    }
    return image
}

let opaqueInput = try Data(contentsOf: URL(fileURLWithPath: "img/2.png"))
let source = try FrameImageProcessor.makeNormalizedSourcePNG(from: opaqueInput, pixelSize: 240)
let preserved = try FrameImageProcessor.makeDisplayPNG(fromNormalizedSource: source, removingLightBackground: false)
let removed = try FrameImageProcessor.makeDisplayPNG(fromNormalizedSource: source, removingLightBackground: true)
runner.expectEqual(alphaValue(in: try decodePNG(preserved), x: 0, y: 0), 255, "background preserved")
runner.expectEqual(alphaValue(in: try decodePNG(removed), x: 0, y: 0), 0, "background removed")
```

- [ ] **Step 2: Run tests and confirm RED**

Run: `swift run TokenPetCoreTests`

Expected: compilation fails because the two new processing methods do not exist.

- [ ] **Step 3: Split normalization from optional background removal**

`makeNormalizedSourcePNG` must decode PNG/JPEG, aspect-fit onto a 240×240 canvas, preserve the source alpha/background, and encode PNG. `makeDisplayPNG` must decode the normalized source, optionally run `removeConnectedBackground`, and encode PNG without scaling again. Keep `makeNormalizedPNG` as a compatibility wrapper that calls both methods with removal enabled for build-time bundled frames.

- [ ] **Step 4: Run tests and confirm GREEN**

Run: `swift run TokenPetCoreTests`

Expected: preserved and removed outputs differ as asserted; all prior image tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/TokenPetCore/FrameImageProcessor.swift Tests/TokenPetCoreTests/main.swift
git commit -m "feat: add reversible character frame processing"
```

### Task 3: Atomic character store

**Files:**
- Create: `Sources/TokenPetCore/CharacterStore.swift`
- Create: `Tests/TokenPetCharacterStoreTests/main.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `CharacterProfile`, `CharacterProfileValidator`, normalized source and display PNG data.
- Produces: `CharacterAssets`, `CharacterStore.list()`, `load(id:)`, `save(_:)`, `delete(id:)`, `selectedCharacterID`, and `CharacterStoreError`.

- [ ] **Step 1: Add the test executable target and failing store test**

```swift
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let defaults = UserDefaults(suiteName: "TokenPetCharacterStoreTests-\(UUID())")!
let store = CharacterStore(rootURL: root, defaults: defaults)
let assets = CharacterAssets(profile: profile, sources: [png, png, png], frames: [png, png, png])
try store.save(assets)
runner.expectEqual(try store.list().map(\.id), [profile.id], "saved profile listed")
runner.expectEqual(try store.load(id: profile.id), assets, "saved assets load")
store.selectedCharacterID = profile.id
try store.delete(id: profile.id)
runner.expectEqual(store.selectedCharacterID, nil, "deleting selected profile clears selection")
```

Add to `Package.swift`:

```swift
.executable(name: "TokenPetCharacterStoreTests", targets: ["TokenPetCharacterStoreTests"]),
.executableTarget(
    name: "TokenPetCharacterStoreTests",
    dependencies: ["TokenPetCore"],
    path: "Tests/TokenPetCharacterStoreTests"
)
```

- [ ] **Step 2: Run and confirm RED**

Run: `swift run TokenPetCharacterStoreTests`

Expected: compilation fails because `CharacterStore` and `CharacterAssets` do not exist.

- [ ] **Step 3: Implement atomic CRUD and corruption fallback**

```swift
public struct CharacterAssets: Equatable, Sendable {
    public var profile: CharacterProfile
    public var sources: [Data]
    public var frames: [Data]
}

public final class CharacterStore: @unchecked Sendable {
    public init(rootURL: URL, defaults: UserDefaults)
    public func list() throws -> [CharacterProfile]
    public func load(id: UUID) throws -> CharacterAssets
    public func save(_ assets: CharacterAssets) throws
    public func delete(id: UUID) throws
    public var selectedCharacterID: UUID? { get set }
}
```

`save` must validate the profile and exact source/frame counts, write `profile.json`, `source-N.png`, and `frame-N.png` to a UUID-named staging directory, read the staging directory back for verification, move the existing directory to a backup, move staging to the target, and remove backup only after success. Any failure restores backup. `list` skips malformed JSON, unsupported schema, invalid frame counts, and missing required files. `delete` rejects the reserved built-in UUID.

- [ ] **Step 4: Extend tests for failed replacement and corrupt profiles**

Create a malformed profile directory and assert `list()` skips it. Attempt a save with mismatched frame counts and assert the previously loaded assets are unchanged.

- [ ] **Step 5: Run and confirm GREEN**

Run: `swift run TokenPetCharacterStoreTests`

Expected: CRUD, rollback, selected-ID clearing, and corrupt-profile tests all pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/TokenPetCore/CharacterStore.swift Tests/TokenPetCharacterStoreTests/main.swift
git commit -m "feat: add atomic character store"
```

### Task 4: Dynamic runtime character rendering

**Files:**
- Create: `Sources/TokenPet/CharacterRepository.swift`
- Modify: `Sources/TokenPet/PetView.swift`
- Modify: `Sources/TokenPet/PetPanelController.swift`
- Modify: `Sources/TokenPet/AppDelegate.swift`
- Modify: `Tests/TokenPetCoreTests/main.swift`

**Interfaces:**
- Consumes: `CharacterStore`, `CharacterProfile`, `FrameSequence.indices(frameCount:)`, `PercentLayout`.
- Produces: `RuntimeCharacter`, `CharacterRepository.availableCharacters()`, `select(id:)`, `selectedCharacter()`, and `PetView.apply(character:)`.

- [ ] **Step 1: Write failing shared-render-model tests**

Test that `PercentLayout.textRect(containerSize:position:fontSize:measuredTextSize:)` returns a centered and clamped rect for representative positions and 10pt/36pt fonts. Verify a 3-frame profile expands to `[0,1,2,1]` while the built-in 4-frame profile expands to `[0,1,2,3,2,1]`.

- [ ] **Step 2: Run and confirm RED**

Run: `swift run TokenPetCoreTests`

Expected: the new measured-text layout API does not exist.

- [ ] **Step 3: Implement repository and dynamic `PetView`**

```swift
struct RuntimeCharacter {
    let profile: CharacterProfile
    let frames: [NSImage]
    let playbackIndices: [Int]
}

@MainActor
final class CharacterRepository {
    static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    func availableCharacters() -> [CharacterProfile]
    func selectedCharacter() -> RuntimeCharacter
    func select(id: UUID?) throws -> RuntimeCharacter
}
```

Refactor `PetView` so it no longer calls `loadFrames()` in its initializer. `apply(character:)` replaces frames, playback indices, normalized position and font size, resets the frame index, restarts the timer if necessary, and redraws. Both runtime and editor must call `PercentLayout.textRect` using `NSString.size(withAttributes:)` for measured text bounds.

- [ ] **Step 4: Wire the built-in character and launch fallback**

`AppDelegate` constructs the Application Support root and `CharacterRepository`; `PetPanelController` receives the repository and applies `selectedCharacter()` during initialization. Missing or corrupt selected user data must reset selection to built-in without terminating the app.

- [ ] **Step 5: Run regression tests and build**

Run:

```bash
swift run TokenPetCoreTests
swift run TokenPetServiceTests
swift build --product TokenPet
```

Expected: all runners pass and the app compiles.

- [ ] **Step 6: Commit**

```bash
git add Sources/TokenPet/CharacterRepository.swift Sources/TokenPet/PetView.swift Sources/TokenPet/PetPanelController.swift Sources/TokenPet/AppDelegate.swift Sources/TokenPetCore/CharacterProfile.swift Tests/TokenPetCoreTests/main.swift
git commit -m "feat: render selected character dynamically"
```

### Task 5: Character manager editor window

**Files:**
- Create: `Sources/TokenPet/CharacterManagerModel.swift`
- Create: `Sources/TokenPet/CharacterManagerView.swift`
- Create: `Sources/TokenPet/CharacterEditorWindowController.swift`
- Modify: `Sources/TokenPet/PetPanelController.swift`
- Modify: `Sources/TokenPet/AppDelegate.swift`

**Interfaces:**
- Consumes: `CharacterRepository`, `CharacterStore`, `FrameImageProcessor`, `CharacterProfileValidator`, shared percent layout.
- Produces: `CharacterManagerModel`, SwiftUI `CharacterManagerView`, and `CharacterEditorWindowController.show()`.

- [ ] **Step 1: Add model tests to the character-store runner**

Move pure draft validation and reorder logic to core `CharacterDraft`:

```swift
var draft = CharacterDraft.new(name: "Cat", sourceFrames: [a, b, c])
draft.moveFrame(from: 0, to: 2)
runner.expectEqual(draft.sourceFrames, [b, c, a], "drag reorder")
runner.expectEqual(draft.validation(existingNames: []).isValid, true, "valid 3-frame draft")
runner.expectEqual(CharacterDraft.new(name: "", sourceFrames: [a, b]).validation(existingNames: []).isValid, false, "invalid draft")
```

- [ ] **Step 2: Run and confirm RED**

Run: `swift run TokenPetCharacterStoreTests`

Expected: compilation fails because `CharacterDraft` does not exist.

- [ ] **Step 3: Implement `CharacterManagerModel`**

```swift
@MainActor
final class CharacterManagerModel: ObservableObject {
    @Published var profiles: [CharacterProfile] = []
    @Published var selectedID: UUID?
    @Published var draft: CharacterDraft?
    @Published var errorMessage: String?
    @Published var isDirty = false

    func createCharacter()
    func importFrames()
    func moveFrame(from: Int, to: Int)
    func rebuildDisplayFrames()
    func saveAndApply()
    func deleteSelected()
}
```

`importFrames()` uses `NSOpenPanel` with `allowedContentTypes = [.png, .jpeg]`, `allowsMultipleSelection = true`, validates 3...4 selections, reads all data immediately, and never stores external paths or security-scoped bookmarks. Processing errors set `errorMessage` and preserve the old draft.

- [ ] **Step 4: Implement the SwiftUI window**

Use a `NavigationSplitView` or `HSplitView` with a 220pt character list and flexible editor. The editor must include four frame tiles, `onDrag`/`onDrop` reorder, background-removal toggle, `TimelineView(.animation(minimumInterval: 1/3))` preview, draggable `72%`, X/Y numeric fields, 10...36pt font-size control, inline validation message, delete/cancel/save-and-apply buttons. The delete button presents a destructive confirmation dialog before calling `deleteSelected()`. Window minimum size is 900×650.

`CharacterEditorWindowController` owns one `NSWindow` with `NSHostingController(rootView:)`, reuses it across menu openings, and confirms discarding dirty changes before closing or switching characters.

- [ ] **Step 5: Build and manually exercise the editor**

Run: `swift build --product TokenPet`

Expected: build passes. Open the app, register 3 PNG/JPG images, observe `[1,2,3,2]` animation, drag `72%`, toggle background removal, save, and confirm the widget changes without restart.

- [ ] **Step 6: Commit**

```bash
git add Sources/TokenPet/CharacterManagerModel.swift Sources/TokenPet/CharacterManagerView.swift Sources/TokenPet/CharacterEditorWindowController.swift Sources/TokenPet/PetPanelController.swift Sources/TokenPet/AppDelegate.swift Sources/TokenPetCore/CharacterProfile.swift Tests/TokenPetCharacterStoreTests/main.swift
git commit -m "feat: add character manager editor"
```

### Task 6: Character menu, persistence verification, and documentation

**Files:**
- Modify: `Sources/TokenPet/PetPanelController.swift`
- Modify: `Sources/TokenPet/AppDelegate.swift`
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-08-27-character-manager.md`

**Interfaces:**
- Consumes: all prior task APIs.
- Produces: live right-click character submenu, complete installed feature, verification evidence.

- [ ] **Step 1: Add the live character submenu**

Create a `캐릭터` menu item whose submenu is rebuilt in `menuWillOpen`. Each valid profile appears with a checkmark for the selected ID; choosing it calls `repository.select(id:)`, `petView.apply(character:)`, and persists selection. Add `캐릭터 관리…` below the submenu. The built-in character always appears first.

- [ ] **Step 2: Document usage and data location**

README must describe: open manager from right-click, select 3...4 PNG/JPG images, reorder frames, optional light-background removal, drag percent, save/apply, switch characters, and storage under Application Support. State that deleting the app does not delete user characters.

- [ ] **Step 3: Run full automated verification**

Run:

```bash
swift run TokenPetCoreTests
swift run TokenPetServiceTests
swift run TokenPetCharacterStoreTests
./scripts/build_app.sh
./scripts/test_bundle.sh
git diff --check
```

Expected: every command exits 0 with no test failures or bundle/signature errors.

- [ ] **Step 4: Install and verify actual behavior**

Run:

```bash
./scripts/install.sh
codesign --verify --deep --strict ~/Applications/TokenPet.app
```

Manually verify: register a 3-frame character, preview moves, percent drag is reflected in widget, right-click switching works, relaunch preserves selection, deleting selected custom character returns to built-in, Claude usage percentage still refreshes.

- [ ] **Step 5: Request code review and resolve Critical/Important findings**

Review must specifically inspect atomic replacement rollback, user-file handling, corrupt-profile fallback, SwiftUI/AppKit lifecycle, drag coordinate conversion, and regressions in Keychain/usage refresh behavior.

- [ ] **Step 6: Commit final integration**

```bash
git add README.md Sources Tests Package.swift docs/superpowers/plans/2026-08-27-character-manager.md
git commit -m "feat: add custom character management"
```
