# Fork Changes from Original v1.1.2

This document describes the architectural changes and improvements made in this fork of DirettaRendererUPnP.

## Overview

This fork refactors the Diretta integration to use the lower-level `DIRETTA::Sync` API  instead of `DIRETTA::SyncBuffer`, providing better control over audio streaming and improved reliability.

## Summary

| Metric | Original v1.1.2 | This Fork | Change |
|--------|-----------------|-----------|--------|
| Total lines of code | 6,410 | 6,209 | -3% |
| Core Diretta files | 2,079 lines | 1,939 lines | -7% |
| SDK API | `DIRETTA::SyncBuffer` | `DIRETTA::Sync` | Lower-level |
| Architecture | 2-class design | 3-class design | Cleaner separation |

---

## Architectural Changes

### Original v1.1.2 Structure

```
src/
├── DirettaOutput.cpp    (1,167 lines) - Connection, format, buffering
├── DirettaOutput.h      (201 lines)
├── DirettaRenderer.cpp  (912 lines)   - UPnP + threading + callbacks
├── DirettaRenderer.h    (101 lines)
├── AudioEngine.cpp/h
├── UPnPDevice.cpp/hpp
└── main.cpp
```

### This Fork Structure

```
src/
├── DirettaSync.cpp      (1,114 lines) - Unified adapter (inherits DIRETTA::Sync)
├── DirettaSync.h        (329 lines)
├── DirettaRingBuffer.h  (252 lines)   - Extracted lock-free ring buffer
├── DirettaRenderer.cpp  (573 lines)   - Simplified orchestrator
├── DirettaRenderer.h    (85 lines)
├── AudioEngine.cpp/h
├── UPnPDevice.cpp/hpp
└── main.cpp
```

---

## Key Technical Differences

### 1. SDK API Approach

| Aspect | Original | This Fork |
|--------|----------|-----------|
| Base class | Uses `DIRETTA::SyncBuffer` | Inherits from `DIRETTA::Sync` |
| Model | Push-only | Push/pull hybrid |
| Buffer control | SDK manages internally | App manages via DirettaRingBuffer |
| Timing control | Limited | Full control via `getNewStream()` override |

**Original approach:**
```cpp
m_syncBuffer = std::make_unique<DIRETTA::SyncBuffer>();
m_syncBuffer->open(...);
m_syncBuffer->write(data, size);
```

**This fork approach:**
```cpp
class DirettaSync : public DIRETTA::Sync {
    bool getNewStream(DIRETTA::Stream& stream) override {
        // Pull data from ring buffer
        m_ringBuffer.pop(dest, bytesNeeded);
        return true;
    }
};
```

### 2. Format Configuration

**Original** - Raw FormatID bit flags:
```cpp
DIRETTA::FormatID formatID;
formatID = DIRETTA::FormatID::FMT_DSD1 | DIRETTA::FormatID::FMT_DSD_SIZ_32;
formatID |= DIRETTA::FormatID::FMT_DSD_LSB;
formatID |= DIRETTA::FormatID::FMT_DSD_LITTLE;
```

**This fork** - FormatConfigure class with validation:
```cpp
DIRETTA::FormatConfigure fmt;
fmt.setSpeed(dsdBitRate);
fmt.setChannel(channels);
fmt.setFormat(DIRETTA::FormatID::FMT_DSD1 |
              DIRETTA::FormatID::FMT_DSD_SIZ_32 |
              DIRETTA::FormatID::FMT_DSD_LSB |
              DIRETTA::FormatID::FMT_DSD_BIG);

if (checkSinkSupport(fmt)) {
    setSinkConfigure(fmt);
}
```

### 3. DSD Handling Improvements

| Feature | Original | This Fork |
|---------|----------|-----------|
| Source format detection | Basic codec check | Full DSF/DFF detection via `AudioFormat::DSDFormat` |
| Bit reversal decision | Always reverse if target is MSB | Compare source (DSF=LSB, DFF=MSB) vs target |
| Byte endianness | Partial LITTLE support | Full byte swap for LITTLE endian targets |
| Format change handling | Light reconfigure | Full reopen + 100 silence buffers |

**Bit reversal logic (this fork):**
```cpp
bool sourceIsLSB = (format.dsdFormat == AudioFormat::DSDFormat::DSF);

// Target is MSB | BIG
m_needDsdBitReversal = sourceIsLSB;  // Reverse if source is LSB (DSF)
m_needDsdByteSwap = false;           // BIG endian = no swap

// Target is MSB | LITTLE
m_needDsdBitReversal = sourceIsLSB;  // Reverse if source is LSB (DSF)
m_needDsdByteSwap = true;            // LITTLE endian = swap bytes
```

### 4. Ring Buffer Extraction

The ring buffer is now a separate, reusable class with specialized push methods:

```cpp
class DirettaRingBuffer {
    // Direct PCM copy
    size_t push(const uint8_t* data, size_t len);

    // 24-bit packing (S24_P32 → 24-bit)
    size_t push24BitPacked(const uint8_t* data, size_t inputSize);

    // 16-bit to 32-bit upsampling
    size_t push16To32(const uint8_t* data, size_t inputSize);

    // DSD planar to interleaved with optional bit reversal & byte swap
    size_t pushDSDPlanar(const uint8_t* data, size_t inputSize,
                         int numChannels,
                         const uint8_t* bitReverseTable,
                         bool byteSwap = false);
};
```

### 5. Format Transition Handling

**Original:** Light reconfigure attempt, may fail on some targets

**This fork:** Full `reopenForFormatChange()`:
```cpp
bool DirettaSync::reopenForFormatChange() {
    // 1. Send silence buffers (100 for DSD, 30 for PCM)
    requestShutdownSilence(m_isDsdMode ? 100 : 30);

    // 2. Wait for silence to be sent
    while (m_silenceBuffersRemaining > 0) { ... }

    // 3. Full SDK shutdown
    stop();
    disconnect(true);
    DIRETTA::Sync::close();

    // 4. Wait for DAC stabilization
    std::this_thread::sleep_for(std::chrono::milliseconds(800));

    // 5. Reopen SDK
    DIRETTA::Sync::open(...);
    setSink(...);

    return true;
}
```

---

## Bug Fixes

### 1. Duplicate `av_seek_frame()` Calls
**File:** `AudioEngine.cpp:340-344`
**Issue:** DSD diagnostic code had seek-back duplicated
**Fix:** Removed duplicate block

### 2. Duplicate `DEBUG_LOG` Statements
**File:** `AudioEngine.cpp:453-463`
**Issue:** PCM format info logged twice, first without semicolon
**Fix:** Removed malformed duplicate

### 3. Static Variable in Lambda
**File:** `DirettaRenderer.cpp:272`
**Issue:** `static lastStopTime` inside `start()` is unconventional
**Fix:** Moved to member variable `m_lastStopTime`

### 4. Redundant Assignment
**File:** `AudioEngine.cpp:389`
**Issue:** `m_rawDSD = false` assigned twice in PCM path
**Fix:** Removed duplicate at line 389

### 5. DSD White Noise on Some Targets
**Issue:** Source format (DSF/DFF) not considered when deciding bit reversal
**Fix:** Pass `AudioFormat` to `configureSinkDSD()`, compare source vs target bit order

### 6. Loud Cracks on DSD Format Change
**Issue:** No silence padding before format switch
**Fix:** Added 100 silence buffers for DSD in `reopenForFormatChange()`

---

## Files Changed

| File | Status | Notes |
|------|--------|-------|
| `DirettaOutput.cpp/h` | **Removed** | Merged into DirettaSync |
| `DirettaSync.cpp/h` | **New** | Unified adapter inheriting DIRETTA::Sync |
| `DirettaRingBuffer.h` | **New** | Extracted lock-free ring buffer |
| `DirettaRenderer.cpp` | **Modified** | Simplified, -37% code |
| `DirettaRenderer.h` | **Modified** | Added `m_lastStopTime` member |
| `AudioEngine.cpp` | **Modified** | Bug fixes (duplicates removed) |
| `main.cpp` | **Modified** | Simplified options |

---

## Compatibility

- **Command-line interface:** Unchanged
- **UPnP behavior:** Unchanged
- **Control points:** Same compatibility
- **SDK requirement:** Same (Diretta Host SDK v1.47)

---

## Testing

Tested with:
- PCM: FLAC, ALAC, WAV (44.1kHz - 384kHz, 16/24/32-bit)
- DSD: DSF and DFF files (DSD64, DSD128, DSD256, DSD512)
- Format transitions: PCM↔PCM, DSD↔DSD, PCM↔DSD
- Control points: JPlay, mconnect

---

## Credits

- Original DirettaRendererUPnP by Dominique (cometdom)
- MPD Diretta Output Plugin v0.4.0 for DIRETTA::Sync API patterns
- Claude Code for refactoring assistance
