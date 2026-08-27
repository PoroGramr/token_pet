# TokenPet

Claude Code의 5시간 사용량 한도에서 남은 비율을 애니메이션 캐릭터로 표시하는 macOS 상주 위젯입니다.

## 요구 사항

- macOS 14 이상, Apple Silicon Mac
- Claude Code CLI 2.x
- Swift 6.2 Command Line Tools

## 설치

```bash
./scripts/install.sh
```

앱은 `~/Applications/TokenPet.app`에 설치되고 자동으로 실행됩니다. 현재 Claude Code에 로그인하지 않았다면 캐릭터를 우클릭한 뒤 `Claude Code 로그인`을 선택하세요. 최초 Keychain 접근 시 macOS가 권한을 물으면 허용하세요. ad-hoc 재서명으로 직접 접근이 거부되면 Keychain ACL이 허용한 Apple의 `/usr/bin/security`를 읽기 전용 fallback으로 사용합니다. TokenPet은 Claude Code의 인증 정보를 읽기만 하며 refresh token이나 Keychain 항목을 수정하지 않습니다.

## 사용법

- 드래그: 위젯 위치 이동
- 우클릭: 새로고침, 위치 초기화, Claude Code 로그인, 로그인 시 실행, 종료
- 표시: `72%`는 5시간 한도에서 72%가 남았다는 뜻입니다.
- `!`: 네트워크 오류로 마지막 정상 수치를 표시 중입니다.

## 개발 검증

```bash
swift run TokenPetCoreTests
swift run TokenPetServiceTests
./scripts/build_app.sh
./scripts/test_bundle.sh
```

자격 증명 오류가 계속되면 먼저 `claude auth status`로 Claude Code 로그인 상태를 확인한 뒤 우클릭 메뉴의 `새로고침`을 누르세요.

이 빌드는 개인 Mac에서 소스로 설치하는 용도의 ad-hoc 서명 앱입니다. 외부 배포용 Developer ID 서명과 notarization은 포함하지 않습니다. Anthropic의 OAuth 사용량 경로는 공개 API가 아니므로 향후 Claude Code 변경에 따라 앱 업데이트가 필요할 수 있습니다.
