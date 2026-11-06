#!/bin/bash
command=$(jq -r '.tool_input.command // empty')

# Only act on raw build and test commands that aren't filtered yet.
start=$'(^|[;&|(\n])[[:space:]]*([[:alnum:]_]+=[^[:space:]]*[[:space:]]+)*'
options='([^;&|]*[[:space:]])?'
action='(build|test|build-for-testing|test-without-building)([[:space:];&|>]|$)'

if [[ "$command" =~ ${start}xcodebuild[[:space:]]${options}${action} \
   && "$command" != *xcsift* ]]; then
  echo "Run it again as: set -o pipefail; $command 2>&1 | xcsift -f toon -w" >&2
  exit 2
fi

exit 0
