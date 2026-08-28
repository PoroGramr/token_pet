#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
dist_dir="$project_root/dist"
app_path="$dist_dir/TokenPet.app"
package_root="$dist_dir/TokenPet-package"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
dmg_path="$dist_dir/TokenPet-$version.dmg"

"$project_root/scripts/build_app.sh"
"$project_root/scripts/test_bundle.sh" "$app_path"

rm -rf "$package_root" "$dmg_path"
mkdir -p "$package_root"
ditto "$app_path" "$package_root/TokenPet.app"
ln -s /Applications "$package_root/Applications"

hdiutil create \
    -volname "TokenPet" \
    -srcfolder "$package_root" \
    -format UDZO \
    -ov \
    "$dmg_path" >/dev/null

rm -rf "$package_root"
echo "Created $dmg_path"
