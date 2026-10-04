#!/usr/bin/env bash
# Source at the start of a harness. A supervising shell owns the workspace,
# so even a harness that replaces its EXIT trap cannot leak its temporaries.
native_temp_script="$(realpath "${BASH_SOURCE[1]}")"
if [[ ${NATIVE_TEMP_CHILD:-} != "$native_temp_script" ]]; then
  native_temp_base=/tmp/native-pascal-1981
  native_temp_work=
  native_temp_pid=
  native_temp_cleanup() {
    if [[ -n $native_temp_work ]]; then rm -rf -- "$native_temp_work"; fi
  }
  native_temp_signal() {
    trap '' HUP INT TERM
    if [[ -n $native_temp_pid ]]; then
      kill -TERM -- "-$native_temp_pid" 2>/dev/null || true
      wait "$native_temp_pid" 2>/dev/null || true
    fi
    exit "$1"
  }
  trap native_temp_cleanup EXIT
  trap 'native_temp_signal 129' HUP
  trap 'native_temp_signal 130' INT
  trap 'native_temp_signal 143' TERM
  mkdir -p -m 700 "$native_temp_base" || exit 1
  if [[ -L $native_temp_base || ! -d $native_temp_base || ! -O $native_temp_base ]] ||
      (( (8#$(stat -c %a "$native_temp_base") & 8#22) != 0 )); then
    echo "error: unsafe temporary root: $native_temp_base" >&2
    exit 1
  fi
  native_temp_work=$(mktemp -d "$native_temp_base/shell.XXXXXXXXXX") || exit 1
  TMPDIR="$native_temp_work" NATIVE_TEMP_CHILD="$native_temp_script" setsid bash "$native_temp_script" "$@" <&0 &
  native_temp_pid=$!
  native_temp_status=0
  wait "$native_temp_pid" || native_temp_status=$?
  exit "$native_temp_status"
fi
unset NATIVE_TEMP_CHILD
# Convert catchable termination into an exit so the harness's EXIT trap runs.
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
