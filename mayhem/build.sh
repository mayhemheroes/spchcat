#!/usr/bin/env bash
#
# mayhem/build.sh — build spchcat's fuzz harness + standalone reproducer, and the project's own
# upstream unit-test suite (so mayhem/test.sh only RUNS it).
#
#   /mayhem/spchcat              in-process libFuzzer harness over wav_io_load() (target `spchcat`)
#   /mayhem/spchcat-standalone   run-once reproducer (same harness, $STANDALONE_FUZZ_MAIN driver)
#   build/bin/*_test             upstream acutest unit tests, NORMAL gcc flags (what test.sh runs)
#
# Air-gapped: the Coqui STT native libs (needed only to LINK app_main_test) are pre-baked into the
# image at /opt/coqui by mayhem/Dockerfile; this script copies them into build/lib offline. It never
# calls the upstream scripts/download_libs.sh (which fetches from the network). No upstream edits.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

INC="-Isrc -Isrc/audio -Isrc/utils -Isrc/third_party"

# 1) Fuzz harness — the untrusted-input code path (WAV parser). Instrument the PROJECT sources
#    (wav_io.c + audio_buffer.c) with $SANITIZER_FLAGS + $DEBUG_FLAGS so the fuzzed code (not just the
#    harness) is sanitized and carries DWARF < 4.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE $INC \
    mayhem/fuzz_spchcat.c src/audio/wav_io.c src/audio/audio_buffer.c \
    -o /mayhem/spchcat

# 2) Standalone (non-fuzzer) reproducer — same harness, LLVM's run-once driver.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" $INC \
    mayhem/fuzz_spchcat.c src/audio/wav_io.c src/audio/audio_buffer.c \
    -o /mayhem/spchcat-standalone

# 3) Upstream unit-test suite, built with the project's OWN compiler (gcc) + flags via its Makefile,
#    so mayhem/test.sh only RUNS the binaries. The Coqui STT libs (baked at /opt/coqui) go where the
#    Makefile's -Lbuild/lib / -Ibuild/lib expect them; libkenlm + rpath-link resolve libstt's deps.
#    pa_list_devices_test is intentionally NOT built here — it opens a live PulseAudio daemon (absent
#    in a headless container) and hangs; see mayhem/test.sh.
mkdir -p build/lib
cp -f /opt/coqui/* build/lib/
make CC=gcc \
     LDFLAGS="-Lbuild/lib -lstt -ltensorflowlite -ltflitedelegates -lkenlm -lpulse -lpulse-simple -Wl,-rpath-link,build/lib" \
     -j"$MAYHEM_JOBS" \
     build/bin/file_utils_test \
     build/bin/string_utils_test \
     build/bin/yargs_test \
     build/bin/settings_test \
     build/bin/audio_buffer_test \
     build/bin/wav_io_test \
     build/bin/app_main_test

echo "build.sh: built /mayhem/spchcat (+ -standalone) and $(ls build/bin | wc -l) upstream test binaries"
