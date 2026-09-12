import QtQuick
import QtTest
import "../../qml"

TestCase {
    name: "MonitorSelection"
    MonitorSelection { id: monitors }

    function screen(name, serial) {
        return { name: name, manufacturer: "Acme", model: "Display", serialNumber: serial,
            width: 1920, height: 1080, devicePixelRatio: 1 }
    }

    function test_restores_monitor_after_order_changes() {
        const left = screen("DP-1", "123")
        const right = screen("DP-2", "456")
        compare(monitors.restoreIndex([right, left], monitors.identity(left)), 1)
    }
    function test_missing_legacy_and_ambiguous_identity_require_confirmation() {
        const left = screen("DP-1", "123")
        const right = screen("DP-2", "456")
        compare(monitors.restoreIndex([right], monitors.identity(left)), -1)
        compare(monitors.restoreIndex([left], ""), -1)
        compare(monitors.restoreIndex([left, left], monitors.identity(left)), -1)
    }
    function test_changed_resolution_or_scaling_requires_confirmation() {
        const left = screen("DP-1", "123")
        const saved = monitors.identity(left)
        left.width = 1280
        compare(monitors.restoreIndex([left], saved), -1)
        left.width = 1920
        left.devicePixelRatio = 1.5
        compare(monitors.restoreIndex([left], saved), -1)
    }
}
