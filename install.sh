#!/bin/bash
# Downloads and verifies the Haide release, replaces the app, and opens it.
# Haide's settings and sessions in ~/.haide are preserved.
set -euo pipefail

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

app_running() {
  local processes status command_line pid command
  local executable='/Haide\.app/Contents/MacOS/Haide([[:space:]]|$)'
  local app_command='^/(.*/)?Haide\.app/Contents/MacOS/Haide$'
  local node_entry='/out/main/[^[:space:]]+\.js([[:space:]]|$)'
  if processes=$(pgrep -afl "$executable"); then
    while IFS= read -r command_line; do
      pid=${command_line%%[[:space:]]*}
      command=$(ps -p "$pid" -o comm=) || continue
      # Electron-as-Node daemons and helpers may use the same executable with a JS entrypoint.
      if [[ "$command" =~ $app_command && ! "$command_line" =~ $node_entry ]]; then
        running_bundle=${command%/Contents/MacOS/Haide}
        return 0
      fi
    done <<< "$processes"
    return 1
  else
    status=$?
    [[ "$status" -eq 1 ]] || fail '실행 중인 Haide 프로세스를 확인할 수 없습니다.'
    return 1
  fi
}

request_quit() {
  app_running || return 0
  reopen_on_failure="$running_bundle"
  if osascript -e 'tell application id "io.github.kimsh8337.haide" to quit'; then
    quit_requested=1
  else
    printf '%s\n' 'Haide를 직접 종료(⌘Q)하면 설치를 계속합니다'
  fi
}

stop_if_cancelled() {
  if [[ -n "${HAIDE_READY_FILE:-}" && -f "$HAIDE_READY_FILE.cancelled" &&
        ! -L "$HAIDE_READY_FILE.cancelled" ]]; then
    printf '%s\n' '설치를 취소했습니다.'
    exit 0
  fi
}

wait_for_haide() {
  local quit_requested=0 answer
  if [[ -n "${HAIDE_READY_FILE:-}" ]]; then
    app_running || true
    # Publish atomically without opening or replacing the destination.
    local signal
    signal=$(mktemp "${HAIDE_READY_FILE}.XXXXXX")
    if ! (printf '%s\n' ready > "$signal" &&
          [[ ! -e "$HAIDE_READY_FILE" && ! -L "$HAIDE_READY_FILE" ]] &&
          ln -h "$signal" "$HAIDE_READY_FILE"); then
      rm -f "$signal"
      fail '설치 준비 상태를 기록할 수 없습니다.'
    fi
    rm -f "$signal"
    reopen_on_failure="${running_bundle:-$target}"
    quit_requested=1
  else
    app_running || return 0
    if [[ "${HAIDE_QUIT:-0}" == 1 ]]; then
      request_quit
    elif { exec 3<>/dev/tty; } 2>/dev/null; then
      printf '%s' 'Haide를 종료하고 설치할까요? [Y/n] ' >&3
      if IFS= read -r answer <&3 && [[ "$answer" =~ ^([yY]|[yY][eE][sS])?$ ]]; then
        request_quit
      fi
      exec 3>&-
    fi
  fi
  local deadline=$((SECONDS + 600))
  local timeout_message='10분 내에 Haide가 종료되지 않아 설치를 중단합니다.'
  if [[ "$quit_requested" == 1 ]]; then
    deadline=$((SECONDS + 30))
    timeout_message='30초 내에 Haide가 종료되지 않아 설치를 중단합니다.'
  elif app_running; then
    [[ "${HAIDE_NO_WAIT:-0}" != 1 ]] || fail 'Haide가 실행 중이어서 설치를 중단합니다.'
    [[ -n "$reopen_on_failure" ]] || printf '%s\n' 'Haide를 직접 종료(⌘Q)하면 설치를 계속합니다'
  fi
  while app_running; do
    stop_if_cancelled
    (( SECONDS < deadline )) || fail "$timeout_message"
    sleep 1
  done
}

open_haide() {
  if [[ -n "${HAIDE_INSTALL_RESULT:-}" && -n "${HAIDE_HOME:-}" ]]; then
    open --env "HAIDE_HOME=$HAIDE_HOME" "$1"
  else
    open "$1"
  fi
}

cleanup() {
  local status=$?
  if [[ -n "$previous" && -e "$previous" ]]; then
    if [[ "$installed" == 1 ]]; then
      rm -rf "$previous" || status=1
    else
      if [[ ! -e "$staged" && -d "$target" && ! -L "$target" ]]; then
        mv -fh "$target" "$staged" || status=1
      fi
      if [[ -e "$target" || -L "$target" ]] || ! mv -fh "$previous" "$target"; then
        printf '이전 앱 보존 위치: %s\n' "$previous" >&2
        status=1
        reopen_on_failure=''
      fi
    fi
  fi
  if [[ -n "$staged" ]]; then
    rm -rf "$staged" || status=1
  fi
  rm -rf "$temporary" || status=1
  if [[ "$status" != 0 && "$installed" != 1 && -n "$reopen_on_failure" &&
        "${HAIDE_NO_OPEN:-0}" != 1 && -d "$reopen_on_failure" ]] && ! app_running; then
    # Publish the failure before the restored app can start. The parent also
    # handles failures outside this script, including failure to download it.
    if [[ -n "${HAIDE_INSTALL_RESULT:-}" && -f "$HAIDE_INSTALL_RESULT" &&
          ! -L "$HAIDE_INSTALL_RESULT" ]]; then
      mv -fh "$HAIDE_INSTALL_RESULT" "$HAIDE_INSTALL_RESULT.failed" || true
    fi
    open_haide "$reopen_on_failure" || true
  fi
  if [[ -n "$lock" ]]; then
    rm -f "$lock" || status=1
  fi
  exit "$status"
}

main() {
  [[ "$(uname -s)" == Darwin ]] || fail 'Haide 설치는 macOS에서 지원됩니다.'
  [[ "$(uname -m)" == arm64 ]] || fail 'Haide 설치는 Apple Silicon(arm64)에서 지원됩니다.'

  local bundle_id='io.github.kimsh8337.haide'
  local requirement='identifier "io.github.kimsh8337.haide" and certificate leaf = H"95e89c6e0aa6379f28e9817df6e1416efd24437f"'
  local release_url='https://github.com/kimsh8337/haide-releases/releases'
  local base_url="$release_url/latest/download"
  local zip='Haide-arm64-mac.zip'
  local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$'
  if [[ -n "${HAIDE_VERSION:-}" ]]; then
    [[ "$HAIDE_VERSION" =~ $version_pattern ]] || fail 'HAIDE_VERSION에 릴리스 버전을 입력하세요.'
    base_url="$release_url/download/v$HAIDE_VERSION"
  fi
  # Installer smoke tests use file:// downloads and the same verification steps.
  base_url="${HAIDE_INSTALL_BASE_URL:-$base_url}"

  temporary=$(mktemp -d)
  target=''
  staged=''
  previous=''
  lock=''
  installed=0
  running_bundle=''
  reopen_on_failure=''
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  curl -fL --retry 3 -o "$temporary/$zip" "${base_url%/}/$zip"
  curl -fL --retry 3 -o "$temporary/SHA256SUMS" "${base_url%/}/SHA256SUMS"
  local expected actual
  expected=$(awk -v name="$zip" '
    NF == 2 && $2 == name { count++; print tolower($1) }
    END { if (count != 1) exit 1 }
  ' "$temporary/SHA256SUMS") || fail "$zip 체크섬을 찾을 수 없습니다."
  [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || fail 'SHA-256 체크섬 형식이 잘못되었습니다.'
  actual=$(shasum -a 256 "$temporary/$zip")
  [[ "${actual%% *}" == "$expected" ]] || fail '다운로드한 zip의 SHA-256 체크섬이 다릅니다.'

  ditto -x -k "$temporary/$zip" "$temporary/unpacked"
  local app="$temporary/unpacked/Haide.app"
  local plist="$app/Contents/Info.plist"
  local actual_id actual_requirement version
  [[ -d "$app" && ! -L "$app" ]] || fail 'zip에서 Haide.app을 찾을 수 없습니다.'
  actual_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")
  [[ "$actual_id" == "$bundle_id" ]] || fail 'Haide 앱의 번들 ID가 다릅니다.'
  codesign --verify --deep --strict "$app" || fail 'Haide 앱의 코드 서명 검증에 실패했습니다.'
  actual_requirement=$(codesign -dr- "$app" 2>/dev/null)
  [[ "${actual_requirement#\# }" == "designated => $requirement" ]] ||
    fail 'Haide 앱의 지정 요구 사항이 다릅니다.'
  codesign --verify -R "=$requirement" "$app" || fail 'Haide 앱의 서명 요구 사항이 다릅니다.'
  version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")

  local directory="${HAIDE_INSTALL_DIR:-/Applications}"
  local cannot_write='설치 폴더에 쓸 수 없습니다. HAIDE_INSTALL_DIR=~/Applications 를 지정해 다시 실행하세요.'
  [[ "$directory" == /* ]] || directory="$PWD/$directory"
  # Resolve the nearest existing parent before mkdir can create any directories.
  local parent="$directory"
  while [[ ! -d "$parent" && "$parent" != / ]]; do
    parent=$(dirname "$parent")
  done
  local physical_parent
  physical_parent=$(cd -P "$parent" && pwd -P) || fail "$cannot_write"
  local settings
  settings=$(cd -P "$HOME" && pwd -P)/.haide
  if [[ "$physical_parent" == "$settings" || "$physical_parent" == "$settings/"* ]]; then
    fail 'Haide 설정 폴더는 앱 설치 위치로 사용할 수 없습니다.'
  fi
  mkdir -p "$directory" || fail "$cannot_write"
  directory=$(cd -P "$directory" && pwd -P) || fail "$cannot_write"
  if [[ "$directory" == "$settings" || "$directory" == "$settings/"* ]]; then
    fail 'Haide 설정 폴더는 앱 설치 위치로 사용할 수 없습니다.'
  fi
  [[ -w "$directory" ]] || fail "$cannot_write"

  local lock_path="$directory/.haide-install.lock"
  # Use the same PID lock as the local installer.
  if [[ -e "$lock_path" || -L "$lock_path" ]] ||
    ! (set -o noclobber; printf '%s' "$$" > "$lock_path") 2>/dev/null; then
    fail "Haide 설치 잠금을 얻을 수 없습니다: $lock_path"
  fi
  lock="$lock_path"
  target="$directory/Haide.app"
  local new_app="$directory/.Haide.app.new-$$"
  local old_app="$directory/.Haide.app.old-$$"
  [[ ! -e "$new_app" && ! -L "$new_app" && ! -e "$old_app" && ! -L "$old_app" ]] ||
    fail '이전 설치의 임시 파일을 확인하세요.'
  staged="$new_app"
  previous="$old_app"
  wait_for_haide
  stop_if_cancelled
  ditto "$app" "$staged"
  # Recursive deletion succeeds when the attribute is absent.
  xattr -dr com.apple.quarantine "$staged"
  if app_running; then
    fail 'Haide가 다시 실행되었습니다. 종료한 뒤 설치를 다시 실행하세요.'
  fi
  stop_if_cancelled
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -d "$target" && ! -L "$target" ]] || fail "기존 설치 경로가 앱 폴더가 아닙니다: $target"
    mv -fh "$target" "$previous"
  fi
  mv -fh "$staged" "$target"
  installed=1
  rm -rf "$previous"
  previous=''

  if [[ -d /opt/homebrew/Caskroom/haide || -d /usr/local/Caskroom/haide ]]; then
    printf '%s\n' '예전 Homebrew 기록: brew uninstall --cask --force haide 로 정리할 수 있습니다.' \
      '이 명령은 Homebrew가 관리하던 경로의 앱도 삭제할 수 있습니다.'
  fi
  printf 'Haide %s 설치 완료: %s\n' "$version" "$target"
  if [[ "${HAIDE_NO_OPEN:-0}" != 1 ]]; then
    open_haide "$target" || printf '%s\n' 'Haide를 자동으로 열지 못했습니다. 직접 여세요.' >&2
  fi
}

main "$@"
