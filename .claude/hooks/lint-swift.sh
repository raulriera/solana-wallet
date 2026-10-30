#!/bin/bash
# PostToolUse hook: lints the Swift file an edit just changed with swift-format and reports
# findings on the changed lines, so the agent fixes them as it works.

file=$(jq -r '.tool_input.file_path // empty')
[[ "$file" == *.swift && -f "$file" ]] || exit 0
# Git reports the physical top level, so resolve symlinks in the edited path too.
file="$(cd "${file%/*}" && pwd -P)/${file##*/}"
root=$(git -C "${file%/*}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ -f "$root/.swift-format" ]] || exit 0
swiftFormat=$(xcrun --find swift-format 2>/dev/null) || exit 0
cd "$root" || exit 0
relative=${file#"$root"/}

# Changed lines against HEAD, from the old path when the file was moved; a new file is
# compared with nothing, so every line counts.
if git ls-files --error-unmatch -- "$relative" >/dev/null 2>&1; then
    moved=$(git diff --no-color --name-status -M HEAD | awk -F '\t' -v path="$relative" '$1 ~ /^R/ && $3 == path { print $2 }')
    base=(-M HEAD --)
    [[ -n $moved ]] && base+=("$moved")
else
    base=(--no-index /dev/null)
fi
changed=$(git diff --no-color --no-ext-diff -U0 "${base[@]}" "$relative" | awk '/^@@/ {
    split(substr($3, 2), range, ",")
    count = (range[2] == "" ? 1 : range[2])
    for (i = 0; i < count; i++) printf "%d ", range[1] + i
}')
[[ -n $changed ]] || exit 0

# Layout findings come from the pretty printer, which can't keep the repo's aligned
# argument wrapping, so only rule findings are reported. Errors without a line, such as an
# unreadable configuration, always pass so linting never turns off silently.
skipped="\[(Indentation|AddLines|RemoveLine|LineLength|Spacing|TrailingWhitespace|TrailingComma|EndOfLineComment)\]"
findings=$("$swiftFormat" lint "$relative" 2>&1 | grep -vE "$skipped" \
    | awk -F: -v lines="$changed" 'BEGIN { n = split(lines, list, " "); for (i = 1; i <= n; i++) keep[list[i]] = 1 }
        (($2 in keep) || ($2 !~ /^[0-9]+$/ && /error:/)) && !seen[$0]++')

[[ -z "$findings" ]] && exit 0
{
    echo "Lint findings on lines you changed in $relative (rules in .swift-format). Fix them now:"
    echo "$findings"
    echo "Only when a finding is wrong, put '// swift-format-ignore: <Rule>' right above that line."
} >&2
exit 2
