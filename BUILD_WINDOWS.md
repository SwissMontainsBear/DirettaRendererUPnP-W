# Building Diretta UPnP Renderer for Windows

## Step 1: Install Visual Studio Build Tools

You need the C++ compiler from Microsoft.

1. Download **Build Tools for Visual Studio 2022** from:
   https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022

2. Run the installer

3. Select **"Desktop development with C++"** workload

4. Click Install and wait for completion

5. **Reboot your computer**

---

## Step 2: Install Git for Windows

1. Download from: https://git-scm.com/download/win

2. Run installer with default options

3. **Important:** Select "Git from the command line and also from 3rd-party software"

4. After install, open a **new** terminal to use git

---

## Step 3: Install vcpkg (Package Manager)

Open **"Developer Command Prompt for VS 2022"** (search in Start menu) and run:

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
vcpkg install ffmpeg:x64-windows libupnp:x64-windows
```

This will take several minutes. Wait for completion.

---

## Step 5: Build the Project

### Option A: Visual Studio IDE

1. Double-click `DirettaRendererUPnP.sln` (or `.vcxproj`) to open in Visual Studio

2. Select **Release | x64** in the toolbar

3. Build > Build Solution (or press Ctrl+Shift+B)

### Option B: Command Line

In Developer Command Prompt:

```cmd
cd C:\path\to\DirettaRendererUPnP-W
msbuild DirettaRendererUPnP.sln /p:Configuration=Release /p:Platform=x64
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

---

## Troubleshooting

### "Visual Studio not found" when running vcpkg

The C++ workload is not installed. Reinstall Build Tools with "Desktop development with C++" selected.

### "git not found"

Close your terminal and open a new one after installing Git.

### Complete Visual Studio Cleanup

If VS installation is corrupted:

1. Download cleanup tool: https://aka.ms/vs/installer/cleanup
2. Run as Administrator
3. Reboot
4. Install Build Tools fresh

### Missing DLLs at Runtime

Copy FFmpeg DLLs to the same folder as the .exe, or use static linking:
```cmd
vcpkg install ffmpeg:x64-windows-static libupnp:x64-windows-static
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
1. Install Build Tools for VS 2022 (with C++ workload)
2. Install Git for Windows
3. Clone and bootstrap vcpkg
4. vcpkg install ffmpeg:x64-windows libupnp:x64-windows
5. Open solution and build
```
