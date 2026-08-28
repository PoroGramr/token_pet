cask "tokenpet" do
  version "0.1.0"
  sha256 "b0789c7af4ea7275483b7e39cfd41564d7688347ac43445753ba60b9ff535d4f"

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
