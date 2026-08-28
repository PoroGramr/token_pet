<img width="610" height="121" alt="스크린샷 2026-08-28 오후 2 47 27" src="https://github.com/user-attachments/assets/8d8587dc-5929-4cf8-b1e0-88d39984f969" />

TokenPet is a resident macOS widget that shows the remaining percentage of your Claude Code five-hour usage window as an animated pixel character.

https://github.com/user-attachments/assets/867fb61e-efdd-41ae-a45e-e72488457d7f

## Requirements

- macOS 14 or later on Apple Silicon
- Claude Code CLI 2.x
- Swift 6.2 Command Line Tools (only when installing from source)

## Installation

### Homebrew

Register the TokenPet tap once, then install the cask.

```bash
brew tap PoroGramr/token_pet https://github.com/PoroGramr/token_pet.git
brew install --cask PoroGramr/token_pet/tokenpet
```

Update later with:

```bash
brew upgrade --cask tokenpet
```

### Install from source

```bash
./scripts/install.sh
```

The app is installed to `~/Applications/TokenPet.app` and opened automatically. If Claude Code is not signed in, right-click the character and choose **Sign in to Claude Code**. TokenPet only reads the Claude Code credentials needed to fetch usage; it never stores or modifies refresh tokens or Keychain items.

## Usage

- Drag the character to move the widget.
- Right-click it to refresh, reset its position, change or manage characters, sign in to Claude Code, configure launch at login, switch language, or quit.
- `72%` means 72% remains in the five-hour usage window.
- `!` means the last successful usage value is being shown because of a network error.

### Characters

Two built-in, read-only characters are included: **Battery** and **Mushroom**. You can tune each built-in character's percentage position and text size without changing its images or name.

To add your own character:

1. Right-click the widget and choose **Manage Characters…**.
2. Select **Add Character**, then choose three or four PNG, JPG, or JPEG frames.
3. Drag frames to set the animation order and optionally remove a light background.
4. Select each frame and drag `72%`, or enter X/Y values, to set its individual text position. Set the shared text size between 10 and 36 pt.
5. Select **Save & Apply**.

Custom-character source and display frames are stored in `~/Library/Application Support/TokenPet/Characters/`. They remain available after reinstalling or replacing `~/Applications/TokenPet.app`.

## Language

English is the default language for new installations. Use **Language** in the widget's context menu to switch between English and Korean. The selection is remembered across launches.

## Development

```bash
swift run TokenPetCoreTests
swift run TokenPetServiceTests
swift run TokenPetCharacterStoreTests
./scripts/build_app.sh
./scripts/test_bundle.sh
./scripts/package_dmg.sh
```

If credential errors persist, run `claude auth status` and then choose **Refresh** from the widget context menu.

This is an ad-hoc signed build intended for installation from source or the project's Homebrew tap. It is not Developer ID signed or notarized. Anthropic's OAuth usage endpoint is not a public API, so TokenPet may need updates when Claude Code changes.
