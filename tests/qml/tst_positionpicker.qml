import QtQuick
import QtTest
import "../../qml"

TestCase {
    id: testCase
    name: "PositionPicker"
    when: windowShown
    width: 400
    height: 300

    Window { id: host; width: 400; height: 300; visible: true }
    PositionPicker { id: picker; hostWindow: host }
    SignalSpy { id: cancelled; target: picker; signalName: "screenshotCancelled" }
    SignalSpy { id: finished; target: picker; signalName: "finished" }
    SignalSpy { id: picked; target: picker; signalName: "picked" }

    function init() {
        picked.clear(); cancelled.clear(); finished.clear()
        host.show()
        host.requestActivate()
        tryCompare(host, "active", true)
    }
    function cleanup() { picker.finish(); picked.clear() }
    function begin() {
        host.requestActivate()
        tryVerify(function() { return host.active })
        picker.begin(host.screen, 100, 150, false, false)
        tryCompare(picker, "inputReady", true)
        tryVerify(function() { return picker.active })
        wait(20)
        compare(host.visible, true)
        picker.setTarget(100, 150)
    }

    function test_restores_window_geometry_data() {
        return [
            { tag: "confirm", cancel: false, maximized: false },
            { tag: "cancel", cancel: true, maximized: false },
            { tag: "maximized", cancel: false, maximized: true }
        ]
    }

    function test_restores_window_geometry(data) {
        host.showNormal()
        host.width = 530
        host.height = 370
        if (data.maximized) host.showMaximized()
        host.requestActivate()
        tryVerify(function() { return host.active })
        wait(100) // Let the compositor finish configuring the host before saving geometry.
        const original = { x: host.x, y: host.y, width: host.width, height: host.height,
                           visibility: host.visibility }
        begin()
        keyClick(data.cancel ? Qt.Key_Escape : Qt.Key_Return)
        tryCompare(host, "active", true)
        tryCompare(host, "visibility", original.visibility)
        tryCompare(host, "width", original.width)
        tryCompare(host, "height", original.height)
        compare(host.x, original.x)
        compare(host.y, original.y)
        host.showNormal()
    }

    function test_keyboard_confirm_and_restore() {
        begin()
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Down, Qt.ShiftModifier)
        compare(picker.targetX, 101)
        compare(picker.targetY, 160)
        keyClick(Qt.Key_Return)
        compare(picked.count, 1)
        compare(picked.signalArguments[0][0], 101)
        compare(picked.signalArguments[0][1], 160)
        compare(picker.visible, false)
        compare(host.visible, true)
    }

    function test_click_then_keyboard_adjustment_keeps_picker_open() {
        begin()
        mouseClick(picker.contentItem, 120, 180)
        compare(picked.count, 0)
        verify(picker.visible)
        compare(picker.targetX, 120)
        compare(picker.targetY, 180)
        mouseMove(picker.contentItem, 300, 300)
        compare(picker.targetX, 120)
        compare(picker.targetY, 180)
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Up)
        compare(picker.targetX, 121)
        compare(picker.targetY, 179)
        keyClick(Qt.Key_Return)
        compare(picked.count, 1)
        compare(picked.signalArguments[0][0], 121)
        compare(picked.signalArguments[0][1], 179)
        compare(host.visible, true)
    }

    function test_click_recovers_keyboard_focus() {
        begin()
        const other = Qt.createQmlObject('import QtQuick; Item { focus: true }', picker.contentItem)
        other.forceActiveFocus()
        mouseClick(picker.contentItem, 120, 180)
        keyClick(Qt.Key_Right)
        compare(picker.targetX, 121)
        keyClick(Qt.Key_Return)
        compare(picked.count, 1)
        other.destroy()
    }

    function test_cancel_does_not_pick() {
        begin()
        keyClick(Qt.Key_Escape)
        tryCompare(picker, "selecting", false)
        compare(picked.count, 0)
        compare(host.visible, true)
    }

    function test_right_click_cancels_without_changing_target() {
        begin()
        mouseClick(picker.contentItem, 120, 180, Qt.RightButton)
        tryCompare(picker, "selecting", false)
        compare(picked.count, 0)
        compare(picker.targetX, 100)
        compare(picker.targetY, 150)
        compare(host.visible, true)
    }

    function test_edges_and_hint_are_selectable() {
        begin()
        picker.setTarget(-10, -20)
        compare(picker.targetX, 0)
        compare(picker.targetY, 0)
        verify(picker.hintAtBottom)
        picker.setTarget(picker.width + 10, picker.height + 10)
        compare(picker.targetX, picker.width - 1)
        compare(picker.targetY, picker.height - 1)
        verify(!picker.hintAtBottom)
        mouseClick(picker.contentItem, picker.width / 2, 25)
        compare(picked.count, 0)
        verify(picker.visible)
        keyClick(Qt.Key_Return)
        compare(picked.count, 1)
        compare(picked.signalArguments[0][1], 25)
    }

    function test_fresh_picker_transfers_focus_and_returns_coordinates_on_each_monitor() {
        const component = Qt.createComponent("../../qml/PositionPicker.qml")
        compare(component.status, Component.Ready)
        const screens = Qt.application.screens
        for (let i = 0; i < screens.length; ++i) {
            host.show()
            host.requestActivate()
            tryVerify(function() { return host.active })
            const fresh = createTemporaryObject(component, host, { hostWindow: host, screen: screens[i] })
            verify(fresh !== null)
            let result = null
            fresh.picked.connect(function(x, y) { result = { x: x, y: y } })
            fresh.begin(screens[i], 40, 50, false, false)
            tryCompare(fresh, "inputReady", true)
            tryVerify(function() { return fresh.active })
            compare(fresh.screen.name, screens[i].name)
            compare(host.visible, true)
            mouseClick(fresh.contentItem, 140, 160)
            verify(fresh.visible)
            keyClick(Qt.Key_Right)
            keyClick(Qt.Key_Return)
            compare(result.x, 141)
            compare(result.y, 160)
            fresh.destroy()
            compare(host.visible, true)
        }
    }

    function test_preview_does_not_modify_position() {
        picker.begin(host.screen, 20, 30, true, false)
        tryCompare(picker, "inputReady", true)
        picker.confirm()
        compare(picked.count, 0)
        tryCompare(picker, "selecting", false, 2500)
        compare(host.visible, true)
    }

    function test_capture_failure_falls_back() {
        picker.begin(host.screen, 20, 30, false, true)
        verify(picker.waitingForScreenshot)
        picker.acceptScreenshot(picker.captureId, "", "denied")
        tryCompare(picker, "inputReady", true)
        verify(picker.captureError.length > 0)
        tryVerify(function() { return picker.active })
        wait(20)
        keyClick(Qt.Key_Return)
        tryCompare(picked, "count", 1)
        compare(host.visible, true)
    }

    function test_capture_timeout_restores_interactive_selection() {
        picker.begin(host.screen, 20, 30, false, true)
        const requestId = picker.captureId
        tryCompare(picker, "inputReady", true, 4000)
        compare(picker.waitingForScreenshot, false)
        compare(cancelled.count, 1)
        compare(cancelled.signalArguments[0][0], requestId)
        picker.acceptScreenshot(requestId, "", "late response")
        verify(picker.captureError.indexOf("zu lange") >= 0)
        verify(picker.captureError.indexOf("Deny") >= 0)
        verify(picker.captureError.indexOf("Verweigern") >= 0)
        tryVerify(function() { return picker.active })
        wait(20)
        keyClick(Qt.Key_Escape)
        tryCompare(picker, "selecting", false)
        compare(host.visible, true)
        compare(picked.count, 0)
    }

    function test_finish_is_idempotent_and_cancels_capture() {
        picker.begin(host.screen, 20, 30, false, true)
        picker.finish()
        picker.finish()
        compare(cancelled.count, 1)
        compare(finished.count, 1)
        compare(host.visible, true)
    }

    function test_unverified_capture_falls_back_data() {
        const screens = Qt.application.screens
        let left = screens[0].virtualX
        let top = screens[0].virtualY
        let right = left + screens[0].width
        let bottom = top + screens[0].height
        for (const screen of screens) {
            left = Math.min(left, screen.virtualX)
            top = Math.min(top, screen.virtualY)
            right = Math.max(right, screen.virtualX + screen.width)
            bottom = Math.max(bottom, screen.virtualY + screen.height)
        }
        const width = right - left
        const height = bottom - top
        return [
            { tag: "matching desktop size", width: width, height: height },
            { tag: "proportional crop", width: width / 2, height: height / 2 },
            { tag: "single monitor", width: screens[0].width, height: screens[0].height },
            { tag: "scaled desktop", width: width * 1.5, height: height * 1.5 }
        ]
    }

    function test_unverified_capture_falls_back(data) {
        picker.begin(host.screen, 20, 30, false, true)
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="'
            + Math.round(data.width) + '" height="' + Math.round(data.height) + '"/>'
        picker.acceptScreenshot(picker.captureId, "data:image/svg+xml," + encodeURIComponent(svg), "")
        tryCompare(picker, "inputReady", true)
        verify(picker.captureError.indexOf("Positionsdaten") >= 0)
        picker.setTarget(20, 30)
        picker.confirm()
        compare(picked.count, 1)
        compare(picked.signalArguments[0][0], 20)
        compare(picked.signalArguments[0][1], 30)
    }

    function test_previous_capture_is_ignored() {
        picker.begin(host.screen, 20, 30, false, true)
        const previousId = picker.captureId
        picker.finish()
        picker.begin(host.screen, 20, 30, false, true)
        picker.acceptScreenshot(previousId, "", "denied")
        verify(picker.waitingForScreenshot)
        compare(picker.visible, false)
    }

    function test_late_capture_does_not_reopen_picker() {
        picker.begin(host.screen, 20, 30, false, true)
        picker.finish()
        picker.acceptScreenshot(picker.captureId, "", "denied")
        compare(picker.selecting, false)
        compare(picker.visible, false)
        compare(host.visible, true)
    }
}
