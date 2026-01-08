/**
 * @file Platform.h
 * @brief Cross-platform abstractions for Windows and Linux
 */

#ifndef PLATFORM_H
#define PLATFORM_H

#ifdef _WIN32
    // Windows-specific headers
    #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
    #endif
    #ifndef NOMINMAX
    #define NOMINMAX
    #endif
    #ifndef NOGDI
    #define NOGDI
    #endif
    #include <windows.h>
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #include <direct.h>
    #include <io.h>

    // Undefine problematic Windows macros that conflict with SDK
    #ifdef ERROR
    #undef ERROR
    #endif
    #ifdef FILE_END
    #undef FILE_END
    #endif
    #ifdef FILE_ERROR
    #undef FILE_ERROR
    #endif
    #ifdef IN
    #undef IN
    #endif
    #ifdef OUT
    #undef OUT
    #endif

    // Link with Winsock library
    #pragma comment(lib, "ws2_32.lib")

    // POSIX compatibility
    #define strcasecmp _stricmp
    #define strncasecmp _strnicmp

#else
    // POSIX/Linux headers
    #include <unistd.h>
    #include <sys/types.h>
    #include <sys/stat.h>
    #include <signal.h>
    #include <netdb.h>
#endif

#include <string>
#include <functional>

namespace Platform {

//=============================================================================
// Signal/Console Handling
//=============================================================================

#ifdef _WIN32
    // Windows: Console control handler
    using ShutdownCallback = std::function<void()>;

    inline ShutdownCallback g_shutdownCallback;

    inline BOOL WINAPI ConsoleCtrlHandler(DWORD ctrlType) {
        switch (ctrlType) {
            case CTRL_C_EVENT:
            case CTRL_BREAK_EVENT:
            case CTRL_CLOSE_EVENT:
            case CTRL_SHUTDOWN_EVENT:
                if (g_shutdownCallback) {
                    g_shutdownCallback();
                }
                return TRUE;
            default:
                return FALSE;
        }
    }

    inline bool setupSignalHandler(ShutdownCallback callback) {
        g_shutdownCallback = callback;
        return SetConsoleCtrlHandler(ConsoleCtrlHandler, TRUE) != 0;
    }
#else
    // Linux: POSIX signal handler
    using ShutdownCallback = std::function<void()>;

    inline ShutdownCallback g_shutdownCallback;

    inline void signalHandler(int signal) {
        (void)signal;
        if (g_shutdownCallback) {
            g_shutdownCallback();
        }
    }

    inline bool setupSignalHandler(ShutdownCallback callback) {
        g_shutdownCallback = callback;
        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);
        return true;
    }
#endif

//=============================================================================
// Hostname
//=============================================================================

inline std::string getHostname() {
    char hostname[256];
#ifdef _WIN32
    DWORD size = sizeof(hostname);
    if (GetComputerNameA(hostname, &size)) {
        return std::string(hostname);
    }
#else
    if (gethostname(hostname, sizeof(hostname)) == 0) {
        return std::string(hostname);
    }
#endif
    return "diretta-renderer";
}

//=============================================================================
// Directory Operations
//=============================================================================

inline bool createDirectory(const std::string& path) {
#ifdef _WIN32
    return _mkdir(path.c_str()) == 0 || errno == EEXIST;
#else
    return mkdir(path.c_str(), 0755) == 0 || errno == EEXIST;
#endif
}

inline bool createDirectoryRecursive(const std::string& path) {
    std::string currentPath;
    for (size_t i = 0; i < path.length(); ++i) {
        char c = path[i];
#ifdef _WIN32
        if (c == '/' || c == '\\') {
#else
        if (c == '/') {
#endif
            if (!currentPath.empty()) {
                createDirectory(currentPath);
            }
        }
        currentPath += c;
    }
    return createDirectory(currentPath);
}

//=============================================================================
// Temporary Directory
//=============================================================================

inline std::string getTempDirectory() {
#ifdef _WIN32
    char tempPath[MAX_PATH];
    DWORD len = GetTempPathA(MAX_PATH, tempPath);
    if (len > 0 && len < MAX_PATH) {
        std::string path(tempPath);
        // Remove trailing backslash if present
        if (!path.empty() && (path.back() == '\\' || path.back() == '/')) {
            path.pop_back();
        }
        return path;
    }
    return "C:\\Temp";
#else
    const char* tmp = getenv("TMPDIR");
    if (tmp) return tmp;
    return "/tmp";
#endif
}

inline std::string getUpnpScpdDirectory() {
    return getTempDirectory() +
#ifdef _WIN32
        "\\upnp_scpd";
#else
        "/upnp_scpd";
#endif
}

//=============================================================================
// Path Separator
//=============================================================================

inline char pathSeparator() {
#ifdef _WIN32
    return '\\';
#else
    return '/';
#endif
}

inline std::string joinPath(const std::string& a, const std::string& b) {
    if (a.empty()) return b;
    if (b.empty()) return a;

    char sep = pathSeparator();
    if (a.back() == '/' || a.back() == '\\') {
        return a + b;
    }
    return a + sep + b;
}

//=============================================================================
// Sleep
//=============================================================================

inline void sleepMs(unsigned int ms) {
#ifdef _WIN32
    Sleep(ms);
#else
    usleep(ms * 1000);
#endif
}

//=============================================================================
// WinSock Initialization (Windows only)
//=============================================================================

#ifdef _WIN32
class WinSockInitializer {
public:
    WinSockInitializer() {
        WSADATA wsaData;
        WSAStartup(MAKEWORD(2, 2), &wsaData);
    }
    ~WinSockInitializer() {
        WSACleanup();
    }
};

// Global initializer - constructed before main()
inline WinSockInitializer g_winsockInit;
#endif

} // namespace Platform

#endif // PLATFORM_H
