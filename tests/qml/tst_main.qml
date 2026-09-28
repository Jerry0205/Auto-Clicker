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

    function findItem(item, predicate) {
        if (predicate(item)) return item
        for (const child of item.children) {
            const found = findItem(child, predicate)
            if (found) return found
        }
        return null
    }

    function choice(groupName, label) {
        const group = findChild(main, groupName)
        verify(group !== null)
        const button = findItem(group, item => item.Accessible.name === label && item.checkable)
        verify(button !== null, label)
        return button
    }

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
            for (const name of ["intervalInput", "repeatInput", "xInput", "yInput", "monitorInput",
                                "mouseButtonInput", "clickTypeInput", "positionModeInput", "hotkeyButton"])
                compare(findChild(main, name).enabled, false, name)
            compare(findChild(main, "startButton").enabled, true)
            controller[state] = false
        }
    }

    function test_choice_buttons_update_controller_data() {
        return [
            { tag: "right button", group: "mouseButtonInput", label: "Rechts", property: "mouse_button", value: 1 },
            { tag: "middle button", group: "mouseButtonInput", label: "Mitte", property: "mouse_button", value: 2 },
            { tag: "double click", group: "clickTypeInput", label: "Doppelt", property: "click_type", value: 1 },
            { tag: "repeat count", group: "repeatModeInput", label: "Anzahl", property: "repeat_until_stopped", value: false },
            { tag: "fixed position", group: "positionModeInput", label: "Feste Position", property: "current_position", value: false }
        ]
    }
    function test_choice_buttons_update_controller(data) {
        const button = choice(data.group, data.label)
        verify(!button.checked)
        mouseClick(button)
        compare(controller[data.property], data.value)
        verify(button.checked)
        mouseClick(button)
        verify(button.checked, "clicking the selected option keeps it selected")
        compare(button.Accessible.role, Accessible.RadioButton)
    }

    function test_fixed_position_controls_only_show_for_fixed_position() {
        for (const name of ["monitorInput", "xInput", "pickButton", "previewButton"])
            verify(!findChild(main, name).visible, name)
        controller.current_position = false
        for (const name of ["monitorInput", "xInput", "pickButton", "previewButton"])
            tryVerify(() => findChild(main, name).visible, 1000, name)
    }

    function test_unconfirmed_position_can_be_confirmed() {
        controller.current_position = false
        controller.fixed_position_confirmed = false
        const message = findChild(main, "confirmMessage")
        tryVerify(() => message.visible)
        verify(!findChild(main, "previewButton").enabled)
        message.actions[0].trigger()
        compare(controller.fixed_position_confirmed, true)
        tryVerify(() => !message.visible)
    }

    function test_coordinate_inputs_have_accessible_names() {
        for (const [name, label] of [["xInput", "X-Koordinate auf dem Monitor"], ["yInput", "Y-Koordinate auf dem Monitor"]]) {
            const input = findChild(main, name)
            compare(input.Accessible.name, label)
            compare(input.contentItem.Accessible.name, label, "focused text field")
        }
    }

    function test_rate_text_names_clicks_and_slow_intervals_data() {
        return [
            { tag: "single", interval: 100, type: 0, text: "10 Klicks/s" },
            { tag: "double", interval: 100, type: 1, text: "10 Doppelklicks/s" },
            { tag: "one per second", interval: 1000, type: 0, text: "1 Klick/s" },
            { tag: "seconds", interval: 2000, type: 0, text: "alle 2 s" },
            { tag: "minutes", interval: 120000, type: 1, text: "alle 2 min" },
            { tag: "hours", interval: 7200000, type: 0, text: "alle 2 h" }
        ]
    }
    function test_rate_text_names_clicks_and_slow_intervals(data) {
        controller.interval_ms = data.interval
        controller.click_type = data.type
        compare(findChild(main, "rateLabel").text, data.text)
        controller.status = "Klickt"
        controller.running = true
        compare(findChild(main, "statusLabel").text, "Klickt · " + data.text)
        controller.running = false
    }

    function test_start_stop_stays_visible_at_minimum_size_data() {
        return [
            { tag: "cursor", fixed: false, error: "" },
            { tag: "fixed", fixed: true, error: "" },
            { tag: "fixed with error", fixed: true, error: "Ein Fehler mit einer längeren Beschreibung, die umbricht." }
        ]
    }
    function test_start_stop_stays_visible_at_minimum_size(data) {
        main.width = main.minimumWidth
        main.height = main.minimumHeight
        controller.current_position = !data.fixed
        controller.fixed_position_confirmed = false
        controller.error_message = data.error
        controller.running = true
        const button = findChild(main, "startButton")
        tryCompare(button, "text", "Stoppen")
        wait(50)
        const bottom = button.mapToItem(main.contentItem, 0, button.height).y
        verify(bottom <= main.contentItem.height, "Stop button bottom " + bottom + " > " + main.contentItem.height)
        verify(button.visible)
        mouseClick(button)
        compare(controller.running, false)
    }

    function test_closed_error_banner_shows_later_errors() {
        const banner = findChild(main, "errorMessage")
        controller.error_message = "Erster Fehler"
        tryVerify(() => banner.visible)
        const close = findItem(banner, item => item.icon !== undefined && item.icon.name === "dialog-close")
        verify(close !== null)
        mouseClick(close)
        tryVerify(() => !banner.visible)
        compare(controller.error_message, "")
        controller.error_message = "Zweiter Fehler"
        tryVerify(() => banner.visible)
        compare(banner.text, "Zweiter Fehler")
        mouseClick(close)
        tryVerify(() => !banner.visible)
        controller.error_message = "Zweiter Fehler"
        tryVerify(() => banner.visible)
    }
}
