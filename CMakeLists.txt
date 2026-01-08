cmake_minimum_required(VERSION 3.16)
project(DirettaRendererUPnP VERSION 1.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Platform detection
if(WIN32)
    message(STATUS "Building for Windows")
    add_definitions(-DWIN32_LEAN_AND_MEAN -DNOMINMAX)
else()
    message(STATUS "Building for Linux/Unix")
endif()

# Source files
set(SOURCES
    src/main.cpp
    src/DirettaRenderer.cpp
    src/DirettaSync.cpp
    src/AudioEngine.cpp
    src/UPnPDevice.cpp
)

set(HEADERS
    src/Platform.h
    src/DirettaRenderer.h
    src/DirettaSync.h
    src/AudioEngine.h
    src/UPnPDevice.hpp
    src/DirettaRingBuffer.h
    src/ProtocolInfoBuilder.h
)

# Executable
add_executable(${PROJECT_NAME} ${SOURCES} ${HEADERS})

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Find Diretta SDK
set(DIRETTA_SDK_SEARCH_PATHS
    "${CMAKE_CURRENT_SOURCE_DIR}/../DirettaHostSDK_147"
    "${CMAKE_CURRENT_SOURCE_DIR}/../DirettaHostSDK_147"
    "$ENV{DIRETTA_SDK_PATH}"
)

foreach(path ${DIRETTA_SDK_SEARCH_PATHS})
    if(EXISTS "${path}/Host")
        set(DIRETTA_SDK_PATH "${path}")
        break()
    endif()
endforeach()

if(NOT DIRETTA_SDK_PATH)
    message(FATAL_ERROR "Diretta SDK not found! Set DIRETTA_SDK_PATH environment variable.")
endif()

message(STATUS "Diretta SDK: ${DIRETTA_SDK_PATH}")

target_include_directories(${PROJECT_NAME} PRIVATE
    ${DIRETTA_SDK_PATH}/Host
)

# Platform-specific linking
if(WIN32)
    # Determine architecture
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(DIRETTA_ARCH "x64")
    else()
        set(DIRETTA_ARCH "w32")
    endif()

    # Diretta libraries
    target_link_directories(${PROJECT_NAME} PRIVATE ${DIRETTA_SDK_PATH}/lib)
    target_link_libraries(${PROJECT_NAME} PRIVATE
        libDirettaHost_${DIRETTA_ARCH}-win
        libACQUA_${DIRETTA_ARCH}-win
    )

    # Windows system libraries
    target_link_libraries(${PROJECT_NAME} PRIVATE
        ws2_32
        iphlpapi
    )
else()
    # Linux: Determine variant based on architecture
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
        set(DIRETTA_VARIANT "x64-linux-15v3")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
        set(DIRETTA_VARIANT "aarch64-linux-15")
    else()
        set(DIRETTA_VARIANT "x64-linux-15v2")
    endif()

    target_link_directories(${PROJECT_NAME} PRIVATE ${DIRETTA_SDK_PATH}/lib)
    target_link_libraries(${PROJECT_NAME} PRIVATE
        DirettaHost_${DIRETTA_VARIANT}
        ACQUA_${DIRETTA_VARIANT}
    )

    target_link_libraries(${PROJECT_NAME} PRIVATE pthread)
endif()

# Find FFmpeg
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(FFMPEG QUIET libavformat libavcodec libavutil libswresample)
endif()

if(FFMPEG_FOUND)
    target_include_directories(${PROJECT_NAME} PRIVATE ${FFMPEG_INCLUDE_DIRS})
    target_link_directories(${PROJECT_NAME} PRIVATE ${FFMPEG_LIBRARY_DIRS})
    target_link_libraries(${PROJECT_NAME} PRIVATE ${FFMPEG_LIBRARIES})
else()
    # Manual FFmpeg finding (Windows or when pkg-config unavailable)
    if(DEFINED ENV{FFMPEG_DIR})
        set(FFMPEG_DIR $ENV{FFMPEG_DIR})
    elseif(WIN32)
        set(FFMPEG_DIR "C:/ffmpeg")
    else()
        set(FFMPEG_DIR "/usr")
    endif()

    target_include_directories(${PROJECT_NAME} PRIVATE ${FFMPEG_DIR}/include)
    target_link_directories(${PROJECT_NAME} PRIVATE ${FFMPEG_DIR}/lib)
    target_link_libraries(${PROJECT_NAME} PRIVATE avformat avcodec avutil swresample)
endif()

# Find libupnp
if(PkgConfig_FOUND)
    pkg_check_modules(UPNP QUIET libupnp)
endif()

if(UPNP_FOUND)
    target_include_directories(${PROJECT_NAME} PRIVATE ${UPNP_INCLUDE_DIRS})
    target_link_directories(${PROJECT_NAME} PRIVATE ${UPNP_LIBRARY_DIRS})
    target_link_libraries(${PROJECT_NAME} PRIVATE ${UPNP_LIBRARIES})
else()
    # Manual libupnp finding
    if(DEFINED ENV{PUPNP_DIR})
        set(PUPNP_DIR $ENV{PUPNP_DIR})
    elseif(WIN32)
        set(PUPNP_DIR "C:/pupnp")
    else()
        set(PUPNP_DIR "/usr")
    endif()

    target_include_directories(${PROJECT_NAME} PRIVATE ${PUPNP_DIR}/include)
    target_link_directories(${PROJECT_NAME} PRIVATE ${PUPNP_DIR}/lib)
    target_link_libraries(${PROJECT_NAME} PRIVATE upnp ixml)
endif()

# Output directory
set_target_properties(${PROJECT_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Install
install(TARGETS ${PROJECT_NAME} DESTINATION bin)

message(STATUS "")
message(STATUS "=== DirettaRendererUPnP Configuration ===")
message(STATUS "Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "Architecture: ${CMAKE_SYSTEM_PROCESSOR}")
message(STATUS "Diretta SDK: ${DIRETTA_SDK_PATH}")
message(STATUS "=========================================")
message(STATUS "")
