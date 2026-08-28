import Foundation
import Combine

enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"

    var menuTitle: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    private static let defaultsKey = "appLanguage"
    private let defaults: UserDefaults

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .korean
    }

    func text(_ korean: String) -> String {
        guard language == .english else { return korean }
        return Self.english[korean] ?? korean
    }

    private static let english: [String: String] = [
        "사용량을 불러오는 중입니다": "Loading usage…",
        "마지막 정상 수치입니다": "Showing the last successful result",
        "최근 사용량입니다": "Latest usage",
        "Claude Code 로그인이 필요합니다": "Claude Code sign-in is required",
        "Mac 로그인 키체인이 잠겨 있습니다": "The Mac login keychain is locked",
        "Keychain 접근이 거부되었습니다": "Keychain access was denied",
        "Keychain 접근이 취소되었습니다": "Keychain access was cancelled",
        "Keychain 오류가 발생했습니다": "A Keychain error occurred",
        "Keychain 자격 증명 도구가 응답하지 않습니다": "The Keychain credential tool did not respond",
        "API 응답 형식이 변경되었습니다": "The API response format changed",
        "사용량 조회가 잠시 제한되었습니다": "Usage requests are temporarily rate-limited",
        "Anthropic 서버 오류가 발생했습니다": "An Anthropic server error occurred",
        "네트워크에 연결할 수 없습니다": "Could not connect to the network",
        "캐릭터 목록을 불러오지 못했습니다": "Could not load the character list",
        "선택한 캐릭터를 불러오지 못해 기본 캐릭터로 돌아갔습니다": "Could not load the selected character; switched to the default character",
        "선택한 캐릭터를 표시하지 못했습니다": "Could not display the selected character",
        "새로고침": "Refresh",
        "우측 하단으로 이동": "Move to bottom-right",
        "캐릭터": "Characters",
        "캐릭터 관리…": "Manage Characters…",
        "언어": "Language",
        "Claude Code 로그인": "Sign in to Claude Code",
        "Apple security fallback 허용": "Allow Apple security fallback",
        "로그인 시 실행": "Launch at login",
        "종료": "Quit",
        "캐릭터 선택 정보를 확인하지 못했습니다": "Could not read the character selection",
        "캐릭터를 불러오지 못했습니다. 기존 캐릭터를 계속 표시합니다": "Could not load the character. The current character will remain visible.",
        "로그인 시 실행 설정을 변경하지 못했습니다": "Could not change the launch-at-login setting",
        "Apple security fallback을 허용할까요?": "Allow Apple security fallback?",
        "TokenPet은 Apple의 /usr/bin/security를 사용해 Claude Code 인증 정보를 읽기만 합니다. 토큰은 저장하거나 로그에 남기지 않습니다.": "TokenPet uses Apple's /usr/bin/security only to read Claude Code credentials. Tokens are never saved or logged.",
        "허용": "Allow",
        "취소": "Cancel",
        "Terminal에서 Claude 로그인을 시작하지 못했습니다": "Could not start Claude sign-in in Terminal",
        "로그인 시 실행을 자동 등록하지 못했습니다": "Could not automatically enable launch at login",
        "TokenPet 캐릭터 관리": "TokenPet Character Manager",
        "저장하지 않은 변경을 버릴까요?": "Discard unsaved changes?",
        "편집한 이미지와 설정은 저장되지 않습니다.": "Your edited images and settings will not be saved.",
        "변경 버리기": "Discard Changes",
        "계속 편집": "Keep Editing",
        "캐릭터 프레임 선택": "Choose Character Frames",
        "가져오기": "Import",
        "이미지는 한 번에 3장 또는 4장을 선택해 주세요.": "Choose exactly 3 or 4 images at a time.",
        "선택한 이미지를 읽거나 처리하지 못했습니다. PNG/JPG 파일을 확인해 주세요.": "Could not read or process the selected images. Check the PNG/JPG files.",
        "배경 제거 설정을 적용하지 못했습니다. 기존 이미지는 유지됩니다.": "Could not apply background removal. Existing images were kept.",
        "이미지를 다시 처리하지 못했습니다. 기존 이미지는 유지됩니다.": "Could not reprocess the images. Existing images were kept.",
        "표시할 수 없는 이미지가 있어 저장하지 않았습니다. 기존 캐릭터는 그대로 유지됩니다.": "The character was not saved because one or more images cannot be displayed. The existing character was kept.",
        "캐릭터를 저장하지 못했습니다. 기존 캐릭터는 그대로 유지됩니다.": "Could not save the character. The existing character was kept.",
        "캐릭터는 저장하고 적용했지만 목록을 새로 불러오지 못했습니다.": "The character was saved and applied, but the list could not be refreshed.",
        "캐릭터를 삭제하지 못했습니다.": "Could not delete the character.",
        "캐릭터 목록을 불러오지 못했습니다. 기존 선택은 유지됩니다.": "Could not load the character list. The current selection was kept.",
        "캐릭터 데이터를 불러오지 못했습니다. 기존 편집 상태를 유지합니다.": "Could not load character data. The current editing state was kept.",
        "캐릭터 이름은 1~40자로 입력해 주세요.": "Character names must be 1 to 40 characters.",
        "같은 이름의 캐릭터가 이미 있습니다.": "A character with that name already exists.",
        "정상적인 이미지 3장 또는 4장이 필요합니다.": "Exactly 3 or 4 valid images are required.",
        "글자 크기는 10~36pt로 설정해 주세요.": "Text size must be between 10 and 36 pt.",
        "입력 내용을 확인해 주세요.": "Check the entered values.",
        "기본 캐릭터": "Default Character",
        "배터리": "Battery",
        "버섯": "Mushroom",
        "기본 · 읽기 전용": "Default · Read-only",
        "기본 캐릭터는 읽기 전용입니다.\n새 캐릭터를 추가하거나 왼쪽 목록에서 편집할 캐릭터를 선택하세요.": "The default character is read-only.\nAdd a character or choose one from the list to edit.",
        "새 캐릭터": "New Character",
        "새 캐릭터 추가": "Add Character",
        "캐릭터 설정": "Character Settings",
        "캐릭터 이름": "Character Name",
        "애니메이션 프레임": "Animation Frames",
        "PNG/JPG 이미지 3장 또는 4장을 선택하고 드래그해 순서를 바꾸세요.": "Choose 3 or 4 PNG/JPG images, then drag to reorder them.",
        "이미지 선택…": "Choose Images…",
        "밝은 배경 제거": "Remove light background",
        "프레임": "Frame",
        "위치 편집": "Position Editor",
        "좌표": "Coordinates",
        "글자 크기": "Text Size",
        "선택한 이미지에서 72%를 드래그하세요.": "Drag 72% on the selected image.",
        "전체 애니메이션": "Full Animation",
        "각 이미지의 위치가 3fps 왕복 재생에 적용됩니다.": "Each image's position is used during 3 fps ping-pong playback.",
        "미리보기와 위젯은 같은 위치 계산, 글꼴, 색상과 외곽선을 사용합니다.": "The preview and widget use the same position calculation, font, color, and outline.",
        "캐릭터 삭제": "Delete Character",
        "저장 및 적용": "Save & Apply",
        "이 캐릭터를 삭제할까요?": "Delete this character?",
        "삭제": "Delete",
        "저장된 이미지와 설정이 함께 삭제되며 되돌릴 수 없습니다.": "Saved images and settings will be deleted and cannot be restored."
    ]
}
