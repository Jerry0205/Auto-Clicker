import QtQuick

// QML-only fixture: portal and worker behavior is tested separately in Rust.
QtObject {
    property string status: "Bereit"
    property string error_message: ""
    property string hotkey: "Pause"
    property bool hotkey_ready: true
    property bool hotkey_pending: false
    property bool hotkey_configuring: false
    property bool running: false
    property bool busy: false
    property int countdown_remaining: 0
    property int button_starts: 0
    property int stops: 0
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
    function initialize() {}
    function shutdown() {}
    function start() {}
    function start_from_button() { button_starts += 1 }
    // Mirrors the worker's later State(Stopped), which also ends a countdown.
    function stop() { stops += 1; running = false; busy = false; countdown_remaining = 0 }
    function toggle() {}
    function configure_hotkey() {}
    function clear_error() { error_message = "" }
}
