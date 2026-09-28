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
            { tag: "interval", input: "intervalInput", property: "interval_ms", value: 250, position: false },
            { tag: "repeat", input: "repeatInput", property: "repeat_count", value: 42, position: false },
            { tag: "x", input: "xInput", property: "fixed_x", value: 123, position: true },
            { tag: "y", input: "yInput", property: "fixed_y", value: 234, position: true }
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
        compare(controller.positionDirty, data.position)
    }

    function test_monitor_initialization_does_not_replace_saved_position() {
        // Restoring the monitor at startup clamps and rewrites the displayed
        // position, but only user actions may replace the saved one.
        compare(controller.fixed_position_confirmed, false)
        compare(controller.configDirty, false)
        compare(controller.positionDirty, false)
    }

    function test_confirming_monitor_replaces_saved_position() {
        controller.current_position = false
        const confirm = findChild(main, "confirmMonitorButton")
        verify(confirm !== null)
        tryCompare(confirm, "visible", true)
        compare(confirm.enabled, true)
        // The button can lie below the scrollable page's visible area.
        confirm.clicked()
        compare(controller.fixed_position_confirmed, true)
        compare(controller.positionDirty, true)
    }

    function test_reselecting_saved_monitor_restores_saved_position() {
        controller.current_position = false
        // Simulate coordinates clamped to a substitute for the saved monitor.
        controller.savedMonitorIdentity = controller.monitor_identity
        controller.savedFixedX = 300
        controller.savedFixedY = 200
        controller.fixed_x = 10
        controller.fixed_y = 20
        const monitorInput = findChild(main, "monitorInput")
        monitorInput.activated(monitorInput.currentIndex)
        compare(controller.fixed_x, 300)
        compare(controller.fixed_y, 200)
        compare(findChild(main, "xInput").value, 300)
        compare(controller.fixed_position_confirmed, false)
        compare(controller.positionDirty, false)
        main.confirmMonitor()
        compare(controller.fixed_position_confirmed, true)
        compare(controller.positionDirty, true)

        // Restored coordinates are still clamped to the selected monitor.
        controller.fixed_position_confirmed = false
        controller.savedFixedX = 100000
        monitorInput.activated(monitorInput.currentIndex)
        compare(controller.fixed_x, findChild(main, "xInput").to)
        compare(controller.fixed_y, 200)
    }

    function test_explicit_monitor_selection_replaces_missing_saved_monitor() {
        controller.current_position = false
        controller.savedMonitorIdentity = "missing-monitor"
        controller.savedFixedX = 2400
        controller.savedFixedY = 1300
        controller.configDirty = false
        controller.positionDirty = false

        const screen = main.monitorOptions[0].screen
        main.selectMonitor(screen)

        compare(controller.fixed_position_confirmed, false)
        compare(controller.positionDirty, false)
        main.confirmMonitor()
        compare(controller.fixed_position_confirmed, true)
        compare(controller.configDirty, true)
        compare(controller.positionDirty, true)
        compare(controller.savedMonitorIdentity, controller.monitor_identity)
        compare(controller.savedFixedX, controller.fixed_x)
        compare(controller.savedFixedY, controller.fixed_y)
    }

    function test_selecting_smaller_monitor_requires_confirmation_after_clamping() {
        const smaller = Qt.createQmlObject('import QtQuick; QtObject {'
            + 'property string name: "smaller"; property string manufacturer: "";'
            + 'property string model: ""; property string serialNumber: "";'
            + 'property int width: 100; property int height: 100;'
            + 'property int virtualX: 0; property int virtualY: 0;'
            + 'property real devicePixelRatio: 1}', main)
        verify(smaller !== null)
        controller.current_position = false
        controller.fixed_x = 300
        controller.fixed_y = 200
        controller.fixed_position_confirmed = true

        main.selectMonitor(smaller)

        compare(controller.fixed_x, 99)
        compare(controller.fixed_y, 99)
        compare(controller.fixed_position_confirmed, false)
        compare(controller.positionDirty, false)
        compare(controller.savedMonitorIdentity, "")
    }

    function test_reselecting_saved_monitor_at_smaller_resolution_keeps_saved_coordinates() {
        const smaller = Qt.createQmlObject('import QtQuick; QtObject {'
            + 'property string name: "saved-monitor"; property string manufacturer: "";'
            + 'property string model: ""; property string serialNumber: "";'
            + 'property int width: 400; property int height: 300;'
            + 'property int virtualX: 0; property int virtualY: 0;'
            + 'property real devicePixelRatio: 1}', main)
        verify(smaller !== null)
        controller.current_position = false
        main.selectedMonitor = smaller
        controller.savedMonitorIdentity = controller.monitor_identity
        controller.savedFixedX = 300
        controller.savedFixedY = 200
        controller.fixed_x = 300
        controller.fixed_y = 200
        controller.fixed_position_confirmed = true
        smaller.width = 100
        smaller.height = 100
        compare(controller.fixed_position_confirmed, false)
        compare(controller.fixed_x, 99)
        compare(controller.fixed_y, 99)
        const savedIdentity = controller.savedMonitorIdentity
        main.selectMonitor(smaller)

        compare(controller.fixed_x, 99)
        compare(controller.fixed_y, 99)
        compare(controller.fixed_position_confirmed, false)
        compare(controller.positionDirty, false)
        compare(controller.savedFixedX, 300)
        compare(controller.savedFixedY, 200)
        compare(controller.savedMonitorIdentity, savedIdentity)
    }

    function test_mouse_wheel_cannot_replace_saved_position() {
        for (const name of ["xInput", "yInput", "monitorInput"])
            compare(findChild(main, name).wheelEnabled, false)
    }

    function test_save_error_dialog_keeps_choices_reachable() {
        controller.mark_settings_changed()
        controller.saveConfigSucceeds = false
        main.close()
        const dialog = findChild(main, "saveFailureDialog")
        tryCompare(dialog, "opened", true)
        for (const name of ["continueEditingButton", "discardSettingsButton"]) {
            const button = findChild(main, name)
            const right = button.mapToItem(dialog.contentItem, button.width, 0).x
            verify(right <= dialog.availableWidth, name + " ends at " + right)
        }
        const continueButton = findChild(main, "continueEditingButton")
        const discardButton = findChild(main, "discardSettingsButton")
        verify(discardButton.y >= continueButton.y + continueButton.height)
        // The header close button rejects the dialog.
        dialog.reject()
        tryCompare(dialog, "opened", false)
        compare(controller.initializeCount, 1)
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
        compare(controller.hotkey_ready, false)
        compare(controller.hotkey_pending, true)
        compare(findChild(main, "startStopButton").enabled, false)
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

    function test_save_error_restores_minimized_window() {
        controller.mark_settings_changed()
        controller.saveConfigSucceeds = false
        main.showMinimized()
        tryCompare(main, "visibility", Window.Minimized)
        main.close()
        tryCompare(main, "visibility", Window.Windowed)
        const dialog = findChild(main, "saveFailureDialog")
        tryCompare(dialog, "opened", true)
        const discard = findChild(main, "discardSettingsButton")
        mouseClick(discard)
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
        compare(controller.fixed_position_confirmed, false)
        main.confirmMonitor()
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
}
