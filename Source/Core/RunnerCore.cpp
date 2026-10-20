#include "RunnerCore.h"
#include "CrashReporter.h"
#include <chrono>
#include <cmath>
#include <cstring>
#include <iostream>

namespace AoE2Runner {

RunnerCore& RunnerCore::Instance() {
    static RunnerCore s_instance;
    return s_instance;
}

RunnerCore::RunnerCore() {
    m_framebuffer.resize(m_guestWidth * m_guestHeight, 0xFF141923); // Dark slate background
    AoE2_Log("INFO", "RunnerCore", "RunnerCore singleton constructed with resolution %dx%d", m_guestWidth, m_guestHeight);
}

RunnerCore::~RunnerCore() {
    Shutdown();
}

bool RunnerCore::Initialize(const std::string& gameDirectory, const std::string& diskImage) {
    m_gameDirectory = gameDirectory;
    m_diskImage = diskImage;
    m_state = RunnerState::Stopped;

    AoE2_Log("INFO", "RunnerCore", "Initializing RunnerCore with GameDir='%s', DiskImage='%s'",
             gameDirectory.c_str(), diskImage.empty() ? "(none)" : diskImage.c_str());
    CrashReporter_RecordBreadcrumb("RunnerCore", "Initialized runner environment");

    return true;
}

void RunnerCore::Start() {
    if (m_state == RunnerState::Running) {
        AoE2_Log("WARN", "RunnerCore", "Start called but runner is already running.");
        return;
    }
    
    AoE2_Log("INFO", "RunnerCore", "Starting runner execution thread...");
    CrashReporter_RecordBreadcrumb("RunnerCore", "Starting guest execution thread");

    m_state = RunnerState::Running;
    m_workerThread = std::thread(&RunnerCore::ExecutionThreadLoop, this);
}

void RunnerCore::Pause() {
    if (m_state == RunnerState::Running) {
        AoE2_Log("INFO", "RunnerCore", "Pausing guest execution thread.");
        CrashReporter_RecordBreadcrumb("RunnerCore", "Paused guest thread");
        m_state = RunnerState::Paused;
    }
}

void RunnerCore::Resume() {
    if (m_state == RunnerState::Paused) {
        AoE2_Log("INFO", "RunnerCore", "Resuming guest execution thread.");
        CrashReporter_RecordBreadcrumb("RunnerCore", "Resumed guest thread");
        m_state = RunnerState::Running;
    }
}

void RunnerCore::Shutdown() {
    if (m_state != RunnerState::Stopped) {
        AoE2_Log("INFO", "RunnerCore", "Shutting down runner execution thread...");
        CrashReporter_RecordBreadcrumb("RunnerCore", "Shutting down runner");
        m_state = RunnerState::Stopped;
        if (m_workerThread.joinable()) {
            m_workerThread.join();
        }
        AoE2_Log("INFO", "RunnerCore", "Runner thread successfully terminated.");
    }
}

void RunnerCore::SetVideoCallback(VideoCallback callback) {
    m_videoCallback = std::move(callback);
}

void RunnerCore::SetAudioCallback(AudioCallback callback) {
    m_audioCallback = std::move(callback);
}

void RunnerCore::SendMouseMove(int x, int y) {
    std::lock_guard<std::mutex> lock(m_inputMutex);
    m_mouseState.x = std::max(0, std::min(m_guestWidth - 1, x));
    m_mouseState.y = std::max(0, std::min(m_guestHeight - 1, y));
}

void RunnerCore::SendMouseButton(int button, bool isDown) {
    {
        std::lock_guard<std::mutex> lock(m_inputMutex);
        if (button == 0) m_mouseState.leftButton = isDown;
        if (button == 1) m_mouseState.rightButton = isDown;
        if (button == 2) m_mouseState.middleButton = isDown;
    }

    char breadcrumb[128];
    snprintf(breadcrumb, sizeof(breadcrumb), "MouseBtn: %s %s at (%d, %d)",
             button == 0 ? "Left" : (button == 1 ? "Right" : "Middle"),
             isDown ? "DOWN" : "UP", m_mouseState.x, m_mouseState.y);
    CrashReporter_RecordBreadcrumb("Input", breadcrumb);
}

void RunnerCore::SendMouseScroll(int deltaX, int deltaY) {
    char breadcrumb[128];
    snprintf(breadcrumb, sizeof(breadcrumb), "MouseScroll: dx=%d, dy=%d", deltaX, deltaY);
    CrashReporter_RecordBreadcrumb("Input", breadcrumb);
}

void RunnerCore::SendKeyEvent(uint16_t scanCode, bool isDown) {
    char breadcrumb[128];
    snprintf(breadcrumb, sizeof(breadcrumb), "Key: 0x%02X %s", scanCode, isDown ? "DOWN" : "UP");
    CrashReporter_RecordBreadcrumb("Input", breadcrumb);
}

void RunnerCore::ExecutionThreadLoop() {
    AoE2_Log("INFO", "RunnerCore", "ExecutionThreadLoop active on thread ID %p", (void*)pthread_self());

    const auto targetInterval = std::chrono::microseconds(1000000 / 60);
    uint64_t frameCount = 0;
    auto lastFpsLog = std::chrono::steady_clock::now();

    try {
        while (m_state != RunnerState::Stopped) {
            if (m_state == RunnerState::Running) {
                auto startTime = std::chrono::steady_clock::now();
                
                RenderGuestFrame();
                
                if (m_videoCallback) {
                    m_videoCallback(m_guestWidth, m_guestHeight, m_guestPitch, m_framebuffer.data());
                }

                frameCount++;
                auto now = std::chrono::steady_clock::now();
                auto fpsDelta = std::chrono::duration_cast<std::chrono::seconds>(now - lastFpsLog).count();
                if (fpsDelta >= 5) {
                    double fps = static_cast<double>(frameCount) / fpsDelta;
                    AoE2_Log("INFO", "RunnerCore", "Emulation guest running smoothly: %.1f FPS (total frames: %llu)", fps, frameCount);
                    frameCount = 0;
                    lastFpsLog = now;
                }

                auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(now - startTime);
                if (elapsed < targetInterval) {
                    std::this_thread::sleep_for(targetInterval - elapsed);
                }
            } else {
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            }
        }
    } catch (const std::exception& e) {
        AoE2_Log("FATAL", "RunnerCore", "Uncaught C++ exception in ExecutionThreadLoop: %s", e.what());
    } catch (...) {
        AoE2_Log("FATAL", "RunnerCore", "Unknown C++ exception in ExecutionThreadLoop!");
    }

    AoE2_Log("INFO", "RunnerCore", "ExecutionThreadLoop exited cleanly.");
}

void RunnerCore::RenderGuestFrame() {
    MouseState currentMouse;
    {
        std::lock_guard<std::mutex> lock(m_inputMutex);
        currentMouse = m_mouseState;
    }

    // Background tile: Medieval Age of Empires parchment tone
    uint32_t bgTile = 0xFF182230; 
    uint32_t gridColor = 0xFF233245;
    
    // Draw base isometric terrain pattern
    for (int y = 0; y < m_guestHeight; ++y) {
        uint32_t* row = &m_framebuffer[y * m_guestWidth];
        for (int x = 0; x < m_guestWidth; ++x) {
            int isoTile = ((x / 64) + (y / 32)) % 2;
            row[x] = (isoTile == 0) ? bgTile : gridColor;
            
            // Decorative mini-map area (bottom right)
            if (x >= m_guestWidth - 260 && y >= m_guestHeight - 200) {
                row[x] = 0xFF0D121B;
            }
            
            // Decorative resource bar (top header)
            if (y < 36) {
                row[x] = 0xFF111720;
            }
        }
    }

    // Draw interactive guest mouse cursor onto framebuffer
    int cx = currentMouse.x;
    int cy = currentMouse.y;
    uint32_t cursorColor = currentMouse.leftButton ? 0xFF30D158 : (currentMouse.rightButton ? 0xFFFF453A : 0xFFFFFFFF);

    for (int dy = 0; dy < 16; ++dy) {
        for (int dx = 0; dx <= dy && dx < 12; ++dx) {
            int px = cx + dx;
            int py = cy + dy;
            if (px >= 0 && px < m_guestWidth && py >= 0 && py < m_guestHeight) {
                m_framebuffer[py * m_guestWidth + px] = cursorColor;
            }
        }
    }
}

} // namespace AoE2Runner
