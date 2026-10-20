#ifndef EmulationBridge_h
#define EmulationBridge_h

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Framebuffer callback type invoked by the emulation core whenever a new guest frame is ready.
/// - Parameters:
///   - width: Framebuffer width in pixels (e.g. 1024)
///   - height: Framebuffer height in pixels (e.g. 768)
///   - pitch: Stride in bytes per scanline (e.g. 1024 * 4)
///   - pixels: Raw 32-bit BGRA (or 16-bit RGB565) pixel buffer pointer
///   - context: Opaque user pointer passed during registration
typedef void (*FramebufferUpdateCallback)(int width, int height, int pitch, const void* pixels, void* context);

/// Audio sample callback type invoked for PCM stereo audio streaming (44.1kHz 16-bit).
typedef void (*AudioSamplesCallback)(const int16_t* pcmSamples, int frameCount, void* context);

/// Initializes the guest emulation runner environment.
/// - Parameters:
///   - gameDirectoryPath: Absolute path to the imported game directory containing EMPIRES2.EXE
///   - diskImagePath: Optional path to Windows 98 SE guest disk image (e.g., win98se.img)
///   - return: 0 on success, non-zero error code otherwise
int EmulationBridge_Initialize(const char* gameDirectoryPath, const char* diskImagePath);

/// Starts the guest execution thread.
void EmulationBridge_Start(void);

/// Pauses the guest execution thread.
void EmulationBridge_Pause(void);

/// Resumes guest execution.
void EmulationBridge_Resume(void);

/// Stops and tears down the guest execution thread.
void EmulationBridge_Shutdown(void);

/// Registers callbacks for video framebuffer and audio samples.
void EmulationBridge_RegisterCallbacks(FramebufferUpdateCallback videoCb,
                                      AudioSamplesCallback audioCb,
                                      void* context);

/// Sends mouse absolute movement to the guest Win32 subsystem.
void EmulationBridge_SendMouseMove(int x, int y);

/// Sends mouse button state changes to the guest Win32 subsystem.
/// button: 0 = Left, 1 = Right, 2 = Middle
void EmulationBridge_SendMouseButton(int button, bool isDown);

/// Sends mouse wheel / scroll deltas.
void EmulationBridge_SendMouseScroll(int deltaX, int deltaY);

/// Sends keyboard scan code events.
void EmulationBridge_SendKeyEvent(uint16_t scanCode, bool isDown);

#ifdef __cplusplus
}
#endif

// MARK: - Objective-C Wrapper Class for Swift Interoperability

@interface EmulationBridgeWrapper : NSObject

+ (instancetype)sharedInstance;

- (BOOL)initializeWithGameDirectory:(NSString *)gameDirectory
                     diskImagePath:(NSString * _Nullable)diskImage;
- (void)start;
- (void)pause;
- (void)resume;
- (void)shutdown;

- (void)sendMouseMoveToX:(int)x y:(int)y;
- (void)sendMouseButton:(int)button isDown:(BOOL)isDown;
- (void)sendMouseScrollDeltaX:(int)deltaX deltaY:(int)deltaY;
- (void)sendKeyEvent:(uint16_t)scanCode isDown:(BOOL)isDown;

@property (nonatomic, copy, nullable) void (^onFramebufferAvailable)(int width, int height, int pitch, const void *pixels);
@property (nonatomic, copy, nullable) void (^onAudioAvailable)(const int16_t *samples, int count);

@end

#endif /* EmulationBridge_h */
