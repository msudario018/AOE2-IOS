#import "CrashReporter.h"
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <execinfo.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <cstring>
#include <cstdio>
#include <cstdarg>
#include <ctime>

static char s_logDirectory[1024] = {0};
static char s_runtimeLogPath[1024] = {0};
static int s_runtimeLogFd = -1;

// Signal-safe circular breadcrumb buffer
#define MAX_BREADCRUMBS 32
#define BREADCRUMB_LEN 160
static char s_breadcrumbs[MAX_BREADCRUMBS][BREADCRUMB_LEN];
static int s_breadcrumbHead = 0;
static pthread_mutex_t s_breadcrumbMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t s_logMutex = PTHREAD_MUTEX_INITIALIZER;

// Alternate stack for catching stack overflows
static stack_t s_altStack;
static struct sigaction s_oldSigactions[32];

// Signal names lookup
static const char* GetSignalName(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV (Segmentation Fault / Bad Memory Access)";
        case SIGBUS:  return "SIGBUS (Bus Error / Unaligned Access)";
        case SIGILL:  return "SIGILL (Illegal Instruction)";
        case SIGABRT: return "SIGABRT (Abort / Assertion Failure)";
        case SIGFPE:  return "SIGFPE (Floating Point / Arithmetic Error)";
        case SIGTRAP: return "SIGTRAP (Trace/Breakpoint Trap)";
        default:      return "UNKNOWN SIGNAL";
    }
}

// Signal-safe minimal string writer
static void SafeWrite(int fd, const char* str) {
    if (fd < 0 || !str) return;
    write(fd, str, strlen(str));
}

// Signal handler (strictly async-signal-safe)
static void PosixSignalHandler(int sig, siginfo_t* info, void* ucontext) {
    char crashFilename[1024];
    time_t now = time(nullptr);
    struct tm tm_buf;
    localtime_r(&now, &tm_buf);

    snprintf(crashFilename, sizeof(crashFilename), "%s/crash_%04d%02d%02d_%02d%02d%02d.log",
             s_logDirectory,
             tm_buf.tm_year + 1900, tm_buf.tm_mon + 1, tm_buf.tm_mday,
             tm_buf.tm_hour, tm_buf.tm_min, tm_buf.tm_sec);

    int fd = open(crashFilename, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) {
        SafeWrite(fd, "=================================================================\n");
        SafeWrite(fd, "           AGE OF EMPIRES II (iOS) - CRASH REPORT                \n");
        SafeWrite(fd, "=================================================================\n\n");

        char header[512];
        snprintf(header, sizeof(header), "Timestamp: %04d-%02d-%02d %02d:%02d:%02d UTC\n",
                 tm_buf.tm_year + 1900, tm_buf.tm_mon + 1, tm_buf.tm_mday,
                 tm_buf.tm_hour, tm_buf.tm_min, tm_buf.tm_sec);
        SafeWrite(fd, header);

        snprintf(header, sizeof(header), "Signal: %d - %s\nFaulting Address: %p\n\n",
                 sig, GetSignalName(sig), info ? info->si_addr : nullptr);
        SafeWrite(fd, header);

        // Print recent breadcrumbs
        SafeWrite(fd, "--- RECENT EXECUTION BREADCRUMBS ---\n");
        for (int i = 0; i < MAX_BREADCRUMBS; ++i) {
            int idx = (s_breadcrumbHead + i) % MAX_BREADCRUMBS;
            if (s_breadcrumbs[idx][0] != '\0') {
                SafeWrite(fd, "  [");
                SafeWrite(fd, s_breadcrumbs[idx]);
                SafeWrite(fd, "]\n");
            }
        }
        SafeWrite(fd, "\n");

        // Backtrace capture
        SafeWrite(fd, "--- STACK BACKTRACE ---\n");
        void* callstack[64];
        int frames = backtrace(callstack, 64);
        backtrace_symbols_fd(callstack, frames, fd);

        SafeWrite(fd, "\n==================== END OF CRASH REPORT =======================\n");
        fsync(fd);
        close(fd);
    }

    // Also mirror crash header to runtime log
    if (s_runtimeLogFd >= 0) {
        char errBuf[256];
        snprintf(errBuf, sizeof(errBuf), "\n[FATAL_CRASH] Process caught signal %d: %s at address %p\n",
                 sig, GetSignalName(sig), info ? info->si_addr : nullptr);
        SafeWrite(s_runtimeLogFd, errBuf);
        fsync(s_runtimeLogFd);
    }

    // Restore old signal handler and re-raise
    signal(sig, SIG_DFL);
    raise(sig);
}

// Objective-C Uncaught Exception Handler
static void ObjcUncaughtExceptionHandler(NSException *exception) {
    time_t now = time(nullptr);
    struct tm tm_buf;
    localtime_r(&now, &tm_buf);

    char crashFilename[1024];
    snprintf(crashFilename, sizeof(crashFilename), "%s/crash_objc_%04d%02d%02d_%02d%02d%02d.log",
             s_logDirectory,
             tm_buf.tm_year + 1900, tm_buf.tm_mon + 1, tm_buf.tm_mday,
             tm_buf.tm_hour, tm_buf.tm_min, tm_buf.tm_sec);

    NSString *content = [NSString stringWithFormat:
        @"=================================================================\n"
        @"        AGE OF EMPIRES II (iOS) - UNCAUGHT OBJC EXCEPTION       \n"
        @"=================================================================\n\n"
        @"Name: %@\n"
        @"Reason: %@\n"
        @"User Info: %@\n\n"
        @"--- CALL STACK SYMBOLS ---\n%@\n"
        @"=================================================================\n",
        exception.name,
        exception.reason,
        exception.userInfo,
        [exception.callStackSymbols componentsJoinedByString:@"\n"]
    ];

    [content writeToFile:[NSString stringWithUTF8String:crashFilename]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];

    AoE2_Log("FATAL", "Exception", "Uncaught NSException: %s - %s",
             [exception.name UTF8String], [exception.reason UTF8String]);
}

extern "C" {

void CrashReporter_Install(const char* logDirectoryPath) {
    if (logDirectoryPath) {
        strncpy(s_logDirectory, logDirectoryPath, sizeof(s_logDirectory) - 1);
        snprintf(s_runtimeLogPath, sizeof(s_runtimeLogPath), "%s/aoe2_runtime.log", s_logDirectory);

        // Open or append to runtime log
        s_runtimeLogFd = open(s_runtimeLogPath, O_WRONLY | O_CREAT | O_APPEND, 0666);
    }

    // 1. Allocate alternate signal stack (128 KB)
    s_altStack.ss_size = 128 * 1024;
    s_altStack.ss_sp = malloc(s_altStack.ss_size);
    s_altStack.ss_flags = 0;
    sigaltstack(&s_altStack, nullptr);

    // 2. Register POSIX signal handlers
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = PosixSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);

    int signalsToCatch[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP };
    for (int sig : signalsToCatch) {
        sigaction(sig, &sa, &s_oldSigactions[sig]);
    }

    // 3. Register Objective-C uncaught exception handler
    NSSetUncaughtExceptionHandler(&ObjcUncaughtExceptionHandler);

    AoE2_Log("INFO", "CrashReporter", "Crash reporter and signal handlers successfully installed at %s", s_logDirectory);
}

void CrashReporter_RecordBreadcrumb(const char* category, const char* message) {
    pthread_mutex_lock(&s_breadcrumbMutex);
    time_t now = time(nullptr);
    struct tm tm_buf;
    localtime_r(&now, &tm_buf);

    snprintf(s_breadcrumbs[s_breadcrumbHead], BREADCRUMB_LEN,
             "%02d:%02d:%02d [%s] %s",
             tm_buf.tm_hour, tm_buf.tm_min, tm_buf.tm_sec,
             category ? category : "Core",
             message ? message : "");

    s_breadcrumbHead = (s_breadcrumbHead + 1) % MAX_BREADCRUMBS;
    pthread_mutex_unlock(&s_breadcrumbMutex);
}

void AoE2_Log(const char* level, const char* category, const char* format, ...) {
    char messageBuffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(messageBuffer, sizeof(messageBuffer), format, args);
    va_end(args);

    time_t now = time(nullptr);
    struct tm tm_buf;
    localtime_r(&now, &tm_buf);

    char fullLine[1280];
    snprintf(fullLine, sizeof(fullLine), "%04d-%02d-%02d %02d:%02d:%02d [%s] [%s] %s\n",
             tm_buf.tm_year + 1900, tm_buf.tm_mon + 1, tm_buf.tm_mday,
             tm_buf.tm_hour, tm_buf.tm_min, tm_buf.tm_sec,
             level ? level : "INFO",
             category ? category : "App",
             messageBuffer);

    pthread_mutex_lock(&s_logMutex);

    // Write to stderr / Xcode console
    fputs(fullLine, stderr);

    // Write to persistent file
    if (s_runtimeLogFd >= 0) {
        write(s_runtimeLogFd, fullLine, strlen(fullLine));
        fsync(s_runtimeLogFd);
    }

    pthread_mutex_unlock(&s_logMutex);

    // Save as breadcrumb for crash reports
    CrashReporter_RecordBreadcrumb(category, messageBuffer);
}

} // extern "C"

// MARK: - Objective-C Implementation

@implementation CrashReporter

+ (void)install {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = [paths firstObject];
    NSString *logsDir = [docs stringByAppendingPathComponent:@"Logs"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logsDir]) {
        [fm createDirectoryAtPath:logsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    CrashReporter_Install([logsDir UTF8String]);
}

+ (void)recordBreadcrumbWithCategory:(NSString *)category message:(NSString *)message {
    CrashReporter_RecordBreadcrumb([category UTF8String], [message UTF8String]);
}

+ (NSArray<NSString *> *)availableCrashReports {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *logsDir = [[paths firstObject] stringByAppendingPathComponent:@"Logs"];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:logsDir error:nil];
    NSMutableArray *crashLogs = [NSMutableArray array];

    for (NSString *file in files) {
        if ([file hasPrefix:@"crash_"] && [file hasSuffix:@".log"]) {
            [crashLogs addObject:[logsDir stringByAppendingPathComponent:file]];
        }
    }

    [crashLogs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a]; // Newest first
    }];

    return crashLogs;
}

+ (NSString *)readLatestCrashReport {
    NSArray *reports = [self availableCrashReports];
    if (reports.count == 0) return nil;
    return [NSString stringWithContentsOfFile:[reports firstObject] encoding:NSUTF8StringEncoding error:nil];
}

+ (void)clearCrashReports {
    for (NSString *path in [self availableCrashReports]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

@end
