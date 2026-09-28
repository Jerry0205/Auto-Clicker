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
    property bool configDirty: false
    property bool positionDirty: false
    property string savedMonitorIdentity: ""
    property double savedFixedX: 0
    property double savedFixedY: 0
    property int saveCount: 0
    property int shutdownCount: 0
    property int initializeCount: 0
    function initialize() {
        initializeCount++
        hotkey_ready = false
        hotkey_pending = true
        hotkey_configuring = false
    }
    function shutdown() {
        shutdownCount++
        running = false
        busy = false
        hotkey_ready = false
        hotkey_pending = false
        hotkey_configuring = false
    }
    function mark_settings_changed() { configDirty = true }
    function mark_position_changed() {
        configDirty = true
        positionDirty = true
        savedMonitorIdentity = fixed_position_confirmed ? monitor_identity : ""
        savedFixedX = fixed_x
        savedFixedY = fixed_y
    }
    function restore_saved_position() {
        if (fixed_position_confirmed || !savedMonitorIdentity || savedMonitorIdentity !== monitor_identity) return
        fixed_x = savedFixedX
        fixed_y = savedFixedY
    }
    function save_config() {
        if (!configDirty) return true
        saveCount++
        if (!saveConfigSucceeds) error_message = "Konfiguration konnte nicht gespeichert werden"
        else configDirty = false
        return saveConfigSucceeds
    }
    function start() {}
    function stop() { running = false; busy = false }
    function toggle() {}
    function configure_hotkey() {}
    function clear_error() { error_message = "" }
}
