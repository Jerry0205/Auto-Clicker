import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import io.github.jerry0205.klickmeister

Kirigami.ApplicationWindow {
    id: root

    property bool smokeTest: false

    width: 520
    height: 720
    minimumWidth: 460
    minimumHeight: 620
    visible: true
    title: qsTr("Klickmeister")

    AppController {
        id: controller
    }

    PositionPicker {
        id: positionPicker
        transientParent: root
        onPicked: function(x, y) {
            controller.fixed_x = x
            controller.fixed_y = y
            controller.current_position = false
        }
    }

    Component.onCompleted: {
        if (!smokeTest) {
            controller.initialize()
        }
    }
    onClosing: function(close) {
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
                            Layout.fillWidth: true
                            from: 0
                            to: 100000
                            editable: true
                            value: controller.fixed_x
                            onValueModified: controller.fixed_x = value
                        }
                        Controls.Label { text: qsTr("Y") }
                        Controls.SpinBox {
                            Layout.fillWidth: true
                            from: 0
                            to: 100000
                            editable: true
                            value: controller.fixed_y
                            onValueModified: controller.fixed_y = value
                        }
                        Controls.Button {
                            text: qsTr("Wählen …")
                            icon.name: "crosshairs"
                            onClicked: positionPicker.showFullScreen()
                        }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        visible: !controller.current_position
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.disabledTextColor
                        text: qsTr("Koordinaten sind relativ zum gewählten Monitor. Beim Start bestätigt KWin einmalig Monitor- und Zeigerzugriff.")
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
        }
    }
}
