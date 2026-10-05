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

    function test_edits_are_saved_on_close_without_click_start_data() {
        return [
            { tag: "mouse button", input: "mouseButtonInput", key: Qt.Key_Down, property: "mouse_button", value: 1 },
            { tag: "click type", input: "clickTypeInput", key: Qt.Key_Down, property: "click_type", value: 1 },
            { tag: "repeat mode", input: "repeatCountLabel", key: Qt.Key_Space, property: "repeat_until_stopped", value: false },
            { tag: "position mode", input: "fixedPositionInput", key: Qt.Key_Space, property: "current_position", value: false },
            // Start from the opposite state; clicking a checked radio changes nothing.
            { tag: "repeat until stopped", input: "repeatUntilStoppedInput", key: Qt.Key_Space, property: "repeat_until_stopped", initial: false, value: true },
            { tag: "cursor position", input: "currentPositionInput", key: Qt.Key_Space, property: "current_position", initial: false, value: true }
        ]
    }
    function test_edits_are_saved_on_close_without_click_start(data) {
        if (data.initial !== undefined) controller[data.property] = data.initial
        compare(controller.configDirty, false)
        const input = findChild(main, data.input)
        verify(input !== null)
        input.forceActiveFocus()
        keyClick(data.key)
        compare(controller[data.property], data.value)
        compare(controller.configDirty, true)
        main.close()
        compare(controller.saveCount, 1)
        compare(controller.configDirty, false)
        compare(controller.running, false)
        compare(controller.busy, false)
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
        compare(x.Accessible.name, "X-Koordinate auf dem gewählten Bildschirm")
        compare(y.Accessible.name, "Y-Koordinate auf dem gewählten Bildschirm")
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
            controller.status = "Klicken aktiv"
            controller.running = true
            compare(statusLabel.text, "Status: Klicken aktiv · " + scenario.expected)
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
        compare(status.text, "Dialog öffnet …")
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
            // A shown send error must not take away Stop, even without a hotkey.
            { tag: "running-hotkey-unavailable", fixed: false, running: true, busy: false, ready: false, pending: false },
            { tag: "hotkey-unavailable", fixed: false, running: false, busy: false, ready: false, pending: false },
            { tag: "hotkey-pending", fixed: false, running: false, busy: false, ready: false, pending: true }
        ]
    }

    function test_run_control_stays_visible_at_minimum_size(data) {
        main.width = main.minimumWidth
        main.height = main.minimumHeight
        controller.current_position = !data.fixed
        controller.fixed_position_confirmed = false
        // Keep scrolling necessary even with smaller CI fonts and icon themes.
        controller.error_message = Array(16).join("Ein Portalfehler mit zusätzlicher Beschreibung. ")
        controller.status = data.busy ? "Warte auf Freigabe für Maussteuerung …" : (data.running ? "Klicken aktiv" : "Bereit")
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
        tryCompare(findChild(main, "errorBanner"), "visible", true)
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
        compare(button.text, data.running || data.busy ? "■  Stoppen" : "▶  Starten")
        compare(button.Accessible.name, data.running || data.busy ? "Stoppen" : "Starten")
        const expectedStatus = "Status: " + controller.status
            + (data.running ? " · " + main.rateDescription : "")
        compare(status.text, expectedStatus)
        // A click at the button's position must reach it, not the settings.
        const enabled = button.enabled
        const stopMode = data.running || data.busy
        mouseClick(button)
        compare(controller.stops, enabled && stopMode ? 1 : 0)
        compare(controller.button_starts, enabled && !stopMode ? 1 : 0)
        // The mock's stop() ends the run at once; restore it for the second click.
        controller.busy = data.busy
        controller.running = data.running

        const flickable = main.pageStack.currentItem.flickable
        tryVerify(function() { return flickable.contentHeight > flickable.height },
                  1000, "Settings must remain scrollable")
        flickable.contentY = flickable.contentHeight - flickable.height
        wait(50)
        verify(button.visible && inWindow(button), "Scrolling settings must not move the run control")
        verify(status.visible && inWindow(status), "Scrolling settings must not move the run status")
        mouseClick(button)
        compare(controller.stops, enabled && stopMode ? 2 : 0)
        compare(controller.button_starts, enabled && !stopMode ? 2 : 0)
    }

    function test_run_control_can_be_used_with_keyboard() {
        const button = findChild(main, "startStopButton")
        verify(button.activeFocusOnTab)
        button.forceActiveFocus()
        verify(button.activeFocus)
        keyClick(Qt.Key_Space)
        compare(controller.button_starts, 1)
    }

    function test_run_control_follows_settings_in_focus_and_reading_order() {
        const lastSetting = findChild(main, "hotkeyConfigureButton")
        const button = findChild(main, "startStopButton")
        const footer = findChild(main, "runFooter")
        verify(lastSetting.enabled)
        lastSetting.forceActiveFocus(Qt.TabFocusReason)
        verify(lastSetting.activeFocus)
        keyClick(Qt.Key_Tab)
        verify(button.activeFocus, "Tab must move from the last setting to the run control")
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        verify(lastSetting.activeFocus, "Shift+Tab must return from the run control to the settings")

        // Screen readers list sibling items in child order, so the footer
        // must follow the settings page.
        let page = main.pageStack
        while (page && page.parent !== footer.parent) page = page.parent
        verify(page, "Footer and settings must share a parent item")
        const siblings = footer.parent.children
        verify(siblings.indexOf(page) < siblings.indexOf(footer),
               "The footer must follow the settings in reading order")
    }

    function test_button_shows_and_cancels_countdown() {
        const button = findChild(main, "startStopButton")
        verify(button !== null)
        controller.hotkey_ready = true
        controller.hotkey_pending = false
        compare(button.text, "▶  Starten")
        compare(button.Accessible.name, "Starten")
        mouseClick(button)
        compare(controller.button_starts, 1)
        compare(controller.stops, 0)

        // Waiting for the Wayland permission: pending, but no countdown yet.
        controller.busy = true
        compare(button.text, "■  Stoppen")
        compare(button.Accessible.name, "Stoppen")

        // The countdown stays cancellable even if the hotkey becomes unavailable.
        controller.countdown_remaining = 3
        compare(button.text, "■  Start abbrechen (3)")
        compare(button.Accessible.name, "Start abbrechen, Klicken beginnt in 3 Sekunden")
        controller.countdown_remaining = 1
        compare(button.text, "■  Start abbrechen (1)")
        compare(button.Accessible.name, "Start abbrechen, Klicken beginnt in 1 Sekunde")
        controller.hotkey_ready = false
        compare(button.enabled, true)
        mouseClick(button)
        compare(controller.stops, 1)
        compare(controller.countdown_remaining, 0)
        compare(controller.button_starts, 1)
        controller.hotkey_ready = true
        compare(button.text, "▶  Starten")
        compare(button.Accessible.name, "Starten")

        // A countdown value without a pending start is never shown.
        controller.countdown_remaining = 2
        compare(button.text, "▶  Starten")
        compare(button.Accessible.name, "Starten")
        controller.countdown_remaining = 0

        // A running click loop is stopped, never restarted with a countdown.
        controller.running = true
        compare(button.text, "■  Stoppen")
        mouseClick(button)
        compare(controller.stops, 2)
        compare(controller.button_starts, 1)
    }
}
