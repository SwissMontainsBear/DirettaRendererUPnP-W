# Building Diretta UPnP Renderer for Windows

> **Important**: This project requires **Visual Studio 2026** (version 18) with MSVC toolset **v145** (v14.50). The Diretta Host SDK libraries are compiled with this toolset and will not link with earlier Visual Studio versions.

---

## About the Windows Build Process

Due to the licensing terms of the Diretta Host SDK (personal use only, redistribution prohibited), we are unable to provide a pre-built installer or binary distribution for Windows.

However, as a courtesy to Windows users, we provide three integration utilities to simplify the build, launch, and deployment process:

| Utility | Description |
|---------|-------------|
| **`install.ps1`** | Build automation script - checks prerequisites, installs dependencies, compiles the project, and configures firewall |
| **`Start-DirettaRenderer.ps1`** | Enhanced launcher - auto-elevation, Npcap verification, configuration persistence, interactive menu |
| **`Install-Service.ps1`** | Windows service installer - appliance mode operation with auto-start at boot |

Users must still manually install Visual Studio 2026, Npcap, and download the Diretta Host SDK from [diretta.link](https://www.diretta.link).

---

## Quick Start (Automated)

If you have Visual Studio 2026, Git, Npcap, and the Diretta SDK already installed, you can use the automated installation script:

```powershell
# Run as Administrator in PowerShell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\install.ps1
```

The script will:
- Check all prerequisites and report what's missing
- Install/update vcpkg and dependencies
- Build the project
- Copy required DLLs
- Configure Windows Firewall

For manual step-by-step installation, continue below.

---

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

## Step 5: Install Npcap (Required for RAW Socket Mode)

Npcap is **mandatory** to enable Diretta MSMODE3 (RAW socket mode), which provides optimal performance for high-resolution audio streaming (DSD256/512/1024).

Without Npcap, the Diretta SDK falls back to MSMODE2 (UDP), which has lower performance and may cause audio issues at high sample rates.

1. Download Npcap from: https://npcap.com/#download

2. Run the installer **as Administrator**

3. **Important:** Select these options during installation:
   - ✅ **Install Npcap in WinPcap API-compatible Mode**
   - ❌ **Support raw 802.11 traffic (experimental)** unless you have wifi interface
   - ❌ **Install Npcap in Admin-only Mode** - Leave this **UNCHECKED** (unless you always run as Administrator)

4. Complete the installation and **reboot your computer**

### Verifying Npcap Installation

After reboot, verify Npcap sees your network adapters:

```cmd
"C:\Program Files\Npcap\dumpcap.exe" -D
```

You should see your network interfaces listed. The interface used for Diretta must appear here for RAW mode to work.

---

## Step 6: Build the Project

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

## Step 7: Copy DLLs

Copy required DLLs to the output folder (in case the linker has not done it):

```cmd
copy C:\vcpkg\installed\x64-windows\bin\*.dll bin\x64\Release\
```

---

## Step 8: Configure Windows Firewall

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

Copy DLLs from vcpkg (Step 7), or rebuild with static linking:
```cmd
vcpkg install ffmpeg:x64-windows-static libupnp[webserver]:x64-windows-static
```

### Diretta Falls Back to UDP Mode (MSMODE2)

If the renderer logs show UDP mode instead of RAW mode, Npcap is not working correctly:

1. **Verify Npcap is installed:**
   ```cmd
   "C:\Program Files\Npcap\dumpcap.exe" -D
   ```
   If this fails, reinstall Npcap.

2. **Check installation options:** Reinstall Npcap with:
   - ✅ WinPcap API-compatible Mode
   - ✅ Support raw 802.11 traffic
   - ❌ Admin-only Mode (unchecked)

3. **Reboot after installation** - Required for Npcap driver to load.

4. **Run as Administrator:** RAW sockets may require elevated privileges:
   ```cmd
   runas /user:Administrator DirettaRendererUPnP.exe --target 1
   ```

5. **USB-Ethernet adapters:** Some USB network adapters have driver limitations that prevent RAW socket mode. Try:
   - Using the onboard NIC instead
   - Using a PCIe NIC instead of USB
   - Updating the adapter's driver

### Npcap Not Detecting Network Interface

If `dumpcap -D` doesn't show your network adapter:

1. Check Device Manager for driver issues
2. Try reinstalling the network adapter driver
3. For USB adapters, try a different USB port
4. Some virtual/VPN adapters are not supported

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
5. Install Npcap (required for RAW socket mode / MSMODE3)
6. Build the project
7. Copy DLLs to output folder
8. Configure Windows Firewall
9. Run the renderer
```

---

## Running as a Windows Service (Appliance Mode)

For headless or appliance-style operation, you can install the renderer as a Windows service that starts automatically at boot.

### Installing the Service

```powershell
# Run as Administrator
.\Install-Service.ps1 -Install -Target 1 -Name "Living Room Diretta"
```

Or run interactively to be prompted for configuration:
```powershell
.\Install-Service.ps1 -Install
```

### Service Management Commands

| Command | Description |
|---------|-------------|
| `.\Install-Service.ps1 -Status` | Show service status and configuration |
| `.\Install-Service.ps1 -Start` | Start the service |
| `.\Install-Service.ps1 -Stop` | Stop the service |
| `.\Install-Service.ps1 -Restart` | Restart the service |
| `.\Install-Service.ps1 -Logs` | View recent log output |
| `.\Install-Service.ps1 -Configure` | Change service settings |
| `.\Install-Service.ps1 -Uninstall` | Remove the service |

You can also manage the service through Windows Services (`services.msc`):
- Service name: `DirettaRenderer`
- Display name: `Diretta UPnP Renderer`

### Service Features

- **Auto-start**: Starts automatically when Windows boots
- **Auto-restart**: Restarts automatically if the renderer crashes (5 second delay)
- **Log rotation**: Logs written to `logs\` folder with automatic rotation at 1MB
- **Configuration persistence**: Settings saved to `service-config.json`

### Log Files

Service logs are located at:
```
logs\diretta-stdout.log   # Standard output
logs\diretta-stderr.log   # Error output
```

To follow logs in real-time:
```powershell
Get-Content .\logs\diretta-stdout.log -Wait -Tail 20
```
