import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 1. Install signal and exception crash reporter immediately before any subsystem initializes
        CrashReporter.install()
        Log.info(.general, "Application did finish launching. CrashReporter active.")
        
        // 2. Initialize UI Window
        window = UIWindow(frame: UIScreen.main.bounds)
        let gameVC = GameViewController()
        window?.rootViewController = gameVC
        window?.makeKeyAndVisible()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Log.info(.general, "App resigning active -> pausing emulation runner.")
        EmulationBridgeWrapper.sharedInstance().pause()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Log.info(.general, "App became active -> resuming emulation runner.")
        EmulationBridgeWrapper.sharedInstance().resume()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Log.info(.general, "App terminating -> shutting down runner.")
        EmulationBridgeWrapper.sharedInstance().shutdown()
    }
}
