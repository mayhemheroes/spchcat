#!/usr/bin/env bash
#
# mayhem/test.sh — RUN spchcat's OWN upstream unit-test suite (acutest), already built by
# mayhem/build.sh. Behavioral: every binary asserts concrete values / known-answer results
# (e.g. wav_io_test decodes a fixed WAV and checks the exact PCM samples; app_main_test checks
# plain_text_from_transcript() output strings), so a no-op / exit(0) sabotage FAILS the suite.
# Emits a CTRF summary and exits non-zero iff any test failed. Never compiles.
#
# Suite = upstream Makefile `test` target (8 binaries). We run 7; pa_list_devices_test is SKIPPED:
# it calls get_input_devices(), which connects to (and tries to autospawn) a live PulseAudio daemon
# that does not exist in a headless container, so it HANGS rather than testing anything. Recorded as
# skipped below. All 7 run acutest with --xml-output (JUnit), which we parse for exact counts.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

export LD_LIBRARY_PATH="build/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# settings_test reads getenv("LANG") and restores it verbatim (settings_test.c:83) — with LANG unset
# it setenv(NULL)s and SEGVs, an environment gap, not a behavior bug. Its default-path subtests also
# derive the language from LANG (set_defaults) and then resolve a model under /etc/spchcat/models/<lang>,
# so LANG must name the language pack the image installs (en_US). set_defaults only PARSES the string,
# so the en_US.UTF-8 locale need not be generated in the image.
export LANG=en_US.UTF-8
# These acutest binaries are allocate-and-exit BATCH tools; a couple of them leak a few bytes of
# pre-existing upstream cruft at exit (e.g. settings.c:55 string_duplicate). That's not the behavior
# under test (every assertion is a value/KAT check), so we run with LeakSanitizer off — the sanctioned
# detect_leaks=0-for-batch-tools case. ASan/UBSan error detection stays ON and HALTING.
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:${ASAN_OPTIONS:-}"
export UBSAN_OPTIONS="halt_on_error=1:${UBSAN_OPTIONS:-}"

TESTS=(file_utils_test string_utils_test yargs_test settings_test audio_buffer_test wav_io_test app_main_test)
SKIPPED=1  # pa_list_devices_test (needs a live PulseAudio daemon; see header)

xmldir="$(mktemp -d)"
missing=0
for t in "${TESTS[@]}"; do
  bin="build/bin/$t"
  if [ ! -x "$bin" ]; then
    echo "test.sh: MISSING test binary $bin — build.sh must produce it (not rebuilding here)" >&2
    missing=1
    continue
  fi
  echo "== $t =="
  "./$bin" --xml-output="$xmldir/$t.xml" || true
done

if [ "$missing" -ne 0 ]; then
  emit_ctrf spchcat-acutest 0 1 "$SKIPPED"
  exit 1
fi

read -r passed failed < <(python3 - "$xmldir" <<'PY'
import sys, glob, os
import xml.etree.ElementTree as ET
d = sys.argv[1]
passed = failed = 0
files = glob.glob(os.path.join(d, "*.xml"))
if not files:
    print("0 1"); sys.exit(0)
for f in files:
    try:
        root = ET.parse(f).getroot()
    except Exception:
        failed += 1
        continue
    suites = [root] if root.tag == "testsuite" else root.findall(".//testsuite")
    for s in suites:
        t = int(s.get("tests", 0))
        fl = int(s.get("failures", 0)) + int(s.get("errors", 0))
        failed += fl
        passed += (t - fl)
print(f"{passed} {failed}")
PY
)

echo "test.sh: passed=$passed failed=$failed skipped=$SKIPPED"
emit_ctrf spchcat-acutest "$passed" "$failed" "$SKIPPED"
