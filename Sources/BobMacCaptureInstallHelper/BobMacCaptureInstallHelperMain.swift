import Foundation

@main
enum BobMacCaptureInstallHelperMain {
    static func main() {
        do {
            let command = try InstallHelperArguments.parse(
                Array(CommandLine.arguments.dropFirst())
            )
            switch command {
            case .help:
                writeStderr(InstallHelperArguments.usage)
                if !InstallHelperArguments.usage.hasSuffix("\n") {
                    writeStderr("\n")
                }
                exit(0)
            case .discover(let installPath):
                let pids = InstallRelauncher().discover(installPath: installPath)
                for pid in pids {
                    print(pid)
                }
            case .restart(let installPath, let pids):
                try InstallRelauncher().restart(installPath: installPath, pids: pids)
            }
        } catch let error as InstallHelperError {
            writeStderr(error.message)
            writeStderr("\n")
            exit(error.exitStatus)
        } catch {
            writeStderr(String(describing: error))
            writeStderr("\n")
            exit(70)
        }
    }

    private static func writeStderr(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}
