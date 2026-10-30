// Posts one automation command to a running app and exits.
//   app-send <notification name> <command>
// Same distributed notification the app listens for (DevTools/Automation.swift), without Apple Events.
// scripts/dev/app-command.sh compiles this file into .build/app-send when it is missing or older.
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: app-send <notification name> <command>\n".utf8))
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(arguments[1]),
    object: arguments[2],
    userInfo: nil,
    deliverImmediately: true
)
