import QtQuick
import QtTest
import "../../qml"

TestCase {
    name: "MainControls"
    when: windowShown
    width: 600
    height: 800

    Component { id: mainComponent; Main { smokeTest: true } }
    property var main
    property var controller

    function init() {
        main = createTemporaryObject(mainComponent, null)
        verify(main !== null)
        controller = findChild(main, "controller")
        verify(controller !== null)
        main.requestActivate()
        tryCompare(main, "active", true)
    }
    function cleanup() { main.close() }

    function test_saved_coordinates_are_visible_after_monitor_initialization() {
        compare(controller.fixed_x, 80)
        compare(controller.fixed_y, 150)
        compare(findChild(main, "xInput").value, controller.fixed_x)
        compare(findChild(main, "yInput").value, controller.fixed_y)
    }

    function test_typed_values_reach_hotkey_without_focus_loss_data() {
        return [
            { tag: "interval", input: "intervalInput", property: "interval_ms", value: 250 },
            { tag: "repeat", input: "repeatInput", property: "repeat_count", value: 42 },
            { tag: "x", input: "xInput", property: "fixed_x", value: 123 },
            { tag: "y", input: "yInput", property: "fixed_y", value: 234 }
        ]
    }
    function test_typed_values_reach_hotkey_without_focus_loss(data) {
        controller.repeat_until_stopped = false
        controller.current_position = false
        const input = findChild(main, data.input)
        verify(input !== null)
        input.contentItem.forceActiveFocus()
        keyClick(Qt.Key_A, Qt.ControlModifier)
        for (const digit of String(data.value)) keyClick(digit)
        verify(input.contentItem.activeFocus)
        compare(input.contentItem.text, String(data.value))
        compare(input.value, data.value)
        compare(controller[data.property], data.value)
    }

    function test_running_and_pending_runs_disable_settings() {
        for (const state of ["running", "busy"]) {
            controller[state] = true
            for (const name of ["intervalInput", "repeatInput", "xInput", "yInput", "monitorInput"])
                compare(findChild(main, name).enabled, false)
            controller[state] = false
        }
    }

    function test_run_control_stays_visible_at_minimum_size_data() {
        return [
            { tag: "cursor-ready", fixed: false, running: false, busy: false },
            { tag: "fixed-ready", fixed: true, running: false, busy: false },
            { tag: "cursor-running", fixed: false, running: true, busy: false },
            { tag: "fixed-running", fixed: true, running: true, busy: false },
            { tag: "cursor-starting", fixed: false, running: false, busy: true },
            { tag: "fixed-starting", fixed: true, running: false, busy: true }
        ]
    }

    function test_run_control_stays_visible_at_minimum_size(data) {
        main.width = main.minimumWidth
        main.height = main.minimumHeight
        controller.current_position = !data.fixed
        controller.fixed_position_confirmed = false
        controller.error_message = "Ein Portalfehler mit zusätzlicher Beschreibung"
        controller.status = data.busy ? "Warte auf Wayland-Berechtigung …" : (data.running ? "Klickt" : "Bereit")
        controller.busy = data.busy
        controller.running = data.running

        const footer = findChild(main, "runFooter")
        const button = findChild(main, "runControl")
        const status = findChild(main, "runStatus")
        verify(footer !== null)
        verify(button !== null)
        verify(status !== null)
        tryCompare(main, "height", main.minimumHeight)
        wait(50)

        function inWindow(item) {
            const position = item.mapToItem(null, 0, 0)
            return position.x >= 0 && position.y >= 0
                && position.x + item.width <= main.width
                && position.y + item.height <= main.height
        }
        verify(button.visible && inWindow(button), "Stop button must remain in the window")
        verify(status.visible && inWindow(status), "Run status must remain in the window")
        compare(button.Accessible.name, data.running || data.busy ? "Stoppen" : "Starten")
        compare(status.text, "Status: " + controller.status)

        const flickable = main.pageStack.currentItem.flickable
        verify(flickable.contentHeight > flickable.height, "Settings must remain scrollable")
        flickable.contentY = flickable.contentHeight - flickable.height
        wait(50)
        verify(button.visible && inWindow(button), "Scrolling settings must not move the run control")
        verify(status.visible && inWindow(status), "Scrolling settings must not move the run status")
    }

    function test_run_control_can_be_used_with_keyboard() {
        const button = findChild(main, "runControl")
        verify(button.activeFocusOnTab)
        button.forceActiveFocus()
        verify(button.activeFocus)
        keyClick(Qt.Key_Space)
        compare(controller.toggle_count, 1)
    }
}
