# Core Patches

The `core/baresip` and `core/re` submodules point at clean upstream release
tags. Fixes TonePhone needs before they land upstream live here as patch
files and are applied at build time.

`scripts/build-core.sh` copies `core/baresip` to `build/src/baresip`, applies
every `core/patches/baresip/*.patch` in name order with `patch -p1`, and builds
from the copy. The submodule itself is never modified.

## Patches

| Patch | Why |
|-------|-----|
| `baresip/0001-audiounit-deliver-recorded-audio-in-packet-time-chunks.patch` | The audiounit recorder asked the converter for `inNumberFrames` frames, which needs more input than its buffer holds at high hardware sample rates (96 kHz to 8 kHz). No microphone audio was sent. Renders one packet time per iteration instead. |

## Updating baresip

1. Check out the new tag in `core/baresip` and `core/re` (they are released together).
2. Run `./scripts/build-core.sh --clean`. A patch that no longer applies stops the build with its file name.
3. Drop patches that upstream has merged; refresh the others with `diff -u` against the new tag.
4. Run `./scripts/package-xcframework.sh` and build the app.

## Writing a patch

Make the change in `build/src/baresip` (or a scratch copy of the tag), then:

```bash
diff -u a/path/to/file.c b/path/to/file.c > core/patches/baresip/000N-short-description.patch
```

Start the file with a short description of the problem and the fix, like a commit message. Keep patches minimal and without debug logging.
