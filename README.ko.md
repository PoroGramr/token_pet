<img width="610" height="121" alt="TokenPet" src="https://github.com/user-attachments/assets/8d8587dc-5929-4cf8-b1e0-88d39984f969" />

Claude Code 또는 Codex 사용량에서 남은 비율을 애니메이션 캐릭터로 표시하는 macOS 상주 위젯입니다.

[English README](README.md)

## 요구 사항

- macOS 14 이상, Apple Silicon Mac
- Claude Code CLI 2.x
- Swift 6.2 Command Line Tools (소스 설치 시)

## 설치

### Homebrew

처음 한 번 TokenPet tap을 등록한 뒤 설치합니다.

```bash
brew tap PoroGramr/token_pet https://github.com/PoroGramr/token_pet.git
brew install --cask PoroGramr/token_pet/tokenpet
```

업데이트는 다음 명령을 사용합니다.

```bash
brew upgrade --cask tokenpet
```

### 소스에서 설치

```bash
./scripts/install.sh
```

앱은 `~/Applications/TokenPet.app`에 설치되고 자동으로 실행됩니다. Claude Code에 로그인하지 않았다면 캐릭터를 우클릭한 뒤 `Claude Code 로그인`을 선택하세요. TokenPet은 사용량을 조회하는 데 필요한 Claude Code 인증 정보만 읽으며, refresh token이나 Keychain 항목을 저장·수정하지 않습니다.

## 사용법

- 드래그: 위젯 위치 이동
- 우클릭: 새로고침, 위치 초기화, 캐릭터 전환·관리, Claude Code 로그인, 로그인 시 실행, 언어 전환, 종료
- `72%`: 5시간 사용량 한도에서 72%가 남았다는 뜻
- `!`: 네트워크 오류로 마지막 정상 사용량을 표시 중이라는 뜻

### Codex 사용량

**사용량 제공자 → Codex**를 선택하세요. TokenPet이 로컬 Codex App Server를 통해 현재 ChatGPT Codex 한도를 자동으로 읽고 설정된 간격마다 갱신합니다. Codex CLI가 설치되어 있고 ChatGPT 계정으로 로그인되어 있어야 합니다.

### 캐릭터

기본 캐릭터 `배터리`, `버섯`이 포함됩니다. 기본 캐릭터의 이미지와 이름은 보호되지만, 프레임별 퍼센트 위치와 글자 크기는 직접 조절할 수 있습니다.

사용자 캐릭터를 추가하려면 다음 순서로 진행합니다.

1. 위젯을 우클릭하고 `캐릭터 관리…`를 선택합니다.
2. `새 캐릭터 추가`를 누른 뒤 PNG, JPG 또는 JPEG 이미지 3장이나 4장을 선택합니다.
3. 프레임을 드래그해 재생 순서를 바꾸고, 필요하면 밝은 배경을 제거합니다.
4. 각 프레임을 선택해 `72%`를 드래그하거나 X/Y 값을 입력하여 위치를 조정합니다. 글자 크기는 10~36pt에서 설정할 수 있습니다.
5. `저장 및 적용`을 누릅니다.

사용자 캐릭터 원본과 표시용 프레임은 `~/Library/Application Support/TokenPet/Characters/`에 저장됩니다. 앱을 다시 설치해도 이 데이터는 유지됩니다.

## 언어

새 설치의 기본 언어는 English입니다. 위젯 우클릭 메뉴의 `Language`에서 English와 한국어를 전환할 수 있으며, 선택값은 재실행 후에도 유지됩니다.

## 개발 검증

```bash
swift run TokenPetCoreTests
swift run TokenPetServiceTests
swift run TokenPetCharacterStoreTests
./scripts/build_app.sh
./scripts/test_bundle.sh
./scripts/package_dmg.sh
```

이 빌드는 개인 Mac에서 소스 또는 프로젝트 Homebrew tap으로 설치하는 용도의 ad-hoc 서명 앱입니다. Developer ID 서명과 notarization은 포함하지 않습니다. Anthropic의 OAuth 사용량 경로는 공개 API가 아니므로 Claude Code 변경에 따라 앱 업데이트가 필요할 수 있습니다.
