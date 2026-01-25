# Changelog

## 2026-01-25 - Bug Fix: 16-bit Audio Segfault on 24-bit-only Sinks

**Problem:** Segfault when playing 16-bit audio files on Diretta targets that only support 24-bit PCM (not 32-bit).

**Root Cause:** Missing conversion path for 16-bit input to 24-bit sink.
- Existing code had 16→32 upsampling (`m_need16To32Upsample`) for 32-bit sinks
- For 24-bit-only sinks (`direttaBps == 3`), the 16→32 condition was FALSE
- Code fell through to direct copy with wrong byte calculation:
  - `bytesPerFrame = 3 * 2 = 6` (using sink's bytes-per-sample)
  - Actual input: `2 * 2 = 4` bytes per frame
- Result: Buffer overrun reading 4096 bytes past input buffer → segfault

**Fix:** Added complete 16→24 bit upsampling path:
- New atomic flag: `m_need16To24Upsample` (set when `direttaBps == 3 && inputBps == 2`)
- New cached value: `m_cachedUpsample16to24`
- New ring buffer function: `push16To24()` - converts 16-bit to 24-bit (shift left 8 bits)
- New dispatch path in `sendAudio()` using correct input frame size

**Files Changed:**
- `src/DirettaSync.h` - Added atomic flag and cached value
- `src/DirettaRingBuffer.h` - Added `push16To24()` function
- `src/DirettaSync.cpp` - Flag initialization and dispatch path

---

## 2026-01-23 - SDK 148 Migration & Windows Build Improvements

### SDK 148 Migration

Migrated from Diretta Host SDK 147 to SDK 148.

**SDK 148 Breaking Changes Handled:**
1. `getNewStream()` signature changed from `Stream&` to `diretta_stream&` (pure virtual)
2. Stream copy semantics deleted (only move allowed)
3. Inheritance changed from `private diretta_stream` to `public diretta_stream`

**Solution Implemented:**
- Bypass `DIRETTA::Stream` class methods entirely
- Use persistent `std::vector<uint8_t> m_streamData` buffer
- Directly set `diretta_stream` C structure fields:
  ```cpp
  baseStream.Data.P = m_streamData.data();
  baseStream.Size = currentBytesPerBuffer;
  ```

This avoids SDK 148's corrupted Stream objects after Stop→Play sequences.

**Files Changed:**
- `src/DirettaSync.h` - Added `m_streamData` buffer
- `src/DirettaSync.cpp` - Rewrote `getNewStream()` to bypass Stream class
- `DirettaRendererUPnP.vcxproj` - Updated SDK paths to SDK 148

---

### Windows Build Fix: POSIX Header Removal

**Problem:** Build failed with `Cannot open include file: 'unistd.h'`

**Cause:** `DirettaRenderer.cpp` included `<unistd.h>` which is POSIX-only.

**Solution:**
- Replaced `#include <unistd.h>` with `#include "Platform.h"`
- Changed `gethostname()` to `Platform::getHostname()`

**Files Changed:**
- `src/DirettaRenderer.cpp`

---

### New Build Script

Added `build.bat` for convenient multi-architecture builds.

**Usage:**
```cmd
build.bat              :: Build both x64 and ARM64 Release
build.bat x64          :: Build x64 only
build.bat arm64        :: Build ARM64 only
build.bat debug        :: Build Debug configuration
build.bat clean        :: Clean and rebuild
```

**Output Locations:**
```
bin\x64\Release\DirettaRendererUPnP.exe
bin\ARM64\Release\DirettaRendererUPnP.exe
```

**Files Added:**
- `build.bat`

---

### License Compliance Documentation

Added third-party license documentation for LGPL compliance when distributing FFmpeg DLLs.

**Files Added:**
- `THIRD_PARTY_LICENSES.md` - Documents FFmpeg (LGPL), libupnp (BSD) licenses
- `licenses/` directory for license texts

---

### Project Configuration

**Visual Studio Requirements:**
- Visual Studio 2022/2026 with MSVC v145 toolset
- Windows 10/11 SDK

**Dependencies (via vcpkg):**
```cmd
vcpkg install ffmpeg:x64-windows libupnp:x64-windows
vcpkg install ffmpeg:arm64-windows libupnp:arm64-windows
```

**Diretta SDK:**
- SDK 148 required (download from https://www.diretta.link)
- Place in `..\DirettaHostSDK_148\`

---

## Previous Versions

See the Linux version (DirettaRendererUPnP-X) CHANGELOG for detailed history of optimizations including:

- DSD Flow Control (50x jitter reduction)
- Consumer/Producer Generation Counters
- Ring Buffer Optimizations
- PCM Bypass Mode
- DSD Conversion Function Specialization
- And many more audio quality improvements

These optimizations are shared between the Linux and Windows codebases.
