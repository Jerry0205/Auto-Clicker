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
    property bool monitorRestored: false
    property bool monitorSelectionInProgress: false
    property bool discardSettingsOnClose: false
    readonly property var monitorOptions: {
        const screens = Qt.application.screens
        const options = []
        for (let i = 0; i < screens.length; ++i) {
            options.push({ screen: screens[i], label: monitors.displayName(screens[i], screens) })
        }
        return options
    }
    readonly property string rateDescription: describeRate(intervalInput.value, controller.click_type)

    function formatRateNumber(value, decimalPlaces) {
        return value.toLocaleString(Qt.locale(), 'f', decimalPlaces)
            .replace(/([,.]\d*?)0+$/, "$1")
            .replace(/[,.]$/, "")
    }

    function describeRate(intervalMs, clickType) {
        const clicksPerCycle = clickType === 1 ? 2 : 1
        if (intervalMs <= 1000) {
            const cyclesPerSecond = 1000 / intervalMs
            // Three places distinguish every whole-millisecond interval below
            // one second from an exact rate of one cycle per second.
            const cycleRate = Number(cyclesPerSecond.toFixed(3))
            const clickRate = Number((cyclesPerSecond * clicksPerCycle).toFixed(3))
            const cycleUnit = cycleRate === 1 ? qsTr("Zyklus/s") : qsTr("Zyklen/s")
            const clickUnit = clickRate === 1 ? qsTr("Klick/s") : qsTr("Klicks/s")
            return qsTr("%1 %2 · %3 %4")
                .arg(formatRateNumber(cycleRate, 3)).arg(cycleUnit)
                .arg(formatRateNumber(clickRate, 3)).arg(clickUnit)
        }
        const seconds = formatRateNumber(intervalMs / 1000, 3)
        const clicks = clicksPerCycle === 1 ? qsTr("1 Klick") : qsTr("2 Klicks")
        return qsTr("1 Zyklus alle %1 s · %2 alle %1 s").arg(seconds).arg(clicks)
    }

    function finishPicker(restoreHost) {
        if (positionPicker) positionPicker.finish(restoreHost)
    }

    function beginPicker(preview) {
        if (positionPicker || !selectedMonitor) return
        const picker = positionPickerComponent.createObject(root, { "screen": selectedMonitor })
        if (!picker) return
        positionPicker = picker
        picker.begin(selectedMonitor, controller.fixed_x, controller.fixed_y, preview)
    }

    function confirmMonitor() {
        syncMonitor()
        controller.fixed_position_confirmed = !!selectedMonitor
        controller.mark_position_changed()
    }

    // Coordinates clamped to a smaller monitor were never chosen by the user.
    function selectMonitor(screen) {
        const sameSelection = screen === selectedMonitor
        const wasConfirmed = controller.fixed_position_confirmed
        monitorSelectionInProgress = true
        selectedMonitor = screen
        monitorSelectionInProgress = false
        const fits = syncMonitor()
        // Reselecting an unconfirmed screen must not accept coordinates that
        // an earlier geometry change already clamped on that same screen.
        const confirmed = fits && (!sameSelection || wasConfirmed)
        controller.fixed_position_confirmed = confirmed
        // Clamping to a smaller monitor is not a chosen position. Keep the
        // saved coordinates until the user confirms or edits the displayed ones.
        if (confirmed && !sameSelection) controller.mark_position_changed()
    }

    function syncMonitor() {
        const screen = selectedMonitor
        const identity = screen ? monitors.identity(screen) : ""
        const x = screen ? screen.virtualX : 0
        const y = screen ? screen.virtualY : 0
        const width = screen ? screen.width : 0
        const height = screen ? screen.height : 0
        const moved = identity !== controller.monitor_identity
            || x !== controller.monitor_x || y !== controller.monitor_y
            || width !== controller.monitor_width || height !== controller.monitor_height
        // Cursor-position runs never use the selected monitor.
        if ((controller.running || controller.busy) && !controller.current_position
                && (moved || !controller.fixed_position_confirmed)) {
            controller.stop()
            monitorStopMessage.visible = true
        }
        controller.monitor_identity = identity
        controller.monitor_x = x
        controller.monitor_y = y
        controller.monitor_width = width
        controller.monitor_height = height
        // Reselecting the saved monitor shows its saved position before clamping.
        controller.restore_saved_position()
        const fits = !!screen && controller.fixed_x < width && controller.fixed_y < height
        controller.fixed_x = Math.max(0, Math.min(controller.fixed_x, xInput.to))
        controller.fixed_y = Math.max(0, Math.min(controller.fixed_y, yInput.to))
        // SpinBox initially clamps saved coordinates to its zero-sized monitor.
        // Restore the display even when the controller's coordinate is unchanged.
        xInput.value = controller.fixed_x
        yInput.value = controller.fixed_y
        return fits
    }

    onSelectedMonitorChanged: if (!monitorSelectionInProgress) syncMonitor()

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
            onPicked: function(x, y) {
                controller.fixed_x = x
                controller.fixed_y = y
                controller.current_position = false
                controller.fixed_position_confirmed = true
                controller.mark_position_changed()
            }
            onFinished: {
                if (root.positionPicker === picker) root.positionPicker = null
                picker.destroy()
            }
        }
    }

    Connections {
        target: controller

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
    function handleScreensChanged() {
        finishPicker()
        ensureMonitorSelection()
        syncMonitor()
    }
    Connections {
        target: Qt.application
        function onScreensChanged() { root.handleScreensChanged() }
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
        if (!root.discardSettingsOnClose && !controller.save_config()) {
            close.accepted = false
            if (root.visibility === Window.Minimized || root.visibility === Window.Hidden)
                root.showNormal()
            root.raise()
            root.requestActivate()
            saveFailureDialog.open()
            return
        }
        close.accepted = true
    }

    Controls.Dialog {
        id: saveFailureDialog
        objectName: "saveFailureDialog"
        modal: true
        closePolicy: Controls.Popup.NoAutoClose
        title: qsTr("Einstellungen konnten nicht gespeichert werden")
        width: Math.min(root.width - 32, 440)
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        // The header's close button rejects the dialog; treat it as continuing.
        onRejected: controller.initialize()

        ColumnLayout {
            width: saveFailureDialog.availableWidth
            Controls.Label {
                Layout.fillWidth: true
                text: controller.error_message
                wrapMode: Text.WordWrap
            }
            Controls.Label {
                Layout.fillWidth: true
                text: qsTr("„Weiter bearbeiten“ startet den Hintergrunddienst neu. KDE kann deshalb beim nächsten Start erneut nach der Wayland-Freigabe fragen.")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
            }
            ColumnLayout {
                Layout.fillWidth: true
                Controls.Button {
                    objectName: "continueEditingButton"
                    Layout.fillWidth: true
                    text: qsTr("Weiter bearbeiten")
                    onClicked: {
                        saveFailureDialog.close()
                        controller.initialize()
                    }
                }
                Controls.Button {
                    objectName: "discardSettingsButton"
                    Layout.fillWidth: true
                    text: qsTr("Ohne Speichern schließen")
                    onClicked: {
                        saveFailureDialog.close()
                        root.discardSettingsOnClose = true
                        root.close()
                    }
                }
            }
        }
    }

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: qsTr("Auto Clicker")

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                id: errorBanner
                objectName: "errorBanner"
                Layout.fillWidth: true
                visible: false
                type: Kirigami.MessageType.Error
                text: controller.error_message
                showCloseButton: true
                onLinkActivated: controller.clear_error()
                onVisibleChanged: if (!visible) controller.clear_error()
                Component.onCompleted: visible = controller.error_message.length > 0
            }

            Connections {
                target: controller
                function onError_messageChanged() {
                    errorBanner.visible = controller.error_message.length > 0
                }
                function onRunningChanged() { if (controller.running) monitorStopMessage.visible = false }
                function onBusyChanged() { if (controller.busy) monitorStopMessage.visible = false }
            }

            Kirigami.InlineMessage {
                id: monitorStopMessage
                objectName: "monitorStopMessage"
                Layout.fillWidth: true
                visible: false
                type: Kirigami.MessageType.Warning
                text: qsTr("Klicken wurde gestoppt, weil sich der Monitor der festen Position geändert hat. Bitte Position prüfen und neu starten.")
                showCloseButton: true
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
                        onValueModified: { controller.interval_ms = value; controller.mark_settings_changed() }
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
                        id: rateLabel
                        objectName: "rateLabel"
                        color: Kirigami.Theme.disabledTextColor
                        text: root.rateDescription
                        wrapMode: Text.WordWrap
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
                        onActivated: { controller.mouse_button = currentIndex; controller.mark_settings_changed() }
                        Accessible.name: qsTr("Maustaste")
                    }
                    Controls.ComboBox {
                        Layout.fillWidth: true
                        model: [qsTr("Einfach"), qsTr("Doppelt")]
                        currentIndex: controller.click_type
                        enabled: !controller.running && !controller.busy
                        onActivated: { controller.click_type = currentIndex; controller.mark_settings_changed() }
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
                        onClicked: controller.mark_settings_changed()
                    }
                    RowLayout {
                        Controls.RadioButton {
                            objectName: "repeatCountLabel"
                            text: qsTr("Klickzyklen")
                            checked: !controller.repeat_until_stopped
                            enabled: !controller.running && !controller.busy
                            onToggled: if (checked) controller.repeat_until_stopped = false
                            onClicked: controller.mark_settings_changed()
                        }
                        Controls.SpinBox {
                            objectName: "repeatInput"
                            Layout.fillWidth: true
                            from: 1
                            to: 10000000
                            editable: true
                            value: controller.repeat_count
                            enabled: !controller.repeat_until_stopped && !controller.running && !controller.busy
                            onValueModified: { controller.repeat_count = value; controller.mark_settings_changed() }
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
                        onClicked: controller.mark_settings_changed()
                    }
                    Controls.RadioButton {
                        text: qsTr("Feste Position")
                        checked: !controller.current_position
                        enabled: !controller.running && !controller.busy
                        onToggled: if (checked) controller.current_position = false
                        onClicked: controller.mark_settings_changed()
                    }
                    RowLayout {
                        enabled: !controller.current_position && !controller.running && !controller.busy
                        Controls.Label { text: qsTr("X") }
                        Controls.SpinBox {
                            id: xInput
                            objectName: "xInput"
                            Accessible.name: qsTr("X-Koordinate auf dem gewählten Monitor")
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(0, controller.monitor_width - 1)
                            editable: true
                            wheelEnabled: false
                            value: controller.fixed_x
                            onValueModified: { controller.fixed_x = value; controller.mark_position_changed() }
                        }
                        Controls.Label { text: qsTr("Y") }
                        Controls.SpinBox {
                            id: yInput
                            objectName: "yInput"
                            Accessible.name: qsTr("Y-Koordinate auf dem gewählten Monitor")
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(0, controller.monitor_height - 1)
                            editable: true
                            wheelEnabled: false
                            value: controller.fixed_y
                            onValueModified: { controller.fixed_y = value; controller.mark_position_changed() }
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
                            // Scrolling the page must not replace the saved position.
                            wheelEnabled: false
                            onModelChanged: Qt.callLater(root.ensureMonitorSelection)
                            Component.onCompleted: {
                                root.monitorSelectionReady = true
                                root.ensureMonitorSelection()
                            }
                            onActivated: root.selectMonitor(model[currentIndex].screen)
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
                        objectName: "confirmMonitorButton"
                        visible: !controller.current_position && !controller.fixed_position_confirmed
                        enabled: !!root.selectedMonitor && !controller.running && !controller.busy
                        text: qsTr("Monitor und Koordinaten bestätigen")
                        onClicked: root.confirmMonitor()
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
                        objectName: "hotkeyStatusLabel"
                        text: controller.hotkey_configuring ? qsTr("Öffnet Dialog …") :
                              controller.hotkey_pending ? qsTr("Wird eingerichtet …") :
                                  (controller.hotkey_ready ? controller.hotkey : qsTr("Nicht verfügbar"))
                        font.bold: true
                    }
                    Controls.Button {
                        objectName: "hotkeyConfigureButton"
                        text: controller.hotkey_ready ? qsTr("Ändern …") : qsTr("Erneut versuchen")
                        enabled: !controller.busy && !controller.running && !controller.hotkey_pending
                        onClicked: controller.configure_hotkey()
                    }
                }
            }

            Controls.Button {
                objectName: "startStopButton"
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.6
                highlighted: true
                text: controller.running || controller.busy ? qsTr("■  Stoppen") : qsTr("▶  Starten")
                enabled: controller.running || controller.busy || (controller.hotkey_ready && !controller.hotkey_pending)
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
                    objectName: "statusLabel"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: controller.running
                        ? qsTr("Status: %1 · %2").arg(controller.status).arg(root.rateDescription)
                        : qsTr("Status: %1").arg(controller.status)
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
