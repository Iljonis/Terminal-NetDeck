import Foundation
import NetDeckCore
import WinSDK

@main
enum NetDeckAskpass {
    @MainActor
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        guard environment[Askpass.flag] == "1",
              environment["NETDECK_SESSION"].flatMap(UUID.init(uuidString:)) != nil,
              CommandLine.arguments.count == 2 else { ExitProcess(1) }
        let code = Askpass.run(arguments: CommandLine.arguments, environment: environment)
        ExitProcess(UInt32(bitPattern: code))
    }
}
