//
//  SceneDelegate.swift
//  J2MEEmulator
//
//  Created by Alexander Goremykin on 19.03.2026.
//

import UIKit

/// Forwards orientation queries to the top view controller
private class OrientationNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? .portrait
    }
}

extension Notification.Name {
    static let j2meOpenSharedJAR = Notification.Name("J2MEOpenSharedJAR")
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let vc = AppsListViewController()
        let nav = OrientationNavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = false

        // Transparent navigation bar over black springboard
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.tintColor = .white

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = nav
        window?.makeKeyAndVisible()

        if let context = connectionOptions.urlContexts.first {
            DispatchQueue.main.async { [weak self] in
                self?.importSharedJAR(context.url)
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            importSharedJAR(context.url)
        }
    }

    private func importSharedJAR(_ source: URL) {
        guard source.pathExtension.lowercased() == "jar" else { return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let games = docs.appendingPathComponent("games", isDirectory: true)
        try? fm.createDirectory(at: games, withIntermediateDirectories: true)
        var destination = games.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }

        do {
            try fm.copyItem(at: source, to: destination)
            destination = destination.standardizedFileURL
            let post = {
                NotificationCenter.default.post(name: .j2meOpenSharedJAR, object: destination)
            }
            if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
        } catch {
            print("[J2ME] Shared JAR import failed: \(error)")
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if UserDefaults.standard.bool(forKey: "J2MEKeepScreenOn") {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        if UserDefaults.standard.bool(forKey: "J2MEKeepScreenOn") {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        if UserDefaults.standard.bool(forKey: "J2MEKeepScreenOn") {
            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "J2MEKeepAlive") {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
            }
        }
    }
}
