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
}
