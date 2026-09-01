import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Window {
    id: picker

    required property Window hostWindow
    property bool inputReady: false

    signal picked(int x, int y)
    signal finished()

    function begin() {
        if (picker.visible) {
            return
        }

        inputReady = false
        picker.showFullScreen()
        picker.raise()
        picker.requestActivate()
        picker.contentItem.forceActiveFocus()
        updateInputReady()
    }

    function updateInputReady() {
        if (!picker.visible) {
            return
        }

        inputReady = picker.visibility === Window.FullScreen
            && picker.width === picker.screen.width
            && picker.height === picker.screen.height
    }

    function finish() {
        inputReady = false
        picker.hide()
        picker.finished()
    }

    visible: false
    transientParent: null
    flags: Qt.FramelessWindowHint
    color: "transparent"

    Connections {
        target: picker

        function onHeightChanged() { picker.updateInputReady() }
        function onVisibilityChanged() { picker.updateInputReady() }
        function onWidthChanged() { picker.updateInputReady() }
    }

    Rectangle {
        anchors.fill: parent
        color: "#e6151a20"
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: picker.inputReady ? Qt.CrossCursor : Qt.BusyCursor
        onClicked: function(mouse) {
            if (!picker.inputReady) {
                return
            }

            picker.picked(Math.round(mouse.x), Math.round(mouse.y))
            picker.finish()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.max(message.implicitWidth, cancelButton.implicitWidth)
            + Kirigami.Units.gridUnit * 3
        height: message.implicitHeight + cancelButton.implicitHeight
            + Kirigami.Units.gridUnit * 2.5
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.focusColor

        Controls.Label {
            id: message
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Kirigami.Units.gridUnit
            text: picker.inputReady
                ? qsTr("Gewünschte Position anklicken")
                : qsTr("Vollbild wird vorbereitet …")
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            cursorShape: Qt.ArrowCursor
        }

        Controls.Button {
            id: cancelButton
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: message.bottom
            anchors.topMargin: Kirigami.Units.largeSpacing
            text: qsTr("Abbrechen (Esc)")
            onClicked: picker.finish()
        }
    }

    Shortcut {
        enabled: picker.visible
        sequence: StandardKey.Cancel
        onActivated: picker.finish()
    }
}
