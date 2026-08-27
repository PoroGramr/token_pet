#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$project_root/dist/TokenPet.app"
applications_dir="$HOME/Applications"
target_app="$applications_dir/TokenPet.app"
target_executable="$target_app/Contents/MacOS/TokenPet"
staging_app="$applications_dir/TokenPet.app.installing"
previous_app="$applications_dir/TokenPet.app.previous"
replacement_started=false
transaction_committed=false
rollback_finished=false

running_tokenpet_pids() {
    ps -axo pid=,command= | awk -v executable="$target_executable" '$2 == executable && NF == 2 {print $1}'
}

rollback() {
    [[ "$rollback_finished" == true ]] && return
    rollback_finished=true
    trap - EXIT INT TERM
    rm -rf "$staging_app"
    if [[ "$transaction_committed" == true ]]; then
        rm -rf "$previous_app"
    elif [[ -d "$previous_app" ]]; then
        replacement_started=false
        rm -rf "$target_app"
        mv "$previous_app" "$target_app"
        open "$target_app" >/dev/null 2>&1 || true
    elif [[ "$replacement_started" == true ]]; then
        replacement_started=false
        rm -rf "$target_app"
    fi
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$project_root/scripts/build_app.sh"
mkdir -p "$applications_dir"

for pid in ${(f)"$(running_tokenpet_pids)"}; do
    kill -TERM "$pid"
done
for _ in {1..50}; do
    [[ -z "$(running_tokenpet_pids)" ]] && break
    sleep 0.1
done
if [[ -n "$(running_tokenpet_pids)" ]]; then
    echo "TokenPet did not terminate; installation stopped" >&2
    exit 1
fi

rm -rf "$staging_app" "$previous_app"
ditto "$source_app" "$staging_app"
codesign --verify --deep --strict "$staging_app"

if [[ -d "$target_app" ]]; then
    mv "$target_app" "$previous_app"
fi
replacement_started=true
mv "$staging_app" "$target_app"
codesign --verify --deep --strict "$target_app"
open "$target_app"

for _ in {1..50}; do
    [[ -n "$(running_tokenpet_pids)" ]] && break
    sleep 0.1
done
if [[ -z "$(running_tokenpet_pids)" ]]; then
    echo "New TokenPet process did not start; restoring previous app" >&2
    exit 1
fi

transaction_committed=true
replacement_started=false
rm -rf "$previous_app"
trap - EXIT INT TERM
echo "Installed and opened $target_app"
