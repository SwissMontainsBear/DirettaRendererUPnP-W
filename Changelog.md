# Changelog

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
