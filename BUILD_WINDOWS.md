# Building Diretta UPnP Renderer for Windows

> **Important**: This project requires **Visual Studio 2026** (version 18) with MSVC toolset **v145** (v14.50). The Diretta Host SDK libraries are compiled with this toolset and will not link with earlier Visual Studio versions.

## Step 1: Install Visual Studio 2026

You need the C++ compiler from Microsoft.

1. Download **Visual Studio 2026** from:
   https://visualstudio.microsoft.com/downloads/

2. Run the installer

3. Select **"Desktop development with C++"** workload

4. In Individual Components, ensure these are selected:
   - MSVC v145 - VS 2026 C++ x64/x86 build tools (v14.50)
   - Windows 10/11 SDK (latest)

5. Click Install and wait for completion

6. **Reboot your computer**

---

## Step 2: Install Git for Windows

1. Download from: https://git-scm.com/download/win

2. Run installer with default options

3. **Important:** Select "Git from the command line and also from 3rd-party software"

4. After install, open a **new** terminal to use git

---

## Step 3: Install vcpkg (Package Manager)

Open **"x64 Native Tools Command Prompt for VS 2026"** (search in Start menu) and run:

```cmd
cd C:\
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
bootstrap-vcpkg.bat
vcpkg integrate install
```

---

## Step 4: Install Dependencies

In the same Developer Command Prompt:

```cmd
cd C:\vcpkg
vcpkg install ffmpeg:x64-windows libupnp[webserver]:x64-windows
```

This will take several minutes. Wait for completion.

> **Note:** The `[webserver]` feature is required for libupnp to include device/server functionality.

---

## Step 5: Build the Project

### Option A: Visual Studio IDE

1. Double-click `DirettaRendererUPnP.vcxproj` to open in Visual Studio 2026

2. Select **Release | x64** in the toolbar

3. Build > Build Solution (or press Ctrl+Shift+B)

### Option B: Command Line

In x64 Native Tools Command Prompt for VS 2026:

```cmd
cd C:\DirettaRendererUPnP\DirettaRendererUPnP-W
msbuild DirettaRendererUPnP.vcxproj /p:Configuration=Release /p:Platform=x64
```

---

## Step 6: Copy DLLs

Copy required DLLs to the output folder:

```cmd
copy C:\vcpkg\installed\x64-windows\bin\*.dll bin\x64\Release\
```

---

## Step 7: Configure Windows Firewall

Run as Administrator:

```cmd
netsh advfirewall firewall add rule name="Diretta Renderer" dir=in action=allow program="C:\DirettaRendererUPnP\DirettaRendererUPnP-W\bin\x64\Release\DirettaRendererUPnP.exe" enable=yes profile=any
netsh advfirewall firewall add rule name="Diretta Renderer Out" dir=out action=allow program="C:\DirettaRendererUPnP\DirettaRendererUPnP-W\bin\x64\Release\DirettaRendererUPnP.exe" enable=yes profile=any
netsh advfirewall firewall add rule name="UPnP SSDP Discovery" dir=in action=allow protocol=udp localport=1900 enable=yes profile=any
netsh advfirewall firewall add rule name="UPnP SSDP Multicast" dir=out action=allow protocol=udp remoteport=1900 enable=yes profile=any
netsh advfirewall firewall add rule name="UPnP HTTP" dir=in action=allow protocol=tcp localport=49152-65535 enable=yes profile=any
```

---

## Output

The executable will be in:
```
bin\x64\Release\DirettaRendererUPnP.exe
```

---

## Running

```cmd
DirettaRendererUPnP.exe --list-targets
DirettaRendererUPnP.exe --target 1 --name "My Renderer"
```

Or use the launcher scripts:
- `Launch-DirettaRenderer.bat` - Interactive menu
- `QuickStart-DirettaRenderer.bat` - One-click start

---

## Troubleshooting

### Error: `C1900: Il mismatch between 'P1' version and 'P2' version`

The Diretta SDK requires MSVC 14.50 (VS 2026). You must use Visual Studio 2026, not VS 2022 or earlier.

### "Visual Studio not found" when running vcpkg

The C++ workload is not installed. Reinstall Visual Studio 2026 with "Desktop development with C++" selected.

### "git not found"

Close your terminal and open a new one after installing Git.

### vcpkg doesn't recognize VS 2026

Set environment variables:
```cmd
set VCINSTALLDIR=C:\Program Files\Microsoft Visual Studio\18\Community\VC\
vcpkg install ffmpeg:x64-windows libupnp[webserver]:x64-windows
```

### Renderer not discoverable

1. Check Windows Firewall rules are configured (Step 7)
2. Ensure SSDP Discovery service is running:
   ```cmd
   net start SSDPSRV
   ```

### Missing DLLs at Runtime

Copy DLLs from vcpkg (Step 6), or rebuild with static linking:
```cmd
vcpkg install ffmpeg:x64-windows-static libupnp[webserver]:x64-windows-static
```

---

## Required SDK

The Diretta Host SDK must be present at:
```
..\DirettaHostSDK_147\
```

This contains:
- `lib\libDirettaHost_x64-win.lib`
- `lib\libACQUA_x64-win.lib`
- `Host\` (header files)

---

## Architecture Support

| Platform | Diretta Library | vcpkg triplet |
|----------|-----------------|---------------|
| x64 (64-bit) | `libDirettaHost_x64-win.lib` | `x64-windows` |
| ARM64 | `libDirettaHost_arm64-win.lib` | `arm64-windows` |

---

## Summary

```
1. Install Visual Studio 2026 (with C++ workload, v145 toolset)
2. Install Git for Windows
3. Clone and bootstrap vcpkg
4. vcpkg install ffmpeg:x64-windows libupnp[webserver]:x64-windows
5. Build the project
6. Copy DLLs to output folder
7. Configure Windows Firewall
8. Run the renderer
```
