import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import io.github.jerry0205.klickmeister

Kirigami.ApplicationWindow {
    id: root

    property bool smokeTest: false
    property bool monitorSelectionReady: false
    property bool monitorRestored: false
    property var selectedMonitor: null
    property var positionPicker: null
    property int captureSequence: 0
    readonly property bool idle: !controller.running && !controller.busy
    readonly property bool fixedPosition: !controller.current_position
    readonly property var monitorOptions: {
        const screens = Qt.application.screens
        return Array.from(screens, screen => ({ screen: screen, label: monitors.displayName(screen, screens) }))
    }
    readonly property string rateText: {
        const interval = controller.interval_ms
        if (interval > 1000) {
            const seconds = interval / 1000
            if (seconds >= 3600) return qsTr("alle %1 h").arg(formatNumber(seconds / 3600))
            if (seconds >= 60) return qsTr("alle %1 min").arg(formatNumber(seconds / 60))
            return qsTr("alle %1 s").arg(formatNumber(seconds))
        }
        const rate = 1000 / interval
        if (controller.click_type === 1)
            return rate === 1 ? qsTr("1 Doppelklick/s") : qsTr("%1 Doppelklicks/s").arg(formatNumber(rate))
        return rate === 1 ? qsTr("1 Klick/s") : qsTr("%1 Klicks/s").arg(formatNumber(rate))
    }

    function formatNumber(value) {
        const rounded = Math.round(value * 10) / 10
        return rounded.toLocaleString(Qt.locale(), "f", Number.isInteger(rounded) ? 0 : 1)
    }

    function finishPicker(restoreHost) {
        if (positionPicker) positionPicker.finish(restoreHost)
    }

    function beginPicker(preview) {
        if (positionPicker || !selectedMonitor) return
        captureSequence += 1
        const picker = positionPickerComponent.createObject(root, {
            "screen": selectedMonitor, "captureId": captureSequence
        })
        if (!picker) return
        positionPicker = picker
        picker.begin(selectedMonitor, controller.fixed_x, controller.fixed_y, preview, magnifierOption.checked)
    }

    function confirmMonitor() {
        syncMonitor()
        controller.fixed_position_confirmed = !!selectedMonitor
    }

    function syncMonitor() {
        const screen = selectedMonitor
        if (!idle) controller.stop()
        controller.monitor_identity = screen ? monitors.identity(screen) : ""
        controller.monitor_x = screen ? screen.virtualX : 0
        controller.monitor_y = screen ? screen.virtualY : 0
        controller.monitor_width = screen ? screen.width : 0
        controller.monitor_height = screen ? screen.height : 0
        controller.fixed_x = Math.max(0, Math.min(controller.fixed_x, xInput.to))
        controller.fixed_y = Math.max(0, Math.min(controller.fixed_y, yInput.to))
        // The SpinBoxes clamped the saved values while the monitor size was still 0.
        xInput.value = controller.fixed_x
        yInput.value = controller.fixed_y
    }

    function monitorChanged(sizeChanged) {
        if (sizeChanged) controller.fixed_position_confirmed = false
        finishPicker()
        syncMonitor()
    }

    function ensureMonitorSelection() {
        if (!monitorSelectionReady) return

        const screens = Array.from(Qt.application.screens)
        if (!monitorRestored) {
            monitorRestored = true
            const restored = monitors.restoreIndex(screens, controller.monitor_identity)
            if (restored >= 0) {
                const screen = screens[restored]
                // Check before selecting: selection clamps the coordinates to the monitor.
                const valid = controller.fixed_x < screen.width && controller.fixed_y < screen.height
                selectedMonitor = screen
                monitorInput.currentIndex = restored
                controller.fixed_position_confirmed = valid
                return
            }
        }

        const current = screens.indexOf(selectedMonitor)
        if (current >= 0) {
            monitorInput.currentIndex = current
            return
        }

        controller.fixed_position_confirmed = false
        const fallback = Math.max(0, screens.indexOf(root.screen))
        selectedMonitor = screens.length > 0 ? screens[fallback] : null
        monitorInput.currentIndex = screens.length > 0 ? fallback : -1
    }

    onSelectedMonitorChanged: syncMonitor()
    onScreenChanged: ensureMonitorSelection()
    onClosing: function(close) {
        finishPicker(false)
        controller.shutdown()
        close.accepted = true
    }
    Component.onCompleted: {
        ensureMonitorSelection()
        if (!smokeTest) controller.initialize()
    }

    width: Kirigami.Units.gridUnit * 25
    height: Kirigami.Units.gridUnit * 23
    minimumWidth: Kirigami.Units.gridUnit * 20
    minimumHeight: Kirigami.Units.gridUnit * 16
    visible: true
    title: qsTr("Klickmeister %1").arg(Qt.application.version)

    MonitorSelection { id: monitors }

    AppController {
        id: controller
        objectName: "controller"
    }

    Component {
        id: positionPickerComponent
        PositionPicker {
            id: picker
            hostWindow: root
            onSelectingChanged: controller.selecting_position = selecting
            onScreenshotRequested: requestId => controller.capture_screenshot(requestId)
            onScreenshotCancelled: requestId => controller.cancel_screenshot(requestId)
            onPicked: function(x, y) {
                controller.fixed_x = x
                controller.fixed_y = y
                controller.current_position = false
                controller.fixed_position_confirmed = true
            }
            onFinished: {
                if (root.positionPicker === picker) root.positionPicker = null
                picker.destroy()
            }
        }
    }

    Connections {
        target: controller
        function onScreenshot_ready(requestId, uri, error) {
            if (root.positionPicker) root.positionPicker.acceptScreenshot(requestId, uri, error)
        }
        function onFixed_xChanged() { xInput.value = controller.fixed_x }
        function onFixed_yChanged() { yInput.value = controller.fixed_y }
    }

    Connections {
        target: Qt.application
        function onScreensChanged() {
            root.finishPicker()
            root.ensureMonitorSelection()
            root.syncMonitor()
        }
    }

    Connections {
        target: root.selectedMonitor
        function onWidthChanged() { root.monitorChanged(true) }
        function onHeightChanged() { root.monitorChanged(true) }
        function onDevicePixelRatioChanged() { root.monitorChanged(true) }
        function onVirtualXChanged() { root.monitorChanged(false) }
        function onVirtualYChanged() { root.monitorChanged(false) }
    }

    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.initialPage: Kirigami.ScrollablePage {
        header: Kirigami.InlineMessage {
            id: errorMessage
            objectName: "errorMessage"
            position: Kirigami.InlineMessage.Position.Header
            type: Kirigami.MessageType.Error
            text: controller.error_message
            visible: text.length > 0
            showCloseButton: true
            // The close button assigns visible = false; restore the binding for the next error.
            onVisibleChanged: if (!visible) {
                controller.clear_error()
                visible = Qt.binding(() => text.length > 0)
            }
        }

        footer: Controls.ToolBar {
            position: Controls.ToolBar.Footer
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Item {
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                    Controls.BusyIndicator {
                        anchors.fill: parent
                        padding: 0
                        running: controller.busy
                        visible: running
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        visible: !controller.busy
                        width: Kirigami.Units.smallSpacing * 2
                        height: width
                        radius: width / 2
                        color: controller.running ? Kirigami.Theme.positiveTextColor
                            : controller.error_message.length > 0 ? Kirigami.Theme.negativeTextColor
                            : Kirigami.Theme.disabledTextColor
                    }
                }

                Controls.Label {
                    objectName: "statusLabel"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: controller.running ? qsTr("%1 · %2").arg(controller.status).arg(root.rateText) : controller.status
                    Accessible.name: qsTr("Status: %1").arg(text)
                }

                Controls.ToolButton {
                    objectName: "hotkeyButton"
                    icon.name: "input-keyboard"
                    text: controller.hotkey || "–"
                    enabled: root.idle
                    onClicked: controller.configure_hotkey()
                    Controls.ToolTip.text: qsTr("Hotkey für Starten/Stoppen ändern")
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                    Accessible.name: qsTr("Hotkey %1 ändern").arg(text)
                }

                Controls.Button {
                    objectName: "startButton"
                    highlighted: true
                    text: root.idle ? qsTr("Starten") : qsTr("Stoppen")
                    icon.name: root.idle ? "media-playback-start" : "media-playback-stop"
                    onClicked: controller.toggle()
                    Controls.ToolTip.text: qsTr("Oder %1 drücken").arg(controller.hotkey)
                    Controls.ToolTip.visible: hovered && controller.hotkey.length > 0
                    Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }

        Kirigami.FormLayout {
            enabled: root.idle

            ChoiceButtons {
                objectName: "mouseButtonInput"
                Kirigami.FormData.label: qsTr("Maustaste:")
                iconOnly: true
                value: controller.mouse_button
                options: [
                    { value: 0, icon: "input-mouse-click-left", text: qsTr("Links") },
                    { value: 2, icon: "input-mouse-click-middle", text: qsTr("Mitte") },
                    { value: 1, icon: "input-mouse-click-right", text: qsTr("Rechts") }
                ]
                onSelected: choice => controller.mouse_button = choice
            }

            ChoiceButtons {
                objectName: "clickTypeInput"
                Kirigami.FormData.label: qsTr("Klick:")
                value: controller.click_type
                options: [
                    { value: 0, text: qsTr("1×"), description: qsTr("Einfach") },
                    { value: 1, text: qsTr("2×"), description: qsTr("Doppelt") }
                ]
                onSelected: choice => controller.click_type = choice
            }

            RowLayout {
                Kirigami.FormData.label: qsTr("Intervall:")
                Controls.SpinBox {
                    id: intervalInput
                    objectName: "intervalInput"
                    from: 10
                    to: 86400000
                    stepSize: 10
                    editable: true
                    value: controller.interval_ms
                    onValueModified: controller.interval_ms = value
                    textFromValue: value => value.toLocaleString(Qt.locale(), "f", 0)
                    valueFromText: text => Number.fromLocaleString(Qt.locale(), text)
                    Accessible.name: qsTr("Klickintervall in Millisekunden")
                }
                Controls.Label { text: qsTr("ms") }
                Controls.Label {
                    objectName: "rateLabel"
                    color: Kirigami.Theme.disabledTextColor
                    text: root.rateText
                }
            }

            RowLayout {
                Kirigami.FormData.label: qsTr("Wiederholen:")
                ChoiceButtons {
                    objectName: "repeatModeInput"
                    value: controller.repeat_until_stopped
                    options: [
                        { value: true, text: "∞", description: qsTr("Bis zum Stoppen") },
                        { value: false, text: qsTr("Anzahl") }
                    ]
                    onSelected: choice => controller.repeat_until_stopped = choice
                }
                Controls.SpinBox {
                    objectName: "repeatInput"
                    visible: !controller.repeat_until_stopped
                    from: 1
                    to: 10000000
                    editable: true
                    value: controller.repeat_count
                    onValueModified: controller.repeat_count = value
                    Accessible.name: qsTr("Anzahl der Klickzyklen")
                }
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
            }

            ChoiceButtons {
                objectName: "positionModeInput"
                Kirigami.FormData.label: qsTr("Ziel:")
                value: controller.current_position
                options: [
                    { value: true, icon: "cursor-arrow", text: qsTr("Mauszeiger"),
                      description: qsTr("Aktuelle Cursorposition") },
                    { value: false, icon: "crosshairs", text: qsTr("Fester Punkt"),
                      description: qsTr("Feste Position") }
                ]
                onSelected: choice => controller.current_position = choice
            }

            Controls.ComboBox {
                id: monitorInput
                objectName: "monitorInput"
                Kirigami.FormData.label: qsTr("Monitor:")
                Layout.fillWidth: true
                visible: root.fixedPosition
                model: root.monitorOptions
                textRole: "label"
                onModelChanged: Qt.callLater(root.ensureMonitorSelection)
                Component.onCompleted: {
                    root.monitorSelectionReady = true
                    root.ensureMonitorSelection()
                }
                onActivated: index => {
                    root.selectedMonitor = model[index].screen
                    root.confirmMonitor()
                }
                Accessible.name: qsTr("Monitor für die feste Position")
            }

            RowLayout {
                Kirigami.FormData.label: qsTr("Punkt:")
                visible: root.fixedPosition
                Controls.Label { text: "X" }
                Controls.SpinBox {
                    id: xInput
                    objectName: "xInput"
                    from: 0
                    to: Math.max(0, controller.monitor_width - 1)
                    editable: true
                    value: controller.fixed_x
                    onValueModified: controller.fixed_x = value
                    Accessible.name: qsTr("X-Koordinate auf dem Monitor")
                }
                Controls.Label { text: "Y" }
                Controls.SpinBox {
                    id: yInput
                    objectName: "yInput"
                    from: 0
                    to: Math.max(0, controller.monitor_height - 1)
                    editable: true
                    value: controller.fixed_y
                    onValueModified: controller.fixed_y = value
                    Accessible.name: qsTr("Y-Koordinate auf dem Monitor")
                }
            }

            RowLayout {
                visible: root.fixedPosition
                Controls.Button {
                    objectName: "pickButton"
                    icon.name: "crosshairs"
                    text: qsTr("Auswählen …")
                    enabled: !!root.selectedMonitor
                    onClicked: root.beginPicker(false)
                    Controls.ToolTip.text: qsTr("Punkt im Vollbild auf dem Monitor wählen")
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                Controls.ToolButton {
                    objectName: "previewButton"
                    icon.name: "view-visible"
                    text: qsTr("Punkt anzeigen")
                    display: Controls.AbstractButton.IconOnly
                    enabled: !!root.selectedMonitor && controller.fixed_position_confirmed
                    onClicked: root.beginPicker(true)
                    Controls.ToolTip.text: text
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                Controls.CheckBox {
                    id: magnifierOption
                    text: qsTr("4×-Lupe")
                    Controls.ToolTip.text: qsTr("Beim Auswählen ein Bildschirmfoto vergrößern. Im KDE-Dialog „Vollbild“ aufnehmen und speichern; ohne Bild geht es nach drei Sekunden ohne Lupe weiter.")
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            Kirigami.InlineMessage {
                objectName: "confirmMessage"
                Layout.fillWidth: true
                visible: root.fixedPosition && !controller.fixed_position_confirmed
                type: Kirigami.MessageType.Warning
                text: qsTr("Bitte Monitor und Punkt bestätigen oder neu auswählen.")
                actions: Kirigami.Action {
                    icon.name: "dialog-ok-apply"
                    text: qsTr("Bestätigen")
                    enabled: !!root.selectedMonitor
                    onTriggered: root.confirmMonitor()
                }
            }

            Controls.Label {
                Layout.fillWidth: true
                visible: root.fixedPosition
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                text: qsTr("Beim Start im KDE-Dialog denselben Monitor freigeben.")
            }
        }
    }
}
