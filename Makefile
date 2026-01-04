# Diretta UPnP Renderer - Makefile (Simplified Architecture)
# Uses unified DirettaSync class (merged from DirettaSyncAdapter + DirettaOutput)
# Based on MPD Diretta Output Plugin v0.4.0
#
# Usage:
#   make                              # Build with auto-detect
#   make ARCH_NAME=x64-linux-15v3     # Manual architecture

# ============================================
# Compiler Settings
# ============================================

CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -pthread
LDFLAGS = -pthread

# ============================================
# Architecture Detection (unchanged from original)
# ============================================

UNAME_M := $(shell uname -m)

ifeq ($(UNAME_M),x86_64)
    BASE_ARCH = x64
else ifeq ($(UNAME_M),aarch64)
    BASE_ARCH = aarch64
else ifeq ($(UNAME_M),arm64)
    BASE_ARCH = aarch64
else ifeq ($(UNAME_M),riscv64)
    BASE_ARCH = riscv64
else
    BASE_ARCH = unknown
endif

ifeq ($(BASE_ARCH),x64)
    HAS_AVX2   := $(shell grep -q avx2 /proc/cpuinfo 2>/dev/null && echo 1 || echo 0)
    HAS_AVX512 := $(shell grep -q avx512 /proc/cpuinfo 2>/dev/null && echo 1 || echo 0)
    IS_ZEN4    := $(shell grep -m1 "model name" /proc/cpuinfo 2>/dev/null | grep -qiE "Ryzen.*(7[0-9]{3}|9[0-9]{3})" && echo 1 || echo 0)

    ifeq ($(IS_ZEN4),1)
        DEFAULT_VARIANT = x64-linux-15zen4
    else ifeq ($(HAS_AVX512),1)
        DEFAULT_VARIANT = x64-linux-15v4
    else ifeq ($(HAS_AVX2),1)
        DEFAULT_VARIANT = x64-linux-15v3
    else
        DEFAULT_VARIANT = x64-linux-15v2
    endif

else ifeq ($(BASE_ARCH),aarch64)
    PAGE_SIZE := $(shell getconf PAGESIZE 2>/dev/null || echo 4096)
    IS_RPI5 := $(shell [ -r /proc/device-tree/model ] && grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null && echo 1 || echo 0)

    ifeq ($(IS_RPI5),1)
        DEFAULT_VARIANT = aarch64-linux-15k16
    else ifeq ($(PAGE_SIZE),16384)
        DEFAULT_VARIANT = aarch64-linux-15k16
    else
        DEFAULT_VARIANT = aarch64-linux-15
    endif

else ifeq ($(BASE_ARCH),riscv64)
    DEFAULT_VARIANT = riscv64-linux-15
else
    DEFAULT_VARIANT = unknown
endif

ifdef ARCH_NAME
    FULL_VARIANT = $(ARCH_NAME)
else
    FULL_VARIANT = $(DEFAULT_VARIANT)
endif

ifdef NOLOG
    NOLOG_SUFFIX = -nolog
else
    NOLOG_SUFFIX =
endif

DIRETTA_LIB_NAME = libDirettaHost_$(FULL_VARIANT)$(NOLOG_SUFFIX).a
ACQUA_LIB_NAME   = libACQUA_$(FULL_VARIANT)$(NOLOG_SUFFIX).a

$(info )
$(info ═══════════════════════════════════════════════════════)
$(info   Diretta UPnP Renderer - SIMPLIFIED ARCHITECTURE)
$(info   DirettaSync: Unified adapter (DirettaSyncAdapter+DirettaOutput))
$(info ═══════════════════════════════════════════════════════)
$(info Variant:       $(FULL_VARIANT))
$(info Library:       $(DIRETTA_LIB_NAME))
$(info ═══════════════════════════════════════════════════════)
$(info )

# ============================================
# SDK Detection
# ============================================

ifdef DIRETTA_SDK_PATH
    SDK_PATH = $(DIRETTA_SDK_PATH)
else
    SDK_SEARCH_PATHS = \
        ../DirettaHostSDK_147 \
        ./DirettaHostSDK_147 \
        $(HOME)/DirettaHostSDK_147 \
        /opt/DirettaHostSDK_147

    SDK_PATH = $(firstword $(foreach path,$(SDK_SEARCH_PATHS),$(wildcard $(path))))

    ifeq ($(SDK_PATH),)
        $(error Diretta SDK not found!)
    endif
endif

SDK_LIB_DIRETTA = $(SDK_PATH)/lib/$(DIRETTA_LIB_NAME)

ifeq (,$(wildcard $(SDK_LIB_DIRETTA)))
    $(error Required library not found: $(DIRETTA_LIB_NAME))
endif

$(info SDK: $(SDK_PATH))
$(info )

# ============================================
# Paths and Libraries
# ============================================

INCLUDES = \
    -I/usr/include/ffmpeg \
    -I/usr/include/upnp \
    -I/usr/local/include \
    -I. \
    -Isrc \
    -I$(SDK_PATH)/Host

LDFLAGS += \
    -L/usr/local/lib \
    -L$(SDK_PATH)/lib

LIBS = \
    -lupnp \
    -lixml \
    -lpthread \
    -lDirettaHost_$(FULL_VARIANT)$(NOLOG_SUFFIX) \
    -lavformat \
    -lavcodec \
    -lavutil \
    -lswresample

SDK_LIB_ACQUA = $(SDK_PATH)/lib/$(ACQUA_LIB_NAME)
ifneq (,$(wildcard $(SDK_LIB_ACQUA)))
    LIBS += -lACQUA_$(FULL_VARIANT)$(NOLOG_SUFFIX)
endif

# ============================================
# Source Files - SIMPLIFIED ARCHITECTURE
# ============================================

SRCDIR = src
OBJDIR = obj
BINDIR = bin

# Simplified architecture source files:
# - DirettaSync.cpp replaces DirettaSyncAdapter.cpp + DirettaOutput.cpp
SOURCES = \
    $(SRCDIR)/main.cpp \
    $(SRCDIR)/DirettaRenderer.cpp \
    $(SRCDIR)/AudioEngine.cpp \
    $(SRCDIR)/DirettaSync.cpp \
    $(SRCDIR)/UPnPDevice.cpp

OBJECTS = $(SOURCES:$(SRCDIR)/%.cpp=$(OBJDIR)/%.o)
DEPENDS = $(OBJECTS:.o=.d)

TARGET = $(BINDIR)/DirettaRendererUPnP

# ============================================
# Build Rules
# ============================================

.PHONY: all clean info

all: $(TARGET)
	@echo ""
	@echo "Build complete: $(TARGET)"
	@echo "Architecture: Simplified (DirettaSync unified)"

$(TARGET): $(OBJECTS) | $(BINDIR)
	@echo "Linking $(TARGET)..."
	$(CXX) $(OBJECTS) $(LDFLAGS) $(LIBS) -o $(TARGET)

$(OBJDIR)/%.o: $(SRCDIR)/%.cpp | $(OBJDIR)
	@echo "Compiling $<..."
	$(CXX) $(CXXFLAGS) $(INCLUDES) -MMD -MP -c $< -o $@

$(OBJDIR):
	@mkdir -p $(OBJDIR)

$(BINDIR):
	@mkdir -p $(BINDIR)

clean:
	@rm -rf $(OBJDIR) $(BINDIR)
	@echo "Clean complete"

info:
	@echo "Source files (simplified architecture):"
	@for src in $(SOURCES); do echo "  $$src"; done
	@echo ""
	@echo "Key files:"
	@echo "  DirettaRingBuffer.h  - Extracted ring buffer class"
	@echo "  DirettaSync.h/cpp    - Unified adapter (replaces DirettaSyncAdapter + DirettaOutput)"
	@echo "  DirettaRenderer.h/cpp - Simplified renderer"

-include $(DEPENDS)
