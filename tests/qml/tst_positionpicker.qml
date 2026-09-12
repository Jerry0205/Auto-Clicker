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

    function init() { picked.clear(); cancelled.clear(); finished.clear(); host.show() }
    function cleanup() { testCase.parent = null; picker.finish(); picked.clear() }
    function begin() {
        picker.begin(host.screen, 100, 150, false, false)
        tryCompare(picker, "inputReady", true)
        compare(host.visible, false)
        testCase.parent = picker.contentItem
        tryVerify(function() { return picker.active })
        wait(20)
        picker.setTarget(100, 150)
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

    function test_cancel_does_not_pick() {
        begin()
        keyClick(Qt.Key_Escape)
        tryCompare(picker, "selecting", false)
        compare(picked.count, 0)
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
        compare(picked.count, 1)
        compare(picked.signalArguments[0][1], 25)
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
        verify(!picker.magnifierReady)
        testCase.parent = picker.contentItem
        tryVerify(function() { return picker.active })
        wait(20)
        keyClick(Qt.Key_Return)
        compare(picked.count, 1)
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
        testCase.parent = picker.contentItem
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

    function test_capture_enables_magnifier_and_clears_on_finish() {
        picker.begin(host.screen, 20, 30, false, true)
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="'
            + picker.desktopBounds.width + '" height="' + picker.desktopBounds.height
            + '"><rect width="100%" height="100%" fill="blue"/></svg>'
        picker.acceptScreenshot(picker.captureId, "data:image/svg+xml," + encodeURIComponent(svg), "")
        tryCompare(picker, "magnifierReady", true)
        tryCompare(picker, "inputReady", true)
        picker.finish()
        compare(picker.magnifierReady, false)
    }

    function test_wrong_capture_geometry_falls_back() {
        picker.begin(host.screen, 20, 30, false, true)
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="1"/>'
        picker.acceptScreenshot(picker.captureId, "data:image/svg+xml," + encodeURIComponent(svg), "")
        tryVerify(function() { return picker.captureError.length > 0 })
        compare(picker.magnifierReady, false)
        verify(picker.inputReady)
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
