# Installation Guide - Diretta UPnP Renderer

Complete step-by-step installation guide for the Diretta UPnP Renderer.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Preparing Your System](#preparing-your-system)
3. [Installing Dependencies](#installing-dependencies)
4. [Downloading Diretta SDK](#downloading-diretta-sdk)
5. [Building the Renderer](#building-the-renderer)
6. [Network Configuration](#network-configuration)
7. [First Run](#first-run)
8. [Creating a Systemd Service](#creating-a-systemd-service)
9. [Listing and Selecting Diretta Targets](#listing-and-selecting-diretta-targets)
10. [Windows Installation](#windows-installation)

---

## System Requirements

### Minimum Hardware
- **CPU**: x86_64 processor (Intel/AMD)
- **RAM**: 2 GB minimum, 4 GB recommended
- **Network**: Gigabit Ethernet with jumbo frame support
- **Storage**: 100 MB for software + space for music files

### Recommended Hardware
- **CPU**: Modern multi-core processor for Hi-Res decoding
- **RAM**: 8 GB for optimal performance
- **Network**: 
  - Network card with RTL8125 chipset (or similar) supporting 16k MTU
  - Managed switch with jumbo frame support
  - Low-latency network infrastructure

### Compatible DACs
Any Diretta-compatible DAC, including:
- Holo Audio Spring 3
- Musician Pegasus
- Other DACs with Diretta protocol support

### Supported Operating Systems
- **Fedora** 38+ (tested)
- **AudioLinux** (tested, recommended for audiophiles)
- **Ubuntu/Debian** 22.04+
- **Arch Linux** (with manual dependency management)
- Other Linux distributions (may require adaptation)

---

## Preparing Your System

### 1. Update Your System

```bash
# Fedora/RHEL
sudo dnf update -y

# Debian/Ubuntu
sudo apt update && sudo apt upgrade -y

# Arch/AudioLinux
sudo pacman -Syu
```

### 2. Check Network Interface

```bash
# List network interfaces
ip link show

# Check current MTU (should show 1500 by default)
ip link show enp4s0 | grep mtu

# Note your interface name (e.g., enp4s0, eth0, etc.)
```

### 3. Install Build Tools

```bash
# Fedora/RHEL
sudo dnf groupinstall "Development Tools" -y

# Debian/Ubuntu
sudo apt install build-essential -y

# Arch/AudioLinux
sudo pacman -S base-devel
```

---

## Installing Dependencies

### Fedora / RHEL / CentOS

```bash
# Install FFmpeg libraries
sudo dnf install -y \
    ffmpeg-devel \
    libavformat-devel \
    libavcodec-devel \
    libavutil-devel \
    libswresample-devel

# Install UPnP library
sudo dnf install -y libupnp-devel

# Install additional tools
sudo dnf install -y git wget
```

### Debian / Ubuntu

```bash
# Install FFmpeg libraries
sudo apt install -y \
    libavformat-dev \
    libavcodec-dev \
    libavutil-dev \
    libswresample-dev

# Install UPnP library
sudo apt install -y libupnp-dev

# Install additional tools
sudo apt install -y git wget
```

### Arch Linux / AudioLinux

```bash
# Install FFmpeg (usually pre-installed on AudioLinux)
sudo pacman -S ffmpeg

# Install UPnP library
sudo pacman -S libupnp

# Install git if needed
sudo pacman -S git
```

### Verify Installation

```bash
# Check FFmpeg libraries
pkg-config --modversion libavformat libavcodec libavutil libswresample

# Check UPnP library
pkg-config --modversion libupnp

# Should show version numbers for all
```

---

## Downloading Diretta SDK

### 1. Get the SDK

1. **Visit**: https://www.diretta.link/hostsdk.html
2. **Navigate to**: "Download Preview" section
3. **Download**: DirettaHostSDK_147.tar.gz (or latest version)

### 2. Extract the SDK

```bash

# Extract SDK to home directory
cd ~
tar xzf ~/Downloads/DirettaHostSDK_147.tar.gz

# Verify extraction
ls -la ~/DirettaHostSDK_147/
# Should show: Host/, lib/, include/, etc.
```

### 3. Set SDK Environment Variable (Optional not needed)

```bash
# Add to ~/.bashrc for convenience
echo 'export DIRETTA_SDK_PATH=~/DirettaHostSDK_147' >> ~/.bashrc
source ~/.bashrc
```

---

## Building the Renderer

### 1. Clone the Repository

```bash

git clone https://github.com/cometdom/DirettaRendererUPnP.git
cd DirettaRendererUPnP
```

```bash
# Clone repository
git clone https://github.com/cometdom/DirettaRendererUPnP.git
cd DirettaRendererUPnP

# Build (Makefile auto-detects SDK location)
make

# Install service
cd systemd
chmod +x install-systemd.sh
sudo ./install-systemd.sh

#Next steps:
 1. Edit configuration (optional):
     sudo nano /opt/diretta-renderer-upnp/diretta-renderer.conf
 2. Reload daemon:
     sudo systemctl daemon-reload
 3. Enable the service:
     sudo systemctl enable diretta-renderer
 4. Start the service:
     sudo systemctl start diretta-renderer
 5. Check status:
     sudo systemctl status diretta-renderer 
 6. View logs:
     sudo journalctl -u diretta-renderer -f
 7. Stop the service:
     sudo systemctl stop diretta-renderer
 8. Disable auto-start:
     sudo systemctl disable diretta-renderer       


### 3. Verify Binary

```bash
ls -lh bin/DirettaRendererUPnP
# Should show the executable

# Check dependencies
ldd bin/DirettaRendererUPnP
# Should NOT show "not found" errors
```

---

## Network Configuration

### 1. Enable Jumbo Frames

```bash
# Temporary (lost after reboot)
sudo ip link set enp4s0 mtu 9000

# Verify
ip link show enp4s0 | grep mtu
# Should show: mtu 9000
```

### 2. Make Jumbo Frames Permanent

#### Method A: NetworkManager (Fedora/Ubuntu Desktop)

```bash
# Get connection name
nmcli connection show

# Set MTU
sudo nmcli connection modify "Wired connection 1" 802-3-ethernet.mtu 9000

# Restart connection
sudo nmcli connection down "Wired connection 1"
sudo nmcli connection up "Wired connection 1"
```

#### Method B: systemd-networkd

Create `/etc/systemd/network/10-ethernet.network`:

```ini
[Match]
Name=enp4s0

[Network]
DHCP=yes

[Link]
MTUBytes=9000
```

Then restart:
```bash
sudo systemctl restart systemd-networkd
```

#### Method C: /etc/network/interfaces (Debian)

Edit `/etc/network/interfaces`:

```
auto enp4s0
iface enp4s0 inet dhcp
    mtu 9000
```

### 3. Configure Your Network Switch

**Important**: Your network switch MUST support jumbo frames!

- Enable jumbo frames in switch management interface
- Typical setting: MTU 9000 or 9216
- Verify all devices in the path support jumbo frames

### 4. Test Network Performance

```bash
# Install iperf3 for testing
sudo dnf install iperf3  # or apt install iperf3

# On DAC computer (if accessible):
iperf3 -s

# On renderer computer:
iperf3 -c <DAC_IP_ADDRESS>
# Should show high throughput (900+ Mbps on Gigabit)
```

---

## First Run

### 1. Check Permissions

```bash
# The renderer needs root for raw network access
# Verify you can run with sudo
sudo -v
```

### 2. Start the Renderer

```bash
cd ~/audio-projects/DirettaUPnPRenderer/bin
sudo ./DirettaRendererUPnP --port 4005 --buffer 2.0
```

### 3. Expected Output

You should see:
```
═══════════════════════════════════════════════════════
  🎵 Diretta UPnP Renderer - Complete Edition
═══════════════════════════════════════════════════════

Configuration:
  Name:        Diretta Renderer
  Port:        4005
  Gapless:     enabled
  Buffer:      2 seconds

[DirettaRenderer] Created
🚀 Starting renderer...
[UPnP Thread] Started
[Audio Thread] Started
✓ Renderer started successfully!

📡 Waiting for UPnP control points...
```

### 4. Test Discovery

From your phone/tablet with JPlay or BubbleUPnP:
1. Open the app
2. Look for "Diretta Renderer" in available devices
3. Select it as output
4. Try playing a track

### 5. Stop the Renderer

Press `Ctrl+C` to stop gracefully.

---

## Creating a Systemd Service

See [SYSTEM_GUIDE](SYSTEMD_GUIDE.md)
---

## Listing and Selecting Diretta Targets

Before running the renderer as a service, it is recommended to scan the network and identify available Diretta targets.

### 1. List Available Targets

From the project root (or any directory containing the built binary):

```bash
sudo ./bin/DirettaRendererUPnP --list-targets
```

Example output:

```text
[1] Target #1
    IP Address: fe80::5c53:8aff:fefb:f63a,19644
    MTU: 1500 bytes

[2] Target #2
    IP Address: fe80::5c53:8aff:fefb:f63a,19646
    MTU: 1500 bytes

[3] Target #3
    IP Address: fe80::5c53:8aff:fefb:f63a,19648
    MTU: 1500 bytes
```

Here:

- `Target #1 / #2 / #3` are internal indices used by the renderer
- `IP Address` and `MTU` can help you distinguish different Diretta devices

### 2. Select a Target by Index

Once you know which target you want to use, you can pass its index to the renderer:

```bash
# Run directly in foreground
sudo ./bin/DirettaRendererUPnP --target 1 --port 4005 --buffer 2.0
```

When using the systemd service, the same index is passed via `generate_service.sh`:

```bash
sudo TARGET_INDEX=1 ./generate_service.sh
sudo systemctl daemon-reload
sudo systemctl restart diretta-renderer
```

If `--target` is not specified and only one Diretta target is found, the renderer will automatically use it.
If multiple targets are detected without a specified index, the renderer may enter interactive selection mode.

---

### 1. CPU Performance Mode

```bash
# Set CPU governor to performance
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### 2. Real-Time Priority (Advanced)

Edit service file to add:
```ini
[Service]
Nice=-10
IOSchedulingClass=realtime
IOSchedulingPriority=0
```

### 3. Disable Power Management

```bash
# Disable USB autosuspend
echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend
```

---

## Troubleshooting Installation

### Build Errors

**Error**: `cannot find -lDirettaHost_x64-linux-15v3`
- **Solution**: Check SDK path in Makefile

**Error**: `fatal error: libavformat/avformat.h: No such file`
- **Solution**: Install FFmpeg development packages

**Error**: `fatal error: upnp/upnp.h: No such file`
- **Solution**: Install libupnp-devel

### Runtime Errors

**Error**: `No Diretta target found`
- Check DAC is powered on
- Verify network connection
- Check firewall settings

**Error**: `Permission denied`
- Use `sudo` to run
- Check file permissions

---

## Next Steps

- Configure your UPnP control point → See README.md
- Troubleshoot issues → See TROUBLESHOOTING.md
- Optimize settings → See CONFIGURATION.md

---

**Installation complete!** You're ready to enjoy bit-perfect audio streaming!

---

## Windows Installation

### System Requirements (Windows)

- **OS**: Windows 10/11 (x64 or ARM64)
- **Visual Studio 2026** (version 18) with MSVC toolset v14.50 (v145)
- **vcpkg**: For managing FFmpeg and libupnp dependencies

> **Critical**: The Diretta Host SDK Windows libraries are compiled with MSVC 14.50 (Visual Studio 2026). Using earlier versions (VS 2022 or older) will result in linker error:
> ```
> LINK : fatal error C1900: Il mismatch between 'P1' version and 'P2' version
> ```

### 1. Install Visual Studio 2026

1. Download [Visual Studio 2026](https://visualstudio.microsoft.com/downloads/)
2. Run the installer and select:
   - **Workload**: "Desktop development with C++"
   - **Individual Components**:
     - MSVC v145 - VS 2026 C++ x64/x86 build tools (v14.50)
     - MSVC v145 - VS 2026 C++ ARM64 build tools (v14.50) *(for ARM64 builds)*
     - Windows 10/11 SDK (latest)
     - C++ CMake tools for Windows

### 2. Install and Configure vcpkg

```powershell
# Clone vcpkg
git clone https://github.com/microsoft/vcpkg.git C:\vcpkg
cd C:\vcpkg

# Bootstrap vcpkg (use VS 2026 developer prompt)
.\bootstrap-vcpkg.bat

# Set environment variable (optional, for convenience)
[Environment]::SetEnvironmentVariable("VCPKG_ROOT", "C:\vcpkg", "User")
```

### 3. Install Dependencies

Open **"x64 Native Tools Command Prompt for VS 2026"** (important: must be x64, not x86):

```powershell
cd C:\vcpkg

# Install FFmpeg and libupnp for x64
.\vcpkg.exe install ffmpeg:x64-windows libupnp:x64-windows

# For ARM64 builds:
.\vcpkg.exe install ffmpeg:arm64-windows libupnp:arm64-windows
```

**Note**: If vcpkg doesn't recognize VS 2026, set environment variables:

```powershell
$env:VisualStudioVersion = "18.0"
$env:VCINSTALLDIR = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\"
```

### 4. Download Diretta Host SDK (Windows)

1. Visit [diretta.link/hostsdk.html](https://www.diretta.link/hostsdk.html)
2. Download **DirettaHostSDK_147** (Windows version)
3. Extract to `C:\DirettaRendererUPnP\DirettaHostSDK_147`

Verify the following files exist:
```
C:\DirettaRendererUPnP\DirettaHostSDK_147\
├── Host\
│   └── DirettaSync.h
├── lib\
│   ├── libDirettaHost_x64-win.lib
│   ├── libDirettaHost_arm64-win.lib
│   ├── libACQUA_x64-win.lib
│   └── libACQUA_arm64-win.lib
```

### 5. Clone the Repository

```powershell
cd C:\DirettaRendererUPnP
git clone https://github.com/YourRepo/DirettaRendererUPnP-W.git
cd DirettaRendererUPnP-W
```

### 6. Build the Project

#### Option A: Command Line (MSBuild)

```powershell
# Open "x64 Native Tools Command Prompt for VS 2026"
cd C:\DirettaRendererUPnP\DirettaRendererUPnP-W

# Clean previous builds
Remove-Item -Recurse -Force .\x64, .\obj, .\bin -ErrorAction SilentlyContinue

# Build Release x64
msbuild DirettaRendererUPnP.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=x64

# Build Release ARM64
msbuild DirettaRendererUPnP.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=ARM64
```

#### Option B: Visual Studio IDE

1. Open `DirettaRendererUPnP.vcxproj` in Visual Studio 2026
2. Select **Release** | **x64** (or ARM64)
3. Build → Rebuild Solution

### 7. Verify Build

```powershell
# Check the executable was created
dir .\bin\x64\Release\DirettaRendererUPnP.exe

# Check dependencies
dumpbin /dependents .\bin\x64\Release\DirettaRendererUPnP.exe
```

### 8. Run on Windows

```powershell
# Run as Administrator (required for network operations)
cd C:\DirettaRendererUPnP\DirettaRendererUPnP-W

# List available Diretta targets
.\bin\x64\Release\DirettaRendererUPnP.exe --list-targets

# Run with specific target
.\bin\x64\Release\DirettaRendererUPnP.exe --target 1 --port 4005
```

### Windows Firewall Configuration

**Critical**: The renderer will not be discoverable without proper firewall rules.

Run as Administrator:

```powershell
# Allow the application (adjust path if installed elsewhere)
netsh advfirewall firewall add rule name="Diretta Renderer" dir=in action=allow program="C:\DirettaRendererUPnP\DirettaRendererUPnP-W\bin\x64\Release\DirettaRendererUPnP.exe" enable=yes profile=any
netsh advfirewall firewall add rule name="Diretta Renderer Out" dir=out action=allow program="C:\DirettaRendererUPnP\DirettaRendererUPnP-W\bin\x64\Release\DirettaRendererUPnP.exe" enable=yes profile=any

# Allow SSDP discovery (required for UPnP device discovery)
netsh advfirewall firewall add rule name="UPnP SSDP Discovery" dir=in action=allow protocol=udp localport=1900 enable=yes profile=any
netsh advfirewall firewall add rule name="UPnP SSDP Multicast" dir=out action=allow protocol=udp remoteport=1900 enable=yes profile=any

# Allow UPnP HTTP (dynamic ports used by libupnp)
netsh advfirewall firewall add rule name="UPnP HTTP" dir=in action=allow protocol=tcp localport=49152-65535 enable=yes profile=any
```

**Verify rules are created:**
```powershell
netsh advfirewall firewall show rule name="Diretta Renderer"
netsh advfirewall firewall show rule name="UPnP SSDP Discovery"
```

**To remove rules later:**
```powershell
netsh advfirewall firewall delete rule name="Diretta Renderer"
netsh advfirewall firewall delete rule name="Diretta Renderer Out"
netsh advfirewall firewall delete rule name="UPnP SSDP Discovery"
netsh advfirewall firewall delete rule name="UPnP SSDP Multicast"
netsh advfirewall firewall delete rule name="UPnP HTTP"
```

### Troubleshooting Windows Build

#### Error: `C1900: Il mismatch between 'P1' version and 'P2' version`

The Diretta SDK libraries require MSVC 14.50 (VS 2026). Solutions:
1. Install Visual Studio 2026
2. Or contact Diretta for libraries compiled with your VS version

To check which compiler version a library requires:
```powershell
dumpbin /rawdata DirettaHostSDK_147\lib\libDirettaHost_x64-win.lib | findstr "Microsoft Visual Studio"
```

#### Error: `Unable to find a valid Visual Studio instance` (vcpkg)

```powershell
# Set VS 2026 path explicitly
$env:VCINSTALLDIR = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\"
.\vcpkg.exe install ffmpeg:x64-windows
```

#### Error: `LNK2019: unresolved external symbol`

Ensure all libraries are built with the same toolset (v145). Rebuild vcpkg packages:
```powershell
.\vcpkg.exe remove ffmpeg:x64-windows libupnp:x64-windows
.\vcpkg.exe install ffmpeg:x64-windows libupnp:x64-windows
```

---

**Windows installation complete!** You're ready to enjoy bit-perfect audio streaming on Windows!
