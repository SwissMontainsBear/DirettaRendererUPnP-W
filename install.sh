#!/bin/bash
#
# Diretta UPnP Renderer - Windows Installation Script (MSYS2/MinGW)
#
# This script helps install dependencies and set up the renderer on Windows.
# Run from MSYS2 MinGW64 shell: bash install.sh
#
# For native Windows builds, use Visual Studio with vcpkg instead.
#

set -e  # Exit on error

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_PATH="${DIRETTA_SDK_PATH:-$HOME/DirettaHostSDK_147}"
FFMPEG_BUILD_DIR="/tmp/ffmpeg-build"
FFMPEG_HEADERS_DIR="$SCRIPT_DIR/ffmpeg-headers"
FFMPEG_TARGET_VERSION="8.0.1"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_header()  { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local response

    if [[ "$default" =~ ^[Yy]$ ]]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-Y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-N}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# =============================================================================
# SYSTEM DETECTION
# =============================================================================

detect_system() {
    print_header "System Detection"

    # Detect environment
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "mingw"* ]]; then
        ENV_TYPE="msys2"
        print_success "Detected: MSYS2/MinGW environment"
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        ENV_TYPE="cygwin"
        print_success "Detected: Cygwin environment"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Could be WSL
        if grep -qi microsoft /proc/version 2>/dev/null; then
            ENV_TYPE="wsl"
            print_success "Detected: Windows Subsystem for Linux (WSL)"
        else
            ENV_TYPE="linux"
            print_success "Detected: Native Linux"
        fi
    else
        ENV_TYPE="unknown"
        print_warning "Unknown environment: $OSTYPE"
    fi

    # Detect architecture
    ARCH=$(uname -m)
    print_info "Architecture: $ARCH"

    # Check for MINGW64
    if [[ "$MSYSTEM" == "MINGW64" ]]; then
        print_success "Running in MINGW64 (64-bit) - recommended"
    elif [[ "$MSYSTEM" == "MINGW32" ]]; then
        print_warning "Running in MINGW32 (32-bit) - 64-bit recommended"
    elif [[ "$MSYSTEM" == "UCRT64" ]]; then
        print_success "Running in UCRT64 (Universal C Runtime)"
    fi
}

# =============================================================================
# MSYS2/MINGW DEPENDENCIES
# =============================================================================

install_msys2_dependencies() {
    print_header "Installing MSYS2/MinGW Dependencies"

    if [[ "$ENV_TYPE" != "msys2" ]]; then
        print_error "This function requires MSYS2/MinGW environment"
        print_info "Install MSYS2 from: https://www.msys2.org/"
        return 1
    fi

    print_info "Using pacman package manager..."

    # Update package database
    pacman -Sy --noconfirm

    # Install base development tools
    pacman -S --needed --noconfirm \
        base-devel \
        git \
        wget \
        unzip

    # Install MinGW64 toolchain and libraries
    if [[ "$MSYSTEM" == "MINGW64" ]] || [[ "$MSYSTEM" == "UCRT64" ]]; then
        local prefix="mingw-w64-x86_64"
        [[ "$MSYSTEM" == "UCRT64" ]] && prefix="mingw-w64-ucrt-x86_64"

        pacman -S --needed --noconfirm \
            ${prefix}-gcc \
            ${prefix}-make \
            ${prefix}-pkg-config \
            ${prefix}-libupnp

        print_success "MinGW64 dependencies installed"
    elif [[ "$MSYSTEM" == "MINGW32" ]]; then
        pacman -S --needed --noconfirm \
            mingw-w64-i686-gcc \
            mingw-w64-i686-make \
            mingw-w64-i686-pkg-config \
            mingw-w64-i686-libupnp

        print_success "MinGW32 dependencies installed"
    else
        print_error "Please run from MINGW64 or MINGW32 shell"
        return 1
    fi
}

# =============================================================================
# WSL DEPENDENCIES (Linux packages for cross-compilation or native Linux build)
# =============================================================================

install_wsl_dependencies() {
    print_header "Installing WSL Dependencies"

    if [[ "$ENV_TYPE" != "wsl" ]] && [[ "$ENV_TYPE" != "linux" ]]; then
        print_error "This function requires WSL or Linux environment"
        return 1
    fi

    # Detect distro
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        print_info "Detected: $PRETTY_NAME"
    else
        print_error "Cannot detect Linux distribution"
        return 1
    fi

    case $OS in
        ubuntu|debian)
            print_info "Using APT package manager..."
            sudo apt update
            sudo apt install -y \
                build-essential \
                git \
                libupnp-dev \
                wget \
                nasm \
                yasm \
                pkg-config
            ;;
        fedora)
            print_info "Using DNF package manager..."
            sudo dnf install -y \
                gcc-c++ \
                make \
                git \
                libupnp-devel \
                wget \
                nasm \
                yasm \
                pkg-config
            ;;
        *)
            print_error "Unsupported distribution: $OS"
            return 1
            ;;
    esac

    print_success "WSL/Linux dependencies installed"
}

# =============================================================================
# FFMPEG INSTALLATION
# =============================================================================

# Minimal FFmpeg 8.x configure options - streamlined audio-only build
get_ffmpeg_8_minimal_opts() {
    cat <<'OPTS'
--prefix=/usr
--enable-shared
--disable-static
--enable-small
--enable-gpl
--enable-version3
--enable-gnutls
--disable-everything
--disable-doc
--disable-avdevice
--disable-swscale
--enable-protocol=file,http,https,tcp
--enable-demuxer=flac,wav,dsf,dff,aac,mov
--enable-decoder=flac,alac,pcm_s16le,pcm_s24le,pcm_s32le,dsd_lsbf,dsd_msbf,dsd_lsbf_planar,dsd_msbf_planar,aac
--enable-muxer=flac,wav
--enable-filter=aresample
OPTS
}

# Full FFmpeg configure options for audio-only build
get_ffmpeg_configure_opts() {
    cat <<'OPTS'
--prefix=/usr/local
--disable-debug
--enable-shared
--disable-stripping
--disable-autodetect
--enable-gnutls
--enable-gpl
--enable-postproc
--enable-swresample
--disable-encoders
--disable-decoders
--disable-hwaccels
--disable-muxers
--disable-demuxers
--disable-parsers
--disable-bsfs
--disable-protocols
--disable-indevs
--disable-outdevs
--disable-devices
--disable-filters
--disable-doc
--enable-muxer=flac,mov,ipod,wav,w64,ffmetadata
--enable-demuxer=flac,mov,wav,w64,ffmetadata,dsf,dff,aac,hls,mpegts,mp3,ogg,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,lavfi
--enable-encoder=alac,flac,pcm_s16le,pcm_s24le,pcm_s32le
--enable-decoder=alac,flac,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,dsd_lsbf,dsd_msbf,dsd_lsbf_planar,dsd_msbf_planar,vorbis,aac,aac_fixed,aac_latm,mp3,mp3float,mjpeg,png
--enable-parser=aac,aac_latm,flac,vorbis,mpegaudio,mjpeg
--enable-protocol=file,pipe,http,https,tcp,hls
--enable-filter=aresample,hdcd,sine,anull
--enable-version3
OPTS
}

install_ffmpeg_msys2() {
    print_header "FFmpeg Installation (MSYS2)"

    echo "FFmpeg installation options for MSYS2/MinGW:"
    echo ""
    echo "  1) Install pre-built FFmpeg from MSYS2 (recommended)"
    echo "     - Quick installation via pacman"
    echo "     - Full codec support including DSD"
    echo ""
    echo "  2) Build FFmpeg 8.0.1 minimal from source"
    echo "     - Latest version, minimal audio-only build"
    echo "     - Smallest footprint"
    echo ""
    echo "  3) Build FFmpeg 7.1 from source"
    echo "     - Latest stable with full audio support"
    echo ""

    read -p "Choose option [1-3] (default: 1): " FFMPEG_OPTION
    FFMPEG_OPTION=${FFMPEG_OPTION:-1}

    case $FFMPEG_OPTION in
        1)
            install_ffmpeg_msys2_prebuilt
            ;;
        2)
            build_ffmpeg_msys2 "8.0.1" "minimal"
            ;;
        3)
            build_ffmpeg_msys2 "7.1" "full"
            ;;
        *)
            print_error "Invalid option: $FFMPEG_OPTION"
            return 1
            ;;
    esac
}

install_ffmpeg_msys2_prebuilt() {
    print_info "Installing pre-built FFmpeg from MSYS2..."

    local prefix="mingw-w64-x86_64"
    [[ "$MSYSTEM" == "UCRT64" ]] && prefix="mingw-w64-ucrt-x86_64"
    [[ "$MSYSTEM" == "MINGW32" ]] && prefix="mingw-w64-i686"

    pacman -S --needed --noconfirm \
        ${prefix}-ffmpeg

    print_success "FFmpeg installed from MSYS2 packages"
    test_ffmpeg_installation
}

build_ffmpeg_msys2() {
    local version="$1"
    local mode="${2:-full}"

    print_info "Building FFmpeg $version from source ($mode mode)..."

    # Install build dependencies
    local prefix="mingw-w64-x86_64"
    [[ "$MSYSTEM" == "UCRT64" ]] && prefix="mingw-w64-ucrt-x86_64"
    [[ "$MSYSTEM" == "MINGW32" ]] && prefix="mingw-w64-i686"

    pacman -S --needed --noconfirm \
        ${prefix}-gnutls \
        ${prefix}-nasm \
        ${prefix}-yasm

    mkdir -p "$FFMPEG_BUILD_DIR"
    cd "$FFMPEG_BUILD_DIR"

    local tarball="ffmpeg-${version}.tar.xz"
    local url="https://ffmpeg.org/releases/$tarball"

    if [ ! -f "$tarball" ]; then
        print_info "Downloading FFmpeg ${version}..."
        wget -q --show-progress "$url" || {
            print_error "Failed to download FFmpeg $version"
            return 1
        }
    fi

    print_info "Extracting FFmpeg..."
    tar xf "$tarball"
    cd "ffmpeg-${version}"

    print_info "Configuring FFmpeg..."
    make distclean 2>/dev/null || true

    local configure_opts
    if [[ "$mode" == "minimal" ]]; then
        configure_opts=$(get_ffmpeg_8_minimal_opts | tr '\n' ' ')
    else
        configure_opts=$(get_ffmpeg_configure_opts | tr '\n' ' ')
    fi

    ./configure $configure_opts

    print_info "Building FFmpeg (this may take a while)..."
    make -j$(nproc)

    print_info "Installing FFmpeg..."
    make install

    cd "$SCRIPT_DIR"
    rm -rf "$FFMPEG_BUILD_DIR"

    print_success "FFmpeg $version built and installed"
    test_ffmpeg_installation
}

install_ffmpeg_wsl() {
    print_header "FFmpeg Installation (WSL/Linux)"

    echo "FFmpeg installation options:"
    echo ""
    echo "  1) Install from system packages"
    echo "     - Quick installation"
    echo "     - May lack some codecs"
    echo ""
    echo "  2) Build FFmpeg 8.0.1 minimal from source (recommended)"
    echo "     - Latest version, minimal audio-only build"
    echo "     - Full DSD support"
    echo ""
    echo "  3) Build FFmpeg 7.1 from source"
    echo "     - Latest stable with full audio support"
    echo ""

    read -p "Choose option [1-3] (default: 2): " FFMPEG_OPTION
    FFMPEG_OPTION=${FFMPEG_OPTION:-2}

    case $FFMPEG_OPTION in
        1)
            install_ffmpeg_system_packages
            ;;
        2)
            build_ffmpeg_wsl "8.0.1" "minimal"
            ;;
        3)
            build_ffmpeg_wsl "7.1" "full"
            ;;
        *)
            print_error "Invalid option: $FFMPEG_OPTION"
            return 1
            ;;
    esac
}

install_ffmpeg_system_packages() {
    print_info "Installing FFmpeg from system packages..."

    case $OS in
        ubuntu|debian)
            sudo apt install -y \
                libavformat-dev \
                libavcodec-dev \
                libavutil-dev \
                libswresample-dev
            ;;
        fedora)
            sudo dnf install -y ffmpeg-free-devel || \
            sudo dnf install -y ffmpeg-devel
            ;;
    esac

    print_success "System FFmpeg installed"
    print_warning "Note: System FFmpeg may lack some audio codecs (e.g., DSD)"
    test_ffmpeg_installation
}

build_ffmpeg_wsl() {
    local version="$1"
    local mode="${2:-full}"

    print_info "Building FFmpeg $version from source ($mode mode)..."

    # Install build dependencies
    case $OS in
        ubuntu|debian)
            sudo apt install -y libgnutls28-dev nasm yasm
            ;;
        fedora)
            sudo dnf install -y gnutls-devel nasm yasm
            ;;
    esac

    mkdir -p "$FFMPEG_BUILD_DIR"
    cd "$FFMPEG_BUILD_DIR"

    local tarball="ffmpeg-${version}.tar.xz"
    local url="https://ffmpeg.org/releases/$tarball"

    if [ ! -f "$tarball" ]; then
        print_info "Downloading FFmpeg ${version}..."
        wget -q --show-progress "$url" || {
            print_error "Failed to download FFmpeg $version"
            return 1
        }
    fi

    print_info "Extracting FFmpeg..."
    tar xf "$tarball"
    cd "ffmpeg-${version}"

    print_info "Configuring FFmpeg..."
    make distclean 2>/dev/null || true

    local configure_opts
    if [[ "$mode" == "minimal" ]]; then
        configure_opts=$(get_ffmpeg_8_minimal_opts | tr '\n' ' ')
    else
        configure_opts=$(get_ffmpeg_configure_opts | tr '\n' ' ')
    fi

    ./configure $configure_opts

    print_info "Building FFmpeg (this may take a while)..."
    make -j$(nproc)

    print_info "Installing FFmpeg..."
    sudo make install
    sudo ldconfig

    cd "$SCRIPT_DIR"
    rm -rf "$FFMPEG_BUILD_DIR"

    # Save version for header compatibility
    echo "$version" > "$SCRIPT_DIR/.ffmpeg-version"

    print_success "FFmpeg $version built and installed"
    test_ffmpeg_installation
}

test_ffmpeg_installation() {
    print_info "Testing FFmpeg installation..."

    local ffmpeg_bin
    ffmpeg_bin=$(which ffmpeg 2>/dev/null || echo "")

    if [ -z "$ffmpeg_bin" ]; then
        print_error "FFmpeg binary not found"
        return 1
    fi

    # Check version
    local ffmpeg_ver
    ffmpeg_ver=$("$ffmpeg_bin" -version 2>&1 | head -1)
    print_success "FFmpeg: $ffmpeg_ver"

    # Check for required decoders
    print_info "Checking audio decoders..."
    local decoders
    decoders=$("$ffmpeg_bin" -decoders 2>&1)

    local required_decoders="flac alac dsd_lsbf dsd_msbf pcm_s16le pcm_s24le pcm_s32le"
    local all_found=true

    for dec in $required_decoders; do
        if echo "$decoders" | grep -q " $dec "; then
            echo "  [OK] $dec"
        else
            echo "  [MISSING] $dec"
            all_found=false
        fi
    done

    if [ "$all_found" = true ]; then
        print_success "All required FFmpeg components found!"
    else
        print_warning "Some FFmpeg components are missing - audio playback may be limited"
    fi
}

# =============================================================================
# FFMPEG HEADERS FOR COMPILATION (ABI COMPATIBILITY)
# =============================================================================

download_ffmpeg_headers() {
    local version="${1:-$FFMPEG_TARGET_VERSION}"

    print_info "Downloading FFmpeg $version headers for compilation..."

    if [ -d "$FFMPEG_HEADERS_DIR" ] && [ -f "$FFMPEG_HEADERS_DIR/.version" ]; then
        local existing_ver
        existing_ver=$(cat "$FFMPEG_HEADERS_DIR/.version")
        if [ "$existing_ver" = "$version" ]; then
            print_success "FFmpeg $version headers already present"
            return 0
        fi
    fi

    mkdir -p "$FFMPEG_HEADERS_DIR"
    cd "$FFMPEG_HEADERS_DIR"

    local tarball="ffmpeg-${version}.tar.xz"
    local url="https://ffmpeg.org/releases/$tarball"

    if [ ! -f "$tarball" ]; then
        print_info "Downloading FFmpeg ${version} source..."
        wget -q --show-progress "$url" || {
            print_error "Failed to download FFmpeg $version"
            return 1
        }
    fi

    print_info "Extracting headers..."
    tar xf "$tarball"

    # Create symlinks to header directories
    rm -f libavformat libavcodec libavutil libswresample
    ln -sf "ffmpeg-${version}/libavformat" libavformat
    ln -sf "ffmpeg-${version}/libavcodec" libavcodec
    ln -sf "ffmpeg-${version}/libavutil" libavutil
    ln -sf "ffmpeg-${version}/libswresample" libswresample

    echo "$version" > .version
    rm -f "$tarball"

    cd "$SCRIPT_DIR"
    print_success "FFmpeg $version headers ready at $FFMPEG_HEADERS_DIR"
}

ensure_ffmpeg_headers() {
    local target_ver="${1:-}"

    if [ -z "$target_ver" ]; then
        if [ -f "$SCRIPT_DIR/.ffmpeg-version" ]; then
            target_ver=$(cat "$SCRIPT_DIR/.ffmpeg-version")
        else
            target_ver="$FFMPEG_TARGET_VERSION"
        fi
        print_info "Target FFmpeg version: $target_ver"
    fi

    if [ -d "$FFMPEG_HEADERS_DIR" ] && [ -f "$FFMPEG_HEADERS_DIR/.version" ]; then
        local existing_ver
        existing_ver=$(cat "$FFMPEG_HEADERS_DIR/.version")
        if [ "$existing_ver" = "$target_ver" ]; then
            print_success "Using FFmpeg $target_ver headers from $FFMPEG_HEADERS_DIR"
            return 0
        fi
    fi

    download_ffmpeg_headers "$target_ver"
}

# =============================================================================
# DIRETTA SDK
# =============================================================================

check_diretta_sdk() {
    print_header "Diretta SDK Check"

    local sdk_locations=(
        "$SDK_PATH"
        "$HOME/DirettaHostSDK_147"
        "./DirettaHostSDK_147"
        "/opt/DirettaHostSDK_147"
        "/c/DirettaHostSDK_147"
        "/d/DirettaHostSDK_147"
    )

    for loc in "${sdk_locations[@]}"; do
        if [ -d "$loc" ] && [ -d "$loc/lib" ]; then
            SDK_PATH="$loc"
            print_success "Found Diretta SDK at: $SDK_PATH"
            return 0
        fi
    done

    print_warning "Diretta SDK not found"
    echo ""
    echo "The Diretta Host SDK is required but not included in this repository."
    echo ""
    echo "Please download it from: https://www.diretta.link"
    echo "  1. Visit the website"
    echo "  2. Go to 'Download Preview' section"
    echo "  3. Download DirettaHostSDK_147.tar.gz"
    echo "  4. Extract to: $HOME/"
    echo ""
    read -p "Press Enter after you've downloaded and extracted the SDK..."

    for loc in "${sdk_locations[@]}"; do
        if [ -d "$loc" ] && [ -d "$loc/lib" ]; then
            SDK_PATH="$loc"
            print_success "Found Diretta SDK at: $SDK_PATH"
            return 0
        fi
    done

    print_error "SDK still not found. Please extract it and try again."
    exit 1
}

# =============================================================================
# BUILD
# =============================================================================

build_renderer() {
    print_header "Building Diretta UPnP Renderer"

    cd "$SCRIPT_DIR"

    if [ ! -f "Makefile" ]; then
        print_error "Makefile not found in $SCRIPT_DIR"
        exit 1
    fi

    # Ensure FFmpeg headers are available
    print_info "Checking FFmpeg header compatibility..."
    ensure_ffmpeg_headers

    # Clean and build
    make clean 2>/dev/null || true

    export DIRETTA_SDK_PATH="$SDK_PATH"

    if [ -d "$FFMPEG_HEADERS_DIR" ] && [ -f "$FFMPEG_HEADERS_DIR/.version" ]; then
        print_info "Building with FFmpeg headers from $FFMPEG_HEADERS_DIR"
        make FFMPEG_PATH="$FFMPEG_HEADERS_DIR"
    else
        make
    fi

    if [ ! -f "bin/DirettaRendererUPnP" ] && [ ! -f "bin/DirettaRendererUPnP.exe" ]; then
        print_error "Build failed. Please check error messages above."
        exit 1
    fi

    print_success "Build successful!"
}

# =============================================================================
# MAIN MENU
# =============================================================================

show_main_menu() {
    echo ""
    echo "============================================"
    echo " Diretta UPnP Renderer - Windows Installation"
    echo "============================================"
    echo ""
    echo "Environment: $ENV_TYPE"
    [[ -n "$MSYSTEM" ]] && echo "MSYS2 subsystem: $MSYSTEM"
    echo ""
    echo "Installation options:"
    echo ""
    echo "  1) Full installation (recommended)"
    echo "     - Install dependencies, FFmpeg, build"
    echo ""
    echo "  2) Install dependencies only"
    echo "     - Base packages and FFmpeg"
    echo ""
    echo "  3) Build only"
    echo "     - Assumes dependencies are installed"
    echo ""
    echo "  4) Download FFmpeg headers only"
    echo "     - For ABI compatibility when building"
    echo ""
    echo "  q) Quit"
    echo ""
}

run_full_installation() {
    case $ENV_TYPE in
        msys2)
            install_msys2_dependencies
            install_ffmpeg_msys2
            ;;
        wsl|linux)
            install_wsl_dependencies
            install_ffmpeg_wsl
            ;;
        *)
            print_error "Unsupported environment: $ENV_TYPE"
            print_info "Please use MSYS2/MinGW or WSL"
            exit 1
            ;;
    esac

    check_diretta_sdk
    build_renderer

    print_header "Installation Complete!"

    echo ""
    echo "Quick Start:"
    if [[ "$ENV_TYPE" == "msys2" ]]; then
        echo "  ./bin/DirettaRendererUPnP.exe --port 4005 --buffer 2.0"
    else
        echo "  sudo ./bin/DirettaRendererUPnP --port 4005 --buffer 2.0"
    fi
    echo ""
    echo "Then open your UPnP control point (JPlay, BubbleUPnP, etc.)"
    echo "and select 'Diretta Renderer' as output device."
    echo ""
}

# =============================================================================
# ENTRY POINT
# =============================================================================

main() {
    detect_system

    case "${1:-}" in
        --full|-f)
            run_full_installation
            exit 0
            ;;
        --deps|-d)
            case $ENV_TYPE in
                msys2)
                    install_msys2_dependencies
                    install_ffmpeg_msys2
                    ;;
                wsl|linux)
                    install_wsl_dependencies
                    install_ffmpeg_wsl
                    ;;
            esac
            exit 0
            ;;
        --build|-b)
            check_diretta_sdk
            build_renderer
            exit 0
            ;;
        --headers|-H)
            ensure_ffmpeg_headers
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [OPTION]"
            echo ""
            echo "Options:"
            echo "  --full, -f       Full installation"
            echo "  --deps, -d       Install dependencies only"
            echo "  --build, -b      Build only"
            echo "  --headers, -H    Download FFmpeg headers only"
            echo "  --help, -h       Show this help"
            echo ""
            echo "Without options, shows interactive menu."
            echo ""
            echo "Supported environments:"
            echo "  - MSYS2/MinGW64 (recommended for Windows)"
            echo "  - WSL (Windows Subsystem for Linux)"
            echo "  - Native Linux"
            exit 0
            ;;
    esac

    # Interactive menu
    while true; do
        show_main_menu

        read -p "Choose option [1-4/q]: " choice

        case $choice in
            1)
                run_full_installation
                break
                ;;
            2)
                case $ENV_TYPE in
                    msys2)
                        install_msys2_dependencies
                        install_ffmpeg_msys2
                        ;;
                    wsl|linux)
                        install_wsl_dependencies
                        install_ffmpeg_wsl
                        ;;
                esac
                print_success "Dependencies installed"
                ;;
            3)
                check_diretta_sdk
                build_renderer
                ;;
            4)
                ensure_ffmpeg_headers
                ;;
            q|Q)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option: $choice"
                ;;
        esac
    done
}

main "$@"
