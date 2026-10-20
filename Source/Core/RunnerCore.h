#ifndef RunnerCore_h
#define RunnerCore_h

#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <functional>
#include <cstdint>

namespace AoE2Runner {

enum class RunnerState {
    Uninitialized,
    Stopped,
    Running,
    Paused
};

struct MouseState {
    int x = 512;
    int y = 384;
    bool leftButton = false;
    bool rightButton = false;
    bool middleButton = false;
};

using VideoCallback = std::function<void(int width, int height, int pitch, const void* pixels)>;
using AudioCallback = std::function<void(const int16_t* samples, int count)>;

class RunnerCore {
public:
    static RunnerCore& Instance();

    bool Initialize(const std::string& gameDirectory, const std::string& diskImage);
    void Start();
    void Pause();
    void Resume();
    void Shutdown();

    void SetVideoCallback(VideoCallback callback);
    void SetAudioCallback(AudioCallback callback);

    void SendMouseMove(int x, int y);
    void SendMouseButton(int button, bool isDown);
    void SendMouseScroll(int deltaX, int deltaY);
    void SendKeyEvent(uint16_t scanCode, bool isDown);

private:
    RunnerCore();
    ~RunnerCore();

    void ExecutionThreadLoop();
    void RenderGuestFrame();

    std::string m_gameDirectory;
    std::string m_diskImage;

    std::atomic<RunnerState> m_state{RunnerState::Uninitialized};
    std::thread m_workerThread;
    std::mutex m_inputMutex;

    MouseState m_mouseState;
    VideoCallback m_videoCallback;
    AudioCallback m_audioCallback;

    // Guest Framebuffer memory
    int m_guestWidth = 1024;
    int m_guestHeight = 768;
    int m_guestPitch = 1024 * 4;
    std::vector<uint32_t> m_framebuffer;
};

} // namespace AoE2Runner

#endif /* RunnerCore_h */
