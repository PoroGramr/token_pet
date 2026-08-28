#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
dist_dir="$project_root/dist"
app_path="$dist_dir/TokenPet.app"
staging_path="$dist_dir/TokenPet.app.staging"
iconset_path="$project_root/.build/TokenPet.iconset"

cd "$project_root"
swift build -c release --product TokenPet
swift build -c release --product TokenPetFramePrep
binary_dir="$(swift build -c release --show-bin-path)"

rm -rf "$staging_path"
mkdir -p "$staging_path/Contents/MacOS"
mkdir -p "$staging_path/Contents/Resources/Frames"
cp "$binary_dir/TokenPet" "$staging_path/Contents/MacOS/TokenPet"
cp "$project_root/Resources/Info.plist" "$staging_path/Contents/Info.plist"
"$binary_dir/TokenPetFramePrep" "$project_root/img" "$staging_path/Contents/Resources/Frames"

rm -rf "$iconset_path"
mkdir -p "$iconset_path"
for specification in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    size="${specification%% *}"
    filename="${specification#* }"
    sips -z "$size" "$size" "$project_root/img/battery/4.png" --out "$iconset_path/$filename" >/dev/null
done
iconutil -c icns "$iconset_path" -o "$staging_path/Contents/Resources/TokenPet.icns"

codesign --force --deep --sign - "$staging_path"
rm -rf "$app_path"
mv "$staging_path" "$app_path"
echo "Built $app_path"
