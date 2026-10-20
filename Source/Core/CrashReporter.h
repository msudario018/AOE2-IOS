#ifndef CrashReporter_h
#define CrashReporter_h

#if defined(__OBJC__)
#import <Foundation/Foundation.h>
#else
#include <stdint.h>
#include <stddef.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Installs POSIX signal handlers (SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE)
/// and NSUncaughtExceptionHandler to capture any native or managed crash.
void CrashReporter_Install(const char* _Nullable logDirectoryPath);

/// Records a lightweight breadcrumb into the circular crash ring-buffer (signal-safe).
void CrashReporter_RecordBreadcrumb(const char* _Nullable category, const char* _Nullable message);

/// Logs a formatted message directly to the persistent runtime log and console.
void AoE2_Log(const char* _Nullable level, const char* _Nullable category, const char* _Nullable format, ...) __attribute__((format(printf, 3, 4)));

/// Non-variadic logging function for Swift interoperability.
void AoE2_LogMsg(const char* _Nullable level, const char* _Nullable category, const char* _Nullable message);

#ifdef __cplusplus
}
#endif

#if defined(__OBJC__)
NS_ASSUME_NONNULL_BEGIN

@interface CrashReporter : NSObject

+ (void)install;
+ (void)recordBreadcrumbWithCategory:(NSString *)category message:(NSString *)message;
+ (NSArray<NSString *> *)availableCrashReports;
+ (NSString * _Nullable)readLatestCrashReport;
+ (void)clearCrashReports;

@end

NS_ASSUME_NONNULL_END
#endif

#endif /* CrashReporter_h */
