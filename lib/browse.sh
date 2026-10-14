#!/bin/bash
# The --interactive browse of the results in fzf. audit.sh runs it as `browse.sh open results_file`;
# fzf runs it again for its list (findings, checks) and for the result under the cursor (preview, view).
set -u
LIB_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=lib/system.sh
source "$LIB_DIR/system.sh"
export BROWSE_COLOR="${BROWSE_COLOR:-true}"

action="$1"
results="$2"
index="${3:-}"

# Usage: render jq_expression; runs it on the slurped results, with the report's jq definitions.
render() {
  jq -rs --argjson isTerminal true --argjson useColor "$BROWSE_COLOR" \
    --argjson terminalWidth "${FZF_PREVIEW_COLUMNS:-80}" --arg host "" --arg macos "" --arg generatedAt "" \
    "$(cat "$LIB_DIR/table.jq" "$LIB_DIR/text.jq" "$LIB_DIR/report.jq")"$'\n'"$1" "$results"
}

# Starts on the findings, or on every check when there are none. The preview sits beside the list
# from 160 columns, below it otherwise.
open_browse() {
  local self file list=findings window="down,60%,border-top,wrap"
  self="bash $(printf %q "$LIB_DIR/browse.sh")"
  file="$(printf %q "$results")"
  [[ "$(render 'map(select(.severity != null)) | length')" -gt 0 ]] || list=checks
  [[ "$(terminal_width)" -lt 160 ]] || window="right,50%,border-left,wrap"
  render "browseRows(\"$list\")" |
    fzf --ansi --delimiter '\t' --with-nth 2.. --layout reverse --info inline-right --tiebreak index \
      --border rounded --border-label " $(list_title "$list") " \
      --header "enter full view · alt-f findings · alt-a all checks · esc quit" \
      --preview "$self preview $file {1}" --preview-window "$window" \
      --bind "enter:execute($self view $file {1})" \
      --bind "alt-f:reload($self findings $file)+change-border-label( $(list_title findings) )" \
      --bind "alt-a:reload($self checks $file)+change-border-label( $(list_title checks) )" ||
    true
}

list_title() {
  case "$1" in
    findings) echo "Findings" ;;
    checks) echo "All checks" ;;
  esac
}

# An empty list has no index.
show_result() {
  [[ "$index" =~ ^[0-9]+$ ]] || return 0
  render ".[$index] | detail"
}

case "$action" in
  open) open_browse ;;
  findings | checks) render "browseRows(\"$action\")" ;;
  preview) show_result ;;
  view) show_result | less -R ;;
esac
