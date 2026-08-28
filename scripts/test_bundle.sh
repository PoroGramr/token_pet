#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$project_root/dist/TokenPet.app}"

test -d "$app_path"
test -x "$app_path/Contents/MacOS/TokenPet"
test -f "$app_path/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")" = "com.park.tokenpet"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_path/Contents/Info.plist")" = "true"

for frame in 1 2 3 4; do
    frame_path="$app_path/Contents/Resources/Frames/battery/$frame.png"
    test -f "$frame_path"
    test "$(sips -g pixelWidth "$frame_path" 2>/dev/null | tail -1 | awk '{print $2}')" = "240"
    test "$(sips -g pixelHeight "$frame_path" 2>/dev/null | tail -1 | awk '{print $2}')" = "240"
    test "$(sips -g hasAlpha "$frame_path" 2>/dev/null | tail -1 | awk '{print $2}')" = "yes"
done

test ! -e "$app_path/Contents/Resources/Frames/battery/5.png"

for frame in orange-mushroom-idle orange-mushroom-landing; do
    frame_path="$app_path/Contents/Resources/Frames/mushroom/$frame.png"
    test -f "$frame_path"
    test "$(sips -g pixelWidth "$frame_path" 2>/dev/null | tail -1 | awk '{print $2}')" = "240"
    test "$(sips -g pixelHeight "$frame_path" 2>/dev/null | tail -1 | awk '{print $2}')" = "240"
    test "$(sips -g hasAlpha "$frame_path" 2>/dev/null | tail -1 | awk '{print $2}')" = "yes"
done
test ! -e "$app_path/Contents/Resources/Frames/mushroom/orange-mushroom-airborne.png"

! cmp -s "$project_root/img/battery/2.png" "$app_path/Contents/Resources/Frames/battery/2.png"
! cmp -s "$project_root/img/battery/3.png" "$app_path/Contents/Resources/Frames/battery/3.png"

codesign --verify --deep --strict "$app_path"
echo "TokenPet bundle verification passed"
