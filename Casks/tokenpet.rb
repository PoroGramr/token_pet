cask "tokenpet" do
  version "0.2.0"
  sha256 "2006a40fc33b0f2b03a1ae1d94e6628c777ff88bbf913188fd1bc2248676c50c"

  url "https://raw.githubusercontent.com/PoroGramr/token_pet/v#{version}/releases/TokenPet-#{version}.dmg"
  name "TokenPet"
  desc "Animated Claude Code and Codex usage token pet"
  homepage "https://github.com/PoroGramr/token_pet"

  depends_on macos: :sonoma

  app "TokenPet.app"

  zap trash: [
    "~/Library/Application Support/TokenPet",
    "~/Library/Preferences/com.park.tokenpet.plist",
  ]
end
