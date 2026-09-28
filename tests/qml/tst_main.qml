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

    function closeButtonIn(item) {
        if (item.icon && item.icon.name === "dialog-close") return item
        for (const child of item.children) {
            const button = closeButtonIn(child)
            if (button) return button
        }
        return null
    }

    function test_error_banner_reappears_after_close() {
        const banner = findChild(main, "errorBanner")
        verify(banner !== null)

        for (const message of ["First error", "Second error", "Second error"]) {
            controller.error_message = message
            tryCompare(banner, "visible", true)
            compare(banner.text, message)

            const closeButton = closeButtonIn(banner)
            verify(closeButton !== null)
            mouseClick(closeButton)
            tryCompare(banner, "visible", false)
            compare(controller.error_message, "")
        }
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

    function test_screen_changes_keep_cursor_position_runs() {
        compare(controller.current_position, true)
        controller.monitor_width += 1
        controller.running = true
        main.handleScreensChanged()
        compare(controller.running, true)
        compare(findChild(main, "monitorStopMessage").visible, false)
    }

    function test_unchanged_monitor_keeps_fixed_position_runs() {
        controller.current_position = false
        controller.fixed_position_confirmed = true
        controller.running = true
        main.handleScreensChanged()
        compare(controller.running, true)
        compare(findChild(main, "monitorStopMessage").visible, false)
    }

    function test_changed_monitor_stops_fixed_position_runs_with_reason() {
        const message = findChild(main, "monitorStopMessage")
        for (const state of ["running", "busy"]) {
            controller.current_position = false
            controller.fixed_position_confirmed = true
            controller.monitor_width += 1
            controller[state] = true
            main.handleScreensChanged()
            compare(controller[state], false)
            tryCompare(message, "visible", true)
            controller[state] = true
            tryCompare(message, "visible", false)
            controller[state] = false
        }
    }

    function test_monitor_activation_does_not_confirm_clamped_coordinates() {
        controller.current_position = false
        const monitorInput = findChild(main, "monitorInput")
        const screen = main.monitorOptions[0].screen
        controller.fixed_x = screen.width + 100
        controller.fixed_position_confirmed = true
        monitorInput.activated(0)
        compare(controller.fixed_x, screen.width - 1)
        compare(controller.fixed_position_confirmed, false)

        monitorInput.activated(0)
        compare(controller.fixed_position_confirmed, true)
    }

    function test_coordinate_inputs_have_distinct_accessible_names() {
        const x = findChild(main, "xInput")
        const y = findChild(main, "yInput")
        verify(x !== null)
        verify(y !== null)
        compare(x.Accessible.name, "X-Koordinate auf dem gewählten Monitor")
        compare(y.Accessible.name, "Y-Koordinate auf dem gewählten Monitor")
        compare(x.contentItem.Accessible.name, x.Accessible.name)
        compare(y.contentItem.Accessible.name, y.Accessible.name)
    }

    function test_position_selection_opens_without_capture_delay() {
        controller.current_position = false
        main.beginPicker(false)
        verify(main.positionPicker !== null)
        compare(main.positionPicker.visible, true)
        tryVerify(function() { return main.positionPicker && main.positionPicker.inputReady })
        main.finishPicker()
        compare(main.positionPicker, null)
    }
}
