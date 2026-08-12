#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

output_path="${1:-$ILO_BOARD_ARTIFACTS_DIR/board-screenshots/ilo-board-$(date +%Y%m%d-%H%M%S).png}"
capture_timeout="${2:-120}"
installed_menu_executable="/Applications/ILO Board.app/Contents/MacOS/ILOBoardMenu"
menu_was_running=0
menu_pids=()

restore_menu_companion() {
  if (( menu_was_running == 1 )); then
    if open -a "ILO Board"; then
      log "Reopened the menu companion."
    else
      print -u2 -- "[ilo-board] warning: Could not reopen the menu companion automatically."
    fi
  fi
}

trap restore_menu_companion EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! "$capture_timeout" =~ '^[0-9]+$' ]] || (( capture_timeout < 1 || capture_timeout > 120 )); then
  fail "Screenshot timeout must be an integer from 1 through 120 seconds."
fi

mkdir -p "${output_path:h}"

if [[ ! -x "$installed_menu_executable" ]]; then
  fail "Install the latest signed ILO Board app before capturing. Screenshots use its stable identity to avoid recurring Keychain prompts."
fi

if [[ -x "$installed_menu_executable" ]]; then
  capture_supported="$(/usr/libexec/PlistBuddy -c 'Print :ILOSupportsPromptFreeScreenCapture' "/Applications/ILO Board.app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$capture_supported" == "true" ]] || fail "Install the latest signed ILO Board app before capturing. This prevents recurring Keychain prompts from rebuilt development tools."
  menu_pids=("${(@f)$(pgrep -f "^${installed_menu_executable}$" || true)}")
  if (( ${#menu_pids} > 0 )) && [[ -n "$menu_pids[1]" ]]; then
    menu_was_running=1
    log "Pausing the installed menu companion for authenticated capture."
    kill -TERM "${menu_pids[@]}"
    for _ in {1..50}; do
      local_process_running=0
      for process_id in "${menu_pids[@]}"; do
        if kill -0 "$process_id" 2>/dev/null; then
          local_process_running=1
          break
        fi
      done
      (( local_process_running == 0 )) && break
      sleep 0.1
    done
    for process_id in "${menu_pids[@]}"; do
      if kill -0 "$process_id" 2>/dev/null; then
        fail "The installed menu companion did not stop cleanly; capture was not started."
      fi
    done
  fi
fi

capture_arguments=("--capture-board-screen" "$output_path" "--capture-timeout" "$capture_timeout")
"$installed_menu_executable" "${capture_arguments[@]}"
log "Saved live board screenshot: $output_path"
