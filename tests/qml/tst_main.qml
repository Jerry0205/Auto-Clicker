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

    function test_rate_and_status_distinguish_cycles_from_clicks() {
        const rateLabel = findChild(main, "rateLabel")
        const statusLabel = findChild(main, "statusLabel")
        verify(rateLabel !== null)
        verify(statusLabel !== null)
        const twoAndHalf = Number(2.5).toLocaleString(Qt.locale(), 'f', 1)
        const scenarios = [
            { interval: 10, type: 0, expected: "100 Zyklen/s · 100 Klicks/s" },
            { interval: 10, type: 1, expected: "100 Zyklen/s · 200 Klicks/s" },
            { interval: 1000, type: 0, expected: "1 Zyklus/s · 1 Klick/s" },
            { interval: 1000, type: 1, expected: "1 Zyklus/s · 2 Klicks/s" },
            { interval: 999, type: 0, expected: "1 Zyklus/s · 1 Klick/s" },
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
}
