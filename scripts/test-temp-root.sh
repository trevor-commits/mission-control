#!/usr/bin/env bash
# Shared macOS-safe temporary root for Mission Control shell test suites.
# BSD mktemp ignores TMPDIR when no template is supplied, so the private PATH
# wrapper below supplies a template only for bare `mktemp` and `mktemp -d`.

if [[ -z "${MISSION_TEST_NATIVE_MKTEMP:-}" ]]; then
  MISSION_TEST_NATIVE_MKTEMP="$(command -v mktemp)" || return 1
  export MISSION_TEST_NATIVE_MKTEMP
fi

mission_test_temp_identity() {
  stat -f '%d:%i:%u' "$1" 2>/dev/null || stat -c '%d:%i:%u' "$1" 2>/dev/null
}

mission_test_temp_before_claim() {
  :
}

mission_test_temp_cleanup() {
  local root claim claimed
  [[ -n "${MISSION_TEST_TEMP_ROOT:-}" ]] || return 0
  root="$MISSION_TEST_TEMP_ROOT"
  claim="${MISSION_TEST_TEMP_CLAIM:-}"
  [[ -n "$claim" ]] || return 1
  [[ -d "$root" && ! -L "$root" ]] || return 1
  [[ "$(mission_test_temp_identity "$root")" == "$MISSION_TEST_TEMP_ROOT_ID" ]] || return 1
  [[ -d "$claim" && ! -L "$claim" ]] || return 1
  [[ "$(mission_test_temp_identity "$claim")" == "$MISSION_TEST_TEMP_CLAIM_ID" ]] || return 1
  case "$root" in
    "$MISSION_TEST_TEMP_PARENT"/"$MISSION_TEST_TEMP_PREFIX".*) ;;
    *) return 1 ;;
  esac
  case "$claim" in
    "$MISSION_TEST_TEMP_PARENT"/."$MISSION_TEST_TEMP_PREFIX"-cleanup.*) ;;
    *) return 1 ;;
  esac

  # Never delete a name in the shared parent directly. Claim it with an
  # atomic same-filesystem rename into a mode-0700 directory, then verify that
  # the moved inode is still the root this process created. A replacement at
  # the original path is preserved rather than recursively removed.
  mission_test_temp_before_claim || return 1
  claimed="$claim/root"
  [[ ! -e "$claimed" && ! -L "$claimed" ]] || return 1
  /bin/mv -- "$root" "$claimed" || return 1
  [[ -d "$claimed" && ! -L "$claimed" ]] || return 1
  [[ "$(mission_test_temp_identity "$claimed")" == "$MISSION_TEST_TEMP_ROOT_ID" ]] || return 1
  /bin/rm -rf -- "$claimed" || return 1
  [[ ! -e "$claimed" && ! -L "$claimed" ]] || return 1
  [[ -d "$claim" && ! -L "$claim" ]] || return 1
  [[ "$(mission_test_temp_identity "$claim")" == "$MISSION_TEST_TEMP_CLAIM_ID" ]] || return 1
  /bin/rmdir -- "$claim" || return 1

  MISSION_TEST_TEMP_ROOT=""
  MISSION_TEST_TEMP_ROOT_ID=""
  MISSION_TEST_TEMP_CLAIM=""
  MISSION_TEST_TEMP_CLAIM_ID=""
}

mission_test_temp_finish() {
  local test_status="$1"
  trap - EXIT HUP INT TERM
  if ! mission_test_temp_cleanup; then
    printf 'FAIL: could not remove the owned Mission Control test root: %s\n' \
      "${MISSION_TEST_TEMP_ROOT:-unresolved}" >&2
    [[ "$test_status" -ne 0 ]] || test_status=1
  fi
  exit "$test_status"
}

mission_test_temp_init() {
  local prefix="$1" parent claim claim_id root root_id wrapper
  [[ -z "${MISSION_TEST_TEMP_ROOT:-}" ]] || return 1
  case "$prefix" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  parent="$(CDPATH= cd -- "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)" || return 1
  claim="$("$MISSION_TEST_NATIVE_MKTEMP" -d "$parent/.${prefix}-cleanup.XXXXXX")" || return 1
  chmod 700 "$claim" || {
    /bin/rmdir -- "$claim" 2>/dev/null || true
    return 1
  }
  claim_id="$(mission_test_temp_identity "$claim")" || {
    /bin/rmdir -- "$claim" 2>/dev/null || true
    return 1
  }
  root="$("$MISSION_TEST_NATIVE_MKTEMP" -d "$parent/$prefix.XXXXXX")" || {
    /bin/rmdir -- "$claim" 2>/dev/null || true
    return 1
  }
  root_id="$(mission_test_temp_identity "$root")" || {
    /bin/rmdir "$root" 2>/dev/null || true
    /bin/rmdir "$claim" 2>/dev/null || true
    return 1
  }

  MISSION_TEST_TEMP_PARENT="$parent"
  MISSION_TEST_TEMP_PREFIX="$prefix"
  MISSION_TEST_TEMP_CLAIM="$claim"
  MISSION_TEST_TEMP_CLAIM_ID="$claim_id"
  MISSION_TEST_TEMP_ROOT="$root"
  MISSION_TEST_TEMP_ROOT_ID="$root_id"
  trap 'mission_test_temp_finish $?' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  chmod 700 "$root" || return 1
  mkdir -m 700 "$root/tmp" "$root/test-bin" || return 1

  wrapper="$root/test-bin/mktemp"
  cat > "$wrapper" <<'SH'
#!/bin/sh
case "$#" in
  0) set -- "${TMPDIR:?}/tmp.XXXXXXXX" ;;
  1) [ "$1" = -d ] && set -- -d "${TMPDIR:?}/tmp.XXXXXXXX" ;;
esac
exec "${MISSION_TEST_NATIVE_MKTEMP:?}" "$@"
SH
  chmod 700 "$wrapper" || return 1

  MISSION_TEST_TMPDIR="$root/tmp"
  TMPDIR="$MISSION_TEST_TMPDIR"
  PATH="$root/test-bin:$PATH"
  export TMPDIR PATH
  hash -r 2>/dev/null || true
}
