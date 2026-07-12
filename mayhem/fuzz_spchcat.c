/*
 * mayhem/fuzz_spchcat.c — in-process libFuzzer harness for spchcat's WAV loader.
 *
 * spchcat's original Mayhem target ran the whole `spchcat --languages_dir=/models @@` CLI on a WAV
 * file. That path is unfuzzable in an air-gapped commit image: it needs the multi-hundred-MB Coqui
 * STT model (network download) loaded before it ever touches the input, so it produced ~0 useful
 * edges on the actual attacker-controlled parsing. The first thing spchcat does with an untrusted
 * file is parse it with wav_io_load() (src/audio/wav_io.c) — the real untrusted-input surface — so
 * we keep the SAME target name `spchcat` but drive that code path directly, no model required.
 *
 * wav_io_load() takes a filename, so we stage the fuzz bytes to a temp file (its natural interface)
 * and parse them, then free the resulting AudioBuffer. This exercises the header/chunk parsing,
 * channel/sample-rate handling, and the data-chunk allocation exactly as the CLI does.
 */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "audio_buffer.h"
#include "wav_io.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  char path[] = "/tmp/spchcat_fuzz_XXXXXX";
  int fd = mkstemp(path);
  if (fd < 0) {
    return 0;
  }
  FILE *f = fdopen(fd, "wb");
  if (f == NULL) {
    close(fd);
    unlink(path);
    return 0;
  }
  if (size > 0) {
    fwrite(data, 1, size, f);
  }
  fclose(f);

  AudioBuffer *buffer = NULL;
  wav_io_load(path, &buffer);
  audio_buffer_free(buffer); /* NULL-safe; frees on the success path */

  unlink(path);
  return 0;
}
