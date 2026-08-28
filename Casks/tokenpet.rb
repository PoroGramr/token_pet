cask "tokenpet" do
  version "0.1.1"
  sha256 "5714d5a047cd836eb7596136a853fed73c5ba41bc601245029aec03a27be766a"

  url "https://raw.githubusercontent.com/PoroGramr/token_pet/v#{version}/releases/TokenPet-#{version}.dmg"
  name "TokenPet"
  desc "Animated Claude Code usage token pet"
  homepage "https://github.com/PoroGramr/token_pet"

  depends_on macos: :sonoma

  app "TokenPet.app"

  zap trash: [
    "~/Library/Application Support/TokenPet",
    "~/Library/Preferences/com.park.tokenpet.plist",
  ]
end
