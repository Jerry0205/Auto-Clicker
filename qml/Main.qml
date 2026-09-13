import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import io.github.jerry0205.klickmeister

Kirigami.ApplicationWindow {
    id: root

    property bool smokeTest: false
    property bool monitorSelectionReady: false
    property var selectedMonitor: null
    property var positionPicker: null
    property int captureSequence: 0
    property bool monitorRestored: false
    readonly property var monitorOptions: {
        const screens = Qt.application.screens
        const options = []
        for (let i = 0; i < screens.length; ++i) {
            options.push({ screen: screens[i], label: monitors.displayName(screens[i], screens) })
        }
        return options
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
        if (controller.running || controller.busy) controller.stop()
        controller.monitor_identity = screen ? monitors.identity(screen) : ""
        controller.monitor_x = screen ? screen.virtualX : 0
        controller.monitor_y = screen ? screen.virtualY : 0
        controller.monitor_width = screen ? screen.width : 0
        controller.monitor_height = screen ? screen.height : 0
        controller.fixed_x = Math.max(0, Math.min(controller.fixed_x, xInput.to))
        controller.fixed_y = Math.max(0, Math.min(controller.fixed_y, yInput.to))
    }

    onSelectedMonitorChanged: syncMonitor()

    function ensureMonitorSelection() {
        if (!monitorSelectionReady) {
            return
        }

        const screens = Qt.application.screens
        if (!monitorRestored) {
            monitorRestored = true
            const restored = monitors.restoreIndex(screens, controller.monitor_identity)
            if (restored >= 0) {
                const screen = screens[restored]
                const valid = controller.fixed_x < screen.width && controller.fixed_y < screen.height
                selectedMonitor = screen
                monitorInput.currentIndex = restored
                controller.fixed_position_confirmed = valid
                return
            }
        }
        for (let index = 0; index < screens.length; ++index) {
            if (screens[index] === selectedMonitor) {
                monitorInput.currentIndex = index
                return
            }
        }

        controller.fixed_position_confirmed = false
        for (let index = 0; index < screens.length; ++index) {
            if (screens[index] === root.screen) {
                selectedMonitor = screens[index]
                monitorInput.currentIndex = index
                return
            }
        }

        selectedMonitor = screens.length > 0 ? screens[0] : null
        monitorInput.currentIndex = screens.length > 0 ? 0 : -1
    }

    width: 520
    height: 720
    minimumWidth: 460
    minimumHeight: 620
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
            onScreenshotRequested: function(requestId) { controller.capture_screenshot(requestId) }
            onScreenshotCancelled: function(requestId) { controller.cancel_screenshot(requestId) }
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

        function onScreenshot_ready(requestId, uri, error) { if (positionPicker) positionPicker.acceptScreenshot(requestId, uri, error) }
        function onFixed_xChanged() { xInput.value = controller.fixed_x }
        function onFixed_yChanged() { yInput.value = controller.fixed_y }
    }

    Component.onCompleted: {
        ensureMonitorSelection()
        if (!smokeTest) {
            controller.initialize()
        }
    }
    onScreenChanged: ensureMonitorSelection()
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
        function onWidthChanged() { controller.fixed_position_confirmed = false; root.finishPicker(); root.syncMonitor() }
        function onHeightChanged() { controller.fixed_position_confirmed = false; root.finishPicker(); root.syncMonitor() }
        function onDevicePixelRatioChanged() { controller.fixed_position_confirmed = false; root.finishPicker(); root.syncMonitor() }
        function onVirtualXChanged() { root.finishPicker(); root.syncMonitor() }
        function onVirtualYChanged() { root.finishPicker(); root.syncMonitor() }
    }
    onClosing: function(close) {
        root.finishPicker(false)
        controller.shutdown()
        close.accepted = true
    }

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: qsTr("Auto Clicker")

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: controller.error_message.length > 0
                type: Kirigami.MessageType.Error
                text: controller.error_message
                showCloseButton: true
                onLinkActivated: controller.clear_error()
                onVisibleChanged: if (!visible) controller.clear_error()
            }

            Controls.GroupBox {
                Layout.fillWidth: true
                title: qsTr("Intervall")

                RowLayout {
                    anchors.fill: parent
                    Controls.SpinBox {
                        id: intervalInput
                        objectName: "intervalInput"
                        Layout.fillWidth: true
                        from: 10
                        to: 86400000
                        stepSize: 10
                        editable: true
                        value: controller.interval_ms
                        enabled: !controller.running && !controller.busy
                        onValueModified: controller.interval_ms = value
                        textFromValue: function(value) { return value.toLocaleString(Qt.locale(), 'f', 0) }
                        valueFromText: function(text) {
                            return Number.fromLocaleString(Qt.locale(), text)
                        }
                        Accessible.name: qsTr("Klickintervall in Millisekunden")
                    }
                    Controls.Label {
                        text: qsTr("ms")
                    }
                    Controls.Label {
                        color: Kirigami.Theme.disabledTextColor
                        text: qsTr("%1 CPS").arg((1000 / intervalInput.value).toFixed(1))
                    }
                }
            }

            Controls.GroupBox {
                Layout.fillWidth: true
                title: qsTr("Klick")

                RowLayout {
                    anchors.fill: parent
                    Controls.ComboBox {
                        Layout.fillWidth: true
                        model: [qsTr("Links"), qsTr("Rechts"), qsTr("Mitte")]
                        currentIndex: controller.mouse_button
                        enabled: !controller.running && !controller.busy
                        onActivated: controller.mouse_button = currentIndex
                        Accessible.name: qsTr("Maustaste")
                    }
                    Controls.ComboBox {
                        Layout.fillWidth: true
                        model: [qsTr("Einfach"), qsTr("Doppelt")]
                        currentIndex: controller.click_type
                        enabled: !controller.running && !controller.busy
                        onActivated: controller.click_type = currentIndex
                        Accessible.name: qsTr("Klicktyp")
                    }
                }
            }

            Controls.GroupBox {
                Layout.fillWidth: true
                title: qsTr("Wiederholen")

                ColumnLayout {
                    anchors.fill: parent
                    Controls.RadioButton {
                        text: qsTr("Bis zum Stoppen")
                        checked: controller.repeat_until_stopped
                        enabled: !controller.running && !controller.busy
                        onToggled: if (checked) controller.repeat_until_stopped = true
                    }
                    RowLayout {
                        Controls.RadioButton {
                            text: qsTr("Anzahl")
                            checked: !controller.repeat_until_stopped
                            enabled: !controller.running && !controller.busy
                            onToggled: if (checked) controller.repeat_until_stopped = false
                        }
                        Controls.SpinBox {
                            objectName: "repeatInput"
                            Layout.fillWidth: true
                            from: 1
                            to: 10000000
                            editable: true
                            value: controller.repeat_count
                            enabled: !controller.repeat_until_stopped && !controller.running && !controller.busy
                            onValueModified: controller.repeat_count = value
                            Accessible.name: qsTr("Anzahl der Klickzyklen")
                        }
                    }
                }
            }

            Controls.GroupBox {
                Layout.fillWidth: true
                title: qsTr("Position")

                ColumnLayout {
                    anchors.fill: parent
                    Controls.RadioButton {
                        text: qsTr("Aktuelle Cursorposition")
                        checked: controller.current_position
                        enabled: !controller.running && !controller.busy
                        onToggled: if (checked) controller.current_position = true
                    }
                    Controls.RadioButton {
                        text: qsTr("Feste Position")
                        checked: !controller.current_position
                        enabled: !controller.running && !controller.busy
                        onToggled: if (checked) controller.current_position = false
                    }
                    RowLayout {
                        enabled: !controller.current_position && !controller.running && !controller.busy
                        Controls.Label { text: qsTr("X") }
                        Controls.SpinBox {
                            id: xInput
                            objectName: "xInput"
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(0, controller.monitor_width - 1)
                            editable: true
                            value: controller.fixed_x
                            onValueModified: controller.fixed_x = value
                        }
                        Controls.Label { text: qsTr("Y") }
                        Controls.SpinBox {
                            id: yInput
                            objectName: "yInput"
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(0, controller.monitor_height - 1)
                            editable: true
                            value: controller.fixed_y
                            onValueModified: controller.fixed_y = value
                        }
                    }
                    RowLayout {
                        enabled: !controller.current_position && !controller.running && !controller.busy
                        Controls.Label { text: qsTr("Monitor") }
                        Controls.ComboBox {
                            id: monitorInput
                            objectName: "monitorInput"
                            Layout.fillWidth: true
                            model: root.monitorOptions
                            textRole: "label"
                            onModelChanged: Qt.callLater(root.ensureMonitorSelection)
                            Component.onCompleted: {
                                root.monitorSelectionReady = true
                                root.ensureMonitorSelection()
                            }
                            onActivated: { root.selectedMonitor = model[currentIndex].screen; root.confirmMonitor() }
                            Accessible.name: qsTr("Monitor für die feste Position")
                        }
                    }
                    Controls.Button {
                        Layout.fillWidth: true
                        enabled: !controller.current_position && !controller.running && !controller.busy
                        text: qsTr("Position wählen / Neu wählen …")
                        icon.name: "crosshairs"
                        onClicked: root.beginPicker(false)
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        visible: !controller.current_position && !controller.fixed_position_confirmed
                        text: qsTr("Gespeicherte Position nicht zugeordnet. Bitte Monitor bestätigen oder eine neue Position wählen.")
                        wrapMode: Text.WordWrap
                    }
                    Controls.Button {
                        visible: !controller.current_position && !controller.fixed_position_confirmed
                        enabled: !!root.selectedMonitor && !controller.running && !controller.busy
                        text: qsTr("Monitor und Koordinaten bestätigen")
                        onClicked: root.confirmMonitor()
                    }
                    Controls.CheckBox {
                        id: magnifierOption
                        visible: !controller.current_position
                        enabled: !controller.running && !controller.busy
                        text: qsTr("Mit 4×-Lupe auswählen (Bildschirmaufnahme)")
                        Controls.ToolTip.visible: hovered
                        Controls.ToolTip.text: qsTr("Die Auswahl verwendet ein Standbild. Die Bildschirmaufnahme kann eine zusätzliche Freigabe erfordern.")
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        visible: !controller.current_position
                        text: qsTr("%1 · X: %2 · Y: %3")
                            .arg(monitors.displayName(root.selectedMonitor, Qt.application.screens))
                            .arg(controller.fixed_x).arg(controller.fixed_y)
                        wrapMode: Text.WordWrap
                    }
                    Controls.Button {
                        visible: !controller.current_position
                        enabled: !!root.selectedMonitor && controller.fixed_position_confirmed && !controller.running && !controller.busy
                        text: qsTr("Position anzeigen")
                        icon.name: "view-preview"
                        onClicked: root.beginPicker(true)
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        visible: !controller.current_position
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.disabledTextColor
                        text: qsTr("Koordinaten gelten innerhalb dieses monitors. Wähle beim Start im KWin-Dialog denselben Monitor; die Freigabe wird vor dem Klicken geprüft.")
                    }
                }
            }

            Controls.GroupBox {
                Layout.fillWidth: true
                title: qsTr("Globaler Hotkey")

                RowLayout {
                    anchors.fill: parent
                    Controls.Label {
                        text: qsTr("Start / Stop")
                    }
                    Item { Layout.fillWidth: true }
                    Controls.Label {
                        text: controller.hotkey
                        font.bold: true
                    }
                    Controls.Button {
                        text: qsTr("Ändern …")
                        enabled: !controller.busy && !controller.running
                        onClicked: controller.configure_hotkey()
                    }
                }
            }

            Controls.Button {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.6
                highlighted: true
                text: controller.running || controller.busy ? qsTr("■  Stoppen") : qsTr("▶  Starten")
                onClicked: controller.toggle()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    implicitWidth: Kirigami.Units.smallSpacing
                    implicitHeight: implicitWidth
                    radius: implicitWidth / 2
                    color: controller.running ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                }
                Controls.Label {
                    text: qsTr("Status: %1").arg(controller.status)
                }
                Item { Layout.fillWidth: true }
                Controls.BusyIndicator {
                    visible: controller.busy
                    running: visible
                    implicitWidth: Kirigami.Units.gridUnit
                    implicitHeight: implicitWidth
                }
            }

            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                color: Kirigami.Theme.disabledTextColor
                text: qsTr("Klickmeister %1").arg(Qt.application.version)
                Accessible.name: qsTr("Installierte Version %1").arg(Qt.application.version)
            }
        }
    }
}
