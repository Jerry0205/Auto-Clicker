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
        compare(controller.configDirty, true)
    }

    function test_running_and_pending_runs_disable_settings() {
        for (const state of ["running", "busy"]) {
            controller[state] = true
            for (const name of ["intervalInput", "repeatInput", "xInput", "yInput", "monitorInput"])
                compare(findChild(main, name).enabled, false)
            controller[state] = false
        }
    }

    function test_close_saves_draft_and_keeps_window_open_on_write_error() {
        controller.interval_ms = 250
        controller.mark_settings_changed()
        controller.saveConfigSucceeds = false
        controller.running = true
        main.close()
        compare(controller.saveCount, 1)
        compare(controller.shutdownCount, 1)
        compare(controller.running, false)
        compare(main.visible, true)
        const dialog = findChild(main, "saveFailureDialog")
        verify(dialog !== null)
        tryCompare(dialog, "opened", true)
        keyClick(Qt.Key_Escape)
        compare(dialog.opened, true)

        controller.saveConfigSucceeds = true
        const continueEditing = findChild(main, "continueEditingButton")
        verify(continueEditing !== null)
        mouseClick(continueEditing)
        compare(controller.initializeCount, 1)
        main.close()
        compare(controller.saveCount, 2)
        compare(controller.shutdownCount, 2)
    }

    function test_discard_after_save_error_closes_without_retrying() {
        controller.mark_settings_changed()
        controller.saveConfigSucceeds = false
        main.close()
        const dialog = findChild(main, "saveFailureDialog")
        tryCompare(dialog, "opened", true)
        const discard = findChild(main, "discardSettingsButton")
        verify(discard !== null)
        mouseClick(discard)
        compare(controller.saveCount, 1)
        compare(controller.shutdownCount, 2)
    }

    function test_unchanged_window_does_not_rewrite_config() {
        main.close()
        compare(controller.saveCount, 0)
        compare(controller.shutdownCount, 1)
    }
}
