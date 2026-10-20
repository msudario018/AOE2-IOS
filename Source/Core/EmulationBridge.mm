#import "EmulationBridge.h"
#include "RunnerCore.h"
#import "CrashReporter.h"

static FramebufferUpdateCallback s_videoCallback = nullptr;
static AudioSamplesCallback s_audioCallback = nullptr;
static void* s_context = nullptr;

extern "C" {

int EmulationBridge_Initialize(const char* gameDirectoryPath, const char* diskImagePath) {
    std::string gameDir = gameDirectoryPath ? gameDirectoryPath : "";
    std::string diskImg = diskImagePath ? diskImagePath : "";
    
    AoE2_Log("INFO", "Bridge", "EmulationBridge_Initialize: gameDir='%s', diskImage='%s'",
             gameDir.c_str(), diskImg.c_str());
    
    bool success = AoE2Runner::RunnerCore::Instance().Initialize(gameDir, diskImg);
    if (!success) {
        AoE2_Log("ERROR", "Bridge", "EmulationBridge_Initialize failed to initialize RunnerCore!");
    }
    return success ? 0 : -1;
}

void EmulationBridge_Start(void) {
    AoE2_Log("INFO", "Bridge", "EmulationBridge_Start invoked.");
    AoE2Runner::RunnerCore::Instance().Start();
}

void EmulationBridge_Pause(void) {
    AoE2_Log("INFO", "Bridge", "EmulationBridge_Pause invoked.");
    AoE2Runner::RunnerCore::Instance().Pause();
}

void EmulationBridge_Resume(void) {
    AoE2_Log("INFO", "Bridge", "EmulationBridge_Resume invoked.");
    AoE2Runner::RunnerCore::Instance().Resume();
}

void EmulationBridge_Shutdown(void) {
    AoE2_Log("INFO", "Bridge", "EmulationBridge_Shutdown invoked.");
    AoE2Runner::RunnerCore::Instance().Shutdown();
}

void EmulationBridge_RegisterCallbacks(FramebufferUpdateCallback videoCb,
                                      AudioSamplesCallback audioCb,
                                      void* context) {
    s_videoCallback = videoCb;
    s_audioCallback = audioCb;
    s_context = context;

    AoE2_Log("INFO", "Bridge", "Registering video & audio frame callbacks (context=%p)", context);

    AoE2Runner::RunnerCore::Instance().SetVideoCallback([](int w, int h, int pitch, const void* pixels) {
        if (s_videoCallback) {
            s_videoCallback(w, h, pitch, pixels, s_context);
        }
    });

    AoE2Runner::RunnerCore::Instance().SetAudioCallback([](const int16_t* samples, int count) {
        if (s_audioCallback) {
            s_audioCallback(samples, count, s_context);
        }
    });
}

void EmulationBridge_SendMouseMove(int x, int y) {
    AoE2Runner::RunnerCore::Instance().SendMouseMove(x, y);
}

void EmulationBridge_SendMouseButton(int button, bool isDown) {
    AoE2Runner::RunnerCore::Instance().SendMouseButton(button, isDown);
}

void EmulationBridge_SendMouseScroll(int deltaX, int deltaY) {
    AoE2Runner::RunnerCore::Instance().SendMouseScroll(deltaX, deltaY);
}

void EmulationBridge_SendKeyEvent(uint16_t scanCode, bool isDown) {
    AoE2Runner::RunnerCore::Instance().SendKeyEvent(scanCode, isDown);
}

} // extern "C"

// MARK: - Objective-C Wrapper Implementation

@implementation EmulationBridgeWrapper

+ (instancetype)sharedInstance {
    static EmulationBridgeWrapper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[EmulationBridgeWrapper alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        EmulationBridge_RegisterCallbacks(
            [](int width, int height, int pitch, const void *pixels, void *context) {
                EmulationBridgeWrapper *wrapper = (__bridge EmulationBridgeWrapper *)context;
                if (wrapper.onFramebufferAvailable) {
                    wrapper.onFramebufferAvailable(width, height, pitch, pixels);
                }
            },
            [](const int16_t *samples, int count, void *context) {
                EmulationBridgeWrapper *wrapper = (__bridge EmulationBridgeWrapper *)context;
                if (wrapper.onAudioAvailable) {
                    wrapper.onAudioAvailable(samples, count);
                }
            },
            (__bridge void *)self
        );
    }
    return self;
}

- (BOOL)initializeWithGameDirectory:(NSString *)gameDirectory
                     diskImagePath:(NSString *)diskImage {
    const char *gameDirStr = [gameDirectory UTF8String];
    const char *diskImgStr = diskImage ? [diskImage UTF8String] : nullptr;
    return EmulationBridge_Initialize(gameDirStr, diskImgStr) == 0;
}

- (void)start {
    EmulationBridge_Start();
}

- (void)pause {
    EmulationBridge_Pause();
}

- (void)resume {
    EmulationBridge_Resume();
}

- (void)shutdown {
    EmulationBridge_Shutdown();
}

- (void)sendMouseMoveToX:(int)x y:(int)y {
    EmulationBridge_SendMouseMove(x, y);
}

- (void)sendMouseButton:(int)button isDown:(BOOL)isDown {
    EmulationBridge_SendMouseButton(button, isDown);
}

- (void)sendMouseScrollDeltaX:(int)deltaX deltaY:(int)deltaY {
    EmulationBridge_SendMouseScroll(deltaX, deltaY);
}

- (void)sendKeyEvent:(uint16_t)scanCode isDown:(BOOL)isDown {
    EmulationBridge_SendKeyEvent(scanCode, isDown);
}

@end
