import QtQuick

// QML-only fixture: portal and worker behavior is tested separately in Rust.
QtObject {
    property string status: "Bereit"
    property string error_message: ""
    property string hotkey: "Pause"
    property bool running: false
    property bool busy: false
    property double interval_ms: 100
    property int mouse_button: 0
    property int click_type: 0
    property bool repeat_until_stopped: true
    property double repeat_count: 100
    property bool current_position: true
    // Nonzero saved coordinates expose initialization/clamping regressions.
    property double fixed_x: 80
    property double fixed_y: 150
    property string monitor_identity: ""
    property bool fixed_position_confirmed: false
    property int monitor_x: 0
    property int monitor_y: 0
    property int monitor_width: 0
    property int monitor_height: 0
    property bool selecting_position: false
    property bool saveConfigSucceeds: true
    property int saveCount: 0
    property int shutdownCount: 0
    signal screenshot_ready(int requestId, string uri, string error)
    function initialize() {}
    function shutdown() { shutdownCount++ }
    function save_config() {
        saveCount++
        if (!saveConfigSucceeds) error_message = "Konfiguration konnte nicht gespeichert werden"
        return saveConfigSucceeds
    }
    function start() {}
    function stop() { running = false; busy = false }
    function toggle() {}
    function configure_hotkey() {}
    function clear_error() { error_message = "" }
    function capture_screenshot(requestId) {}
    function cancel_screenshot(requestId) {}
}
