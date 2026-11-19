import Foundation
import L99Core
import L99Link

/// Installs a whole interface file on the screen through its bootloader (cable, Fn+X,0,6), the same
/// routine as `l99probe isp-flash --direct`. Taking the screen from macOS's serial driver needs
/// administrator rights, so the app runs its own executable in this mode through the standard macOS
/// administrator prompt. Progress goes to a small status file the app watches:
///   `writing <percent>`, `verifying <percent>`, then `done <final value>` or `error <message>`.
nonisolated enum InterfaceInstaller {
    static let flag = "--install-interface"

    /// Returns an exit code when the arguments ask for an install, nil otherwise.
    static func runIfRequested(_ args: [String]) -> Int32? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count,
              let p = args.firstIndex(of: "--status"), p + 1 < args.count else { return nil }
        let file = args[i + 1], status = URL(fileURLWithPath: args[p + 1])
        func report(_ line: String) {
            try? Data((line + "\n").utf8).write(to: status, options: .atomic)
        }
        do {
            guard getuid() == 0 else { throw LinkError("The installer needs administrator rights.") }
            guard let data = FileManager.default.contents(atPath: file) else { throw LinkError("Can't read the skin file.") }
            guard data.count == InterfaceFile.stockSize else {
                throw LinkError("That isn't a complete interface file (\(data.count) bytes). Nothing was sent.")
            }
            let image = try ISP.Image(Array(data))
            let port = try BootloaderPort(directUSB: true)
            var last = ""
            let final = try port.install(image) { phase, done, total in
                let line = "\(phase == .writing ? "writing" : "verifying") \(done * 100 / max(total, 1))"
                if line != last { last = line; report(line) }
            }
            report(String(format: "done %08X", final ?? 0))
            return 0
        } catch {
            report("error \(error.localizedDescription)")
            return 1
        }
    }
}
