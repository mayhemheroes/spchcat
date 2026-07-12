# syntax=docker/dockerfile:1.7
#
# Commit-image for spchcat (SMALL form) — builds on the org C/C++ base image.
# Extra deps beyond the base:
#   * libpulse-dev            — spchcat's audio sources include <pulse/*.h> (app_main_test links -lpulse)
#   * Coqui STT native client — prebuilt libstt/libtensorflowlite/libtflitedelegates + coqui-stt.h,
#     needed only to LINK the upstream app_main_test. Pinned to the v1.1.0 release the project uses
#     (scripts/download_libs.sh); baked at /opt/coqui so mayhem/build.sh consumes it OFFLINE.
FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# Pinned Coqui STT native-client release (x86_64 linux) — same artifact scripts/download_libs.sh pulls.
ARG STT_LIB_URL=https://github.com/coqui-ai/STT/releases/download/v1.1.0/native_client.tflite.Linux.tar.xz

USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends libpulse-dev xz-utils wget ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/coqui \
 && wget -qO /tmp/nc.tar.xz "$STT_LIB_URL" \
 && tar -xJf /tmp/nc.tar.xz -C /opt/coqui \
 && rm -f /tmp/nc.tar.xz \
 && chown -R 2000:2000 /opt/coqui \
 && mkdir -p /etc/spchcat/models/en_US \
 && printf 'placeholder-model' > /etc/spchcat/models/en_US/model.tflite \
 && printf 'placeholder-scorer' > /etc/spchcat/models/en_US/en.scorer \
 && chown -R 2000:2000 /etc/spchcat
# settings_test's default-path tests (test_set_source, test_settings_init_from_argv) resolve a model
# from spchcat's default install dir /etc/spchcat/models/<lang>/*.tflite. Upstream runs them on a box
# where a language pack is installed; a headless CI image has none, so settings_init_from_argv returns
# NULL and the tests SEGV/fail. Install a minimal placeholder language pack so path resolution
# succeeds — find_model_for_language only checks that a *.tflite exists, it never loads it here.
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
