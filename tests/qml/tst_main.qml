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

    function test_rate_and_status_distinguish_cycles_from_clicks() {
        const rateLabel = findChild(main, "rateLabel")
        const statusLabel = findChild(main, "statusLabel")
        verify(rateLabel !== null)
        verify(statusLabel !== null)
        const twoAndHalf = Number(2.5).toLocaleString(Qt.locale(), 'f', 1)
        const nearOneCycle = Number(1.001).toLocaleString(Qt.locale(), 'f', 3)
        const nearTwoClicks = Number(2.002).toLocaleString(Qt.locale(), 'f', 3)
        const scenarios = [
            { interval: 10, type: 0, expected: "100 Zyklen/s · 100 Klicks/s" },
            { interval: 10, type: 1, expected: "100 Zyklen/s · 200 Klicks/s" },
            { interval: 1000, type: 0, expected: "1 Zyklus/s · 1 Klick/s" },
            { interval: 1000, type: 1, expected: "1 Zyklus/s · 2 Klicks/s" },
            { interval: 999, type: 0, expected: nearOneCycle + " Zyklen/s · " + nearOneCycle + " Klicks/s" },
            { interval: 999, type: 1, expected: nearOneCycle + " Zyklen/s · " + nearTwoClicks + " Klicks/s" },
            { interval: 5000, type: 0, expected: "1 Zyklus alle 5 s · 1 Klick alle 5 s" },
            { interval: 5000, type: 1, expected: "1 Zyklus alle 5 s · 2 Klicks alle 5 s" },
            { interval: 2500, type: 1, expected: "1 Zyklus alle " + twoAndHalf + " s · 2 Klicks alle " + twoAndHalf + " s" }
        ]
        for (const scenario of scenarios) {
            controller.interval_ms = scenario.interval
            controller.click_type = scenario.type
            tryCompare(rateLabel, "text", scenario.expected)
            controller.status = "Klickt"
            controller.running = true
            compare(statusLabel.text, "Status: Klickt · " + scenario.expected)
            controller.running = false
        }
    }

    function test_repeat_count_is_labeled_as_cycles() {
        compare(findChild(main, "repeatCountLabel").text, "Klickzyklen")
    }

    function test_hotkey_recovery_controls() {
        const retry = findChild(main, "hotkeyConfigureButton")
        const start = findChild(main, "startStopButton")
        const status = findChild(main, "hotkeyStatusLabel")
        verify(retry !== null)
        verify(start !== null)
        verify(status !== null)

        controller.hotkey_ready = false
        controller.hotkey_pending = false
        compare(retry.text, "Erneut versuchen")
        compare(status.text, "Nicht verfügbar")
        compare(retry.enabled, true)
        compare(start.enabled, false)

        controller.hotkey_pending = true
        compare(status.text, "Wird eingerichtet …")
        compare(retry.enabled, false)
        compare(start.enabled, false)

        controller.hotkey_ready = true
        controller.hotkey_configuring = true
        compare(status.text, "Öffnet Dialog …")
        compare(retry.enabled, false)
        compare(start.enabled, false)

        controller.hotkey_pending = false
        controller.hotkey_configuring = false
        compare(status.text, "Pause")
        compare(retry.text, "Ändern …")
        compare(retry.enabled, true)
        compare(start.enabled, true)
    }

    function test_run_control_stays_visible_at_minimum_size_data() {
        return [
            { tag: "cursor-ready", fixed: false, running: false, busy: false, ready: true, pending: false },
            { tag: "fixed-ready", fixed: true, running: false, busy: false, ready: true, pending: false },
            { tag: "cursor-running", fixed: false, running: true, busy: false, ready: true, pending: false },
            { tag: "fixed-running", fixed: true, running: true, busy: false, ready: true, pending: false },
            { tag: "cursor-starting", fixed: false, running: false, busy: true, ready: false, pending: true },
            { tag: "fixed-starting", fixed: true, running: false, busy: true, ready: false, pending: true },
            { tag: "hotkey-unavailable", fixed: false, running: false, busy: false, ready: false, pending: false },
            { tag: "hotkey-pending", fixed: false, running: false, busy: false, ready: false, pending: true }
        ]
    }

    function test_run_control_stays_visible_at_minimum_size(data) {
        main.width = main.minimumWidth
        main.height = main.minimumHeight
        controller.current_position = !data.fixed
        controller.fixed_position_confirmed = false
        controller.error_message = "Ein Portalfehler mit zusätzlicher Beschreibung"
        controller.status = data.busy ? "Warte auf Wayland-Berechtigung …" : (data.running ? "Klickt" : "Bereit")
        controller.hotkey_ready = data.ready
        controller.hotkey_pending = data.pending
        controller.busy = data.busy
        controller.running = data.running

        const footer = findChild(main, "runFooter")
        const button = findChild(main, "startStopButton")
        const status = findChild(main, "statusLabel")
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
        verify(button.visible && inWindow(button), "Run control must remain in the window")
        verify(status.visible && inWindow(status), "Run status must remain in the window")
        compare(button.enabled, data.running || data.busy || (data.ready && !data.pending))
        compare(button.Accessible.name, data.running || data.busy ? "Stoppen" : "Starten")
        const expectedStatus = "Status: " + controller.status
            + (data.running ? " · " + main.rateDescription : "")
        compare(status.text, expectedStatus)

        const flickable = main.pageStack.currentItem.flickable
        verify(flickable.contentHeight > flickable.height, "Settings must remain scrollable")
        flickable.contentY = flickable.contentHeight - flickable.height
        wait(50)
        verify(button.visible && inWindow(button), "Scrolling settings must not move the run control")
        verify(status.visible && inWindow(status), "Scrolling settings must not move the run status")
    }

    function test_run_control_can_be_used_with_keyboard() {
        const button = findChild(main, "startStopButton")
        verify(button.activeFocusOnTab)
        button.forceActiveFocus()
        verify(button.activeFocus)
        keyClick(Qt.Key_Space)
        compare(controller.toggle_count, 1)
    }
}
