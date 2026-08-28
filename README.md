


# TokenPet

Claude Code의 5시간 사용량 한도에서 남은 비율을 애니메이션 캐릭터로 표시하는 macOS 상주 위젯입니다.

https://github.com/user-attachments/assets/867fb61e-efdd-41ae-a45e-e72488457d7f


## 요구 사항

- macOS 14 이상, Apple Silicon Mac
- Claude Code CLI 2.x
- Swift 6.2 Command Line Tools

## 설치

### Homebrew

처음 한 번 아래 명령으로 TokenPet tap을 등록한 뒤 설치합니다.

```bash
brew tap PoroGramr/token_pet https://github.com/PoroGramr/token_pet.git
brew install --cask PoroGramr/token_pet/tokenpet
```

이후 업데이트는 `brew upgrade --cask tokenpet`으로 할 수 있습니다. Homebrew용 DMG는 버전 태그에 포함됩니다.

### 소스에서 설치

```bash
./scripts/install.sh
```

앱은 `~/Applications/TokenPet.app`에 설치되고 자동으로 실행됩니다. 현재 Claude Code에 로그인하지 않았다면 캐릭터를 우클릭한 뒤 `Claude Code 로그인`을 선택하세요. 최초 Keychain 접근 시 macOS가 권한을 물으면 허용하세요. ad-hoc 재서명으로 직접 접근이 거부되면 Keychain ACL이 허용한 Apple의 `/usr/bin/security`를 읽기 전용 fallback으로 사용합니다. TokenPet은 Claude Code의 인증 정보를 읽기만 하며 refresh token이나 Keychain 항목을 수정하지 않습니다.

## 사용법

- 드래그: 위젯 위치 이동
- 우클릭: 새로고침, 위치 초기화, 캐릭터 전환·관리, Claude Code 로그인, 로그인 시 실행, 종료
- 표시: `72%`는 5시간 한도에서 72%가 남았다는 뜻입니다.
- `!`: 네트워크 오류로 마지막 정상 수치를 표시 중입니다.

### 캐릭터 추가 및 편집

1. 위젯을 우클릭하고 `캐릭터 관리…`를 선택합니다. 바로 위의 `캐릭터` 항목은 저장된 캐릭터를 전환하는 하위 메뉴입니다.
2. `새 캐릭터 추가`를 누른 뒤 PNG, JPG 또는 JPEG 이미지 3장이나 4장을 선택합니다.
3. 프레임을 드래그해 재생 순서를 바꾸고, 필요하면 `밝은 배경 제거`를 켭니다. 미리보기에서 3fps 왕복 애니메이션을 바로 확인할 수 있습니다.
4. 미리보기의 `72%`를 직접 드래그하거나 X/Y 값을 조정하고, 글자 크기를 10~36pt에서 설정합니다.
5. `저장 및 적용`을 누르면 캐릭터가 저장되고 실행 중인 위젯에 즉시 적용됩니다.

저장된 캐릭터는 우클릭 메뉴의 `캐릭터` 하위 메뉴에서 바로 전환할 수 있습니다. 기본 캐릭터는 항상 목록 첫 번째에 표시되는 읽기 전용 캐릭터로, 수정하거나 삭제할 수 없습니다.

사용자 캐릭터 원본과 표시용 프레임은 `~/Library/Application Support/TokenPet/Characters/`에 저장됩니다. `~/Applications/TokenPet.app`을 삭제하거나 앱을 다시 설치해도 이 사용자 데이터는 유지됩니다.

## 개발 검증

```bash
swift run TokenPetCoreTests
swift run TokenPetServiceTests
swift run TokenPetCharacterStoreTests
./scripts/build_app.sh
./scripts/test_bundle.sh
./scripts/package_dmg.sh
```

자격 증명 오류가 계속되면 먼저 `claude auth status`로 Claude Code 로그인 상태를 확인한 뒤 우클릭 메뉴의 `새로고침`을 누르세요.

이 빌드는 개인 Mac에서 소스로 설치하는 용도의 ad-hoc 서명 앱입니다. 외부 배포용 Developer ID 서명과 notarization은 포함하지 않습니다. Anthropic의 OAuth 사용량 경로는 공개 API가 아니므로 향후 Claude Code 변경에 따라 앱 업데이트가 필요할 수 있습니다.
