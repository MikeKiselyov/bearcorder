// Posts one automation command to a running Bugbear and exits.
//   bugbear-send <command>
// Same distributed notification the app listens for (DevTools/Automation.swift), without Apple Events.
// scripts/dev/bugbear-command.sh compiles this file into .build/bugbear-send when it is missing or older.
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: bugbear-send <command>\n".utf8))
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("Bugbear.automation"),
    object: arguments[1],
    userInfo: nil,
    deliverImmediately: true
)
