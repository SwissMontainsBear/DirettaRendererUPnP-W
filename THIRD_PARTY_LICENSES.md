# Third-Party Licenses

This software uses the following third-party libraries:

---

## FFmpeg

**License:** LGPL 2.1+ (as built by vcpkg without GPL components)

**Website:** https://ffmpeg.org/

**Source Code:** https://github.com/FFmpeg/FFmpeg

The FFmpeg libraries (avformat, avcodec, avutil, swresample) are dynamically linked
as separate DLL files. Users may replace these DLLs with their own LGPL-compatible
versions.

**Files:**
- avformat-*.dll
- avcodec-*.dll
- avutil-*.dll
- swresample-*.dll

**FFmpeg License (LGPL 2.1):**

See `licenses/LGPL-2.1.txt` for the full license text.

**FFmpeg Copyright Notice:**

```
FFmpeg is free software; you can redistribute it and/or modify it under the terms
of the GNU Lesser General Public License as published by the Free Software Foundation;
either version 2.1 of the License, or (at your option) any later version.

FFmpeg is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU Lesser General Public License for more details.
```

---

## libupnp (Portable SDK for UPnP Devices)

**License:** BSD 3-Clause

**Website:** https://pupnp.github.io/pupnp/

**Source Code:** https://github.com/pupnp/pupnp

**Files:**
- libupnp.dll (or statically linked)
- ixml.dll (or statically linked)

**libupnp License:**

See `licenses/BSD-3-Clause-libupnp.txt` for the full license text.

---

## Diretta Host SDK

**License:** Proprietary - Personal Use Only

**Website:** https://www.diretta.link/

**Owner:** Yu Harada

The Diretta Host SDK is NOT included in this distribution. Users must download
it separately from the official website. The SDK is licensed for personal,
non-commercial use only. Commercial use requires separate licensing from Yu Harada.

---

## How to Obtain Source Code

### FFmpeg Source Code

FFmpeg source code can be obtained from:

1. **Official Website:** https://ffmpeg.org/download.html
2. **GitHub Mirror:** https://github.com/FFmpeg/FFmpeg
3. **vcpkg port:** https://github.com/microsoft/vcpkg/tree/master/ports/ffmpeg

To build FFmpeg from source with the same configuration as vcpkg:

```bash
git clone https://github.com/FFmpeg/FFmpeg.git
cd FFmpeg
git checkout n7.1  # or the version matching your DLLs
./configure --enable-shared --enable-gpl --enable-version3
make
```

### libupnp Source Code

libupnp source code can be obtained from:

1. **GitHub:** https://github.com/pupnp/pupnp
2. **vcpkg port:** https://github.com/microsoft/vcpkg/tree/master/ports/libupnp

---

## Your Rights Under LGPL

As a user of this software, you have the right to:

1. **Replace FFmpeg DLLs** with your own versions (e.g., newer versions, custom builds)
2. **Obtain FFmpeg source code** from the links above
3. **Modify FFmpeg** and use your modified version with this software
4. **Distribute FFmpeg** under the terms of the LGPL

The main application (DirettaRendererUPnP) is licensed under MIT and is NOT
subject to LGPL copyleft requirements because FFmpeg is dynamically linked.
