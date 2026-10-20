#ifndef CrashReporter_h
#define CrashReporter_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Installs POSIX signal handlers (SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE)
/// and NSUncaughtExceptionHandler to capture any native or managed crash.
void CrashReporter_Install(const char* logDirectoryPath);

/// Records a lightweight breadcrumb into the circular crash ring-buffer (signal-safe).
void CrashReporter_RecordBreadcrumb(const char* category, const char* message);

/// Logs a formatted message directly to the persistent runtime log and console.
void AoE2_Log(const char* level, const char* category, const char* format, ...) __attribute__((format(printf, 3, 4)));

/// Non-variadic logging function for Swift interoperability.
void AoE2_LogMsg(const char* level, const char* category, const char* message);

#ifdef __cplusplus
}
#endif

@interface CrashReporter : NSObject

+ (void)install;
+ (void)recordBreadcrumbWithCategory:(NSString *)category message:(NSString *)message;
+ (nonnull NSArray<NSString *> *)availableCrashReports;
+ (NSString * _Nullable)readLatestCrashReport;
+ (void)clearCrashReports;

@end

#endif /* CrashReporter_h */
