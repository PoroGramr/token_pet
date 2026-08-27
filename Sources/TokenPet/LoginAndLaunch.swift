import AppKit
import Foundation
import ServiceManagement

enum ClaudeLoginLauncher {
    static func openLoginCommand() throws {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.park.tokenpet", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let commandURL = directory.appendingPathComponent("claude-login.command")
        let script = """
        #!/bin/zsh
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        exec claude auth login
        """
        try script.write(to: commandURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: commandURL.path)
        guard NSWorkspace.shared.open(commandURL) else {
            throw CocoaError(.fileNoSuchFile)
        }
    }
}

@MainActor
final class LoginItemManager {
    private let defaults = UserDefaults.standard
    private let firstLaunchKey = "didAttemptAutomaticLoginItemRegistration"

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enableOnFirstLaunch() -> String? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        guard !defaults.bool(forKey: firstLaunchKey) else { return nil }
        do {
            try setEnabled(true)
            defaults.set(true, forKey: firstLaunchKey)
            return nil
        } catch {
            return "로그인 시 실행을 자동 등록하지 못했습니다"
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
