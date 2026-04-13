//
//  TinyPNG4MacApp.swift
//  TinyPNG4Mac
//
//  Created by kyleduo on 2024/11/16.
//

import SwiftData
import SwiftUI

@main
struct TinyPNG4MacApp: App {
    @Environment(\.openWindow) private var openWindow

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelgate
    @StateObject var appContext = AppContext.shared
    @StateObject var vm: MainViewModel = MainViewModel()
    @StateObject var debugVM: DebugViewModel = DebugViewModel.shared

    @State var firstAppear: Bool = true
    @State var lastTaskCount = 0

    var body: some Scene {
        Window("Tiny Image", id: "main") {
            MainContentView(vm: vm)
                .frame(
                    minWidth: appContext.minSize.width,
                    idealWidth: appContext.minSize.width,
                    maxWidth: appContext.maxSize.width,
                    minHeight: appContext.minSize.height,
                    idealHeight: appContext.minSize.height
                )
                .onAppear {
                    if !firstAppear {
                        return
                    }
                    firstAppear = false

                    appDelgate.configure(viewModel: vm) {
                        openWindow(id: "main")
                    }
                }
                .environmentObject(appContext)
                .environmentObject(debugVM)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .defaultSize(appContext.minSize)
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button(action: {
                    // Open the "about" window
                    openWindow(id: "about")
                }, label: {
                    Text("About...")
                })
            }
        }

        // Note the id "about" here
        Window("About Tiny Image", id: "about") {
            AboutView()
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }

    func animateWindowFrame(_ window: NSWindow, newFrame: NSRect) {
        let animation = NSViewAnimation()
        animation.viewAnimations = [
            [
                NSViewAnimation.Key.target: window,
                NSViewAnimation.Key.startFrame: NSValue(rect: window.frame),
                NSViewAnimation.Key.endFrame: NSValue(rect: newFrame),
            ],
        ]
        animation.duration = 0.3
        animation.animationCurve = .easeOut
        animation.start()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var vm: MainViewModel?
    private var openMainWindow: (() -> Void)?

    private var pendingOpenUrls: [URL] = []
    private var appDidFinishLaunching = false

    func configure(viewModel vm: MainViewModel, openMainWindow: @escaping () -> Void) {
        if self.vm == nil {
            self.vm = vm
        }
        self.openMainWindow = openMainWindow

        tryHandleOpenUrls()
    }

    @objc(compressSelection:userData:error:)
    func compressSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?
            .map(\.standardizedFileURL) ?? []

        if urls.isEmpty {
            error.pointee = "No valid files were provided to Tiny Image." as NSString
            return
        }

        enqueueOpenUrls(urls, bringAppToFront: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileUtils.initPaths()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        if let window = NSApp.windows.first {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }

        appDidFinishLaunching = true

        tryHandleOpenUrls()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        enqueueOpenUrls(urls, bringAppToFront: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let vm = vm else {
            return .terminateNow
        }

        if !vm.shouldTerminate() {
            vm.showRunnningTasksAlert()
            return .terminateCancel
        } else {
            return .terminateNow
        }
    }

    private func tryHandleOpenUrls() {
        guard appDidFinishLaunching, let vm, !pendingOpenUrls.isEmpty else {
            return
        }

        let urls = pendingOpenUrls
        pendingOpenUrls.removeAll()

        let imageUrls = FileUtils.findImageFiles(urls: urls)
        if !imageUrls.isEmpty {
            vm.createTasks(imageURLs: imageUrls)
        }
    }

    private func enqueueOpenUrls(_ urls: [URL], bringAppToFront: Bool) {
        guard !urls.isEmpty else {
            return
        }

        for url in urls {
            if !pendingOpenUrls.contains(where: { $0.isSameFilePath(as: url) }) {
                pendingOpenUrls.append(url)
            }
        }

        DispatchQueue.main.async {
            if bringAppToFront {
                self.openMainWindow?()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }

            self.tryHandleOpenUrls()
        }
    }
}
