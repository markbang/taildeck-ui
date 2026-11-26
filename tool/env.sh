# Source before flutter or dart commands: `source tool/env.sh`.
# A variable exported before sourcing keeps its value; unset ones take the official upstream.
: "${PUB_HOSTED_URL:=https://pub.dev}"
: "${FLUTTER_STORAGE_BASE_URL:=https://storage.googleapis.com}"
export PUB_HOSTED_URL FLUTTER_STORAGE_BASE_URL

if [ -n "${FLUTTER_HOME:-}" ] || ! command -v flutter > /dev/null 2>&1; then
  FLUTTER_HOME=${FLUTTER_HOME:-$HOME/flutter}
  if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
    echo "tool/env.sh: no flutter at $FLUTTER_HOME/bin/flutter" >&2
    echo "  put flutter on PATH, or set FLUTTER_HOME to the SDK directory that contains bin/flutter" >&2
    return 1 2> /dev/null || exit 1
  fi
  export FLUTTER_HOME
  PATH="$FLUTTER_HOME/bin:$PATH"
  export PATH
fi
