import SwiftUI

extension Binding where Value: Equatable {
    /// A binding that drops a write of the value it already has. macOS writes some bindings back on
    /// every update (the menu bar item's `isInserted`), and before Swift 6.2 an @Observable property
    /// tells its observers about every write, changed or not: the update then causes the next one.
    static func changesOnly(get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: get, set: { value in
            if value != get() {
                set(value)
            }
        })
    }
}
