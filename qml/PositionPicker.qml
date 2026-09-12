import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Window {
    id: picker

    required property Window hostWindow
    property int captureId: 0
    property bool inputReady: false
    property bool selecting: false
    property bool previewOnly: false
    property bool waitingForScreenshot: false
    property int targetX: 0
    property int targetY: 0
    property int hostVisibility: Window.Windowed
    property string captureError: ""
    property rect desktopBounds: Qt.rect(0, 0, 1, 1)
    property bool hintAtBottom: false
    readonly property bool magnifierReady: snapshot.status === Image.Ready
    signal picked(int x, int y)
    signal screenshotRequested(int requestId)

    function setTarget(x, y) {
        targetX = Math.max(0, Math.min(Math.round(x), Math.max(0, width - 1)))
        targetY = Math.max(0, Math.min(Math.round(y), Math.max(0, height - 1)))
        // Move the hint out of the way before the pointer reaches it.
        if (targetY < 110) hintAtBottom = true
        else if (targetY > height - 110) hintAtBottom = false
    }

    function begin(targetScreen, x, y, preview, magnifier) {
        if (selecting || !targetScreen) return
        captureId += 1
        screen = targetScreen
        hostVisibility = hostWindow.visibility
        previewOnly = preview
        selecting = true
        inputReady = false
        captureError = ""
        snapshot.source = ""
        targetX = x
        targetY = y
        hintAtBottom = y < 110
        desktopBounds = Qt.rect(screen.virtualX, screen.virtualY, screen.width, screen.height)
        const screens = Qt.application.screens
        for (let i = 0; i < screens.length; ++i) {
            const s = screens[i]
            const left = Math.min(desktopBounds.x, s.virtualX)
            const top = Math.min(desktopBounds.y, s.virtualY)
            const right = Math.max(desktopBounds.x + desktopBounds.width, s.virtualX + s.width)
            const bottom = Math.max(desktopBounds.y + desktopBounds.height, s.virtualY + s.height)
            desktopBounds = Qt.rect(left, top, right - left, bottom - top)
        }
        hostWindow.hide()
        waitingForScreenshot = magnifier && !preview
        if (waitingForScreenshot) captureDelay.start()
        else showPicker()
    }

    function showPicker() {
        if (!selecting) return
        showFullScreen()
        raise()
        requestActivate()
        keyboard.forceActiveFocus()
        updateInputReady()
        if (previewOnly) previewTimer.start()
    }

    function acceptScreenshot(requestId, uri, error) {
        if (!selecting || !waitingForScreenshot || requestId !== captureId) return
        captureDelay.stop()
        waitingForScreenshot = false
        captureError = error.length > 0 ? qsTr("Bildschirmaufnahme nicht verfügbar – Auswahl ohne Lupe") : ""
        snapshot.source = uri
        showPicker()
    }

    function updateInputReady() {
        inputReady = selecting && visible && visibility === Window.FullScreen
            && width === screen.width && height === screen.height
        if (inputReady) setTarget(targetX, targetY)
    }

    function confirm() {
        if (!inputReady || previewOnly) return
        picked(targetX, targetY)
        finish()
    }

    function finish(restoreHost) {
        if (!selecting) return
        selecting = false
        inputReady = false
        waitingForScreenshot = false
        captureDelay.stop()
        previewTimer.stop()
        hide()
        snapshot.source = ""
        if (restoreHost !== false) {
            if (hostVisibility === Window.Maximized) hostWindow.showMaximized()
            else if (hostVisibility === Window.FullScreen) hostWindow.showFullScreen()
            else hostWindow.showNormal()
            hostWindow.raise()
            hostWindow.requestActivate()
        }
    }

    visible: false
    transientParent: null
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    onClosing: function(close) { close.accepted = false; finish() }

    Timer { id: captureDelay; interval: 250; onTriggered: picker.screenshotRequested(picker.captureId) }
    Timer { id: previewTimer; interval: 1800; onTriggered: picker.finish() }

    Connections {
        target: picker
        function onHeightChanged() { picker.updateInputReady() }
        function onVisibilityChanged() { picker.updateInputReady() }
        function onWidthChanged() { picker.updateInputReady() }
    }

    // A portal screenshot is a still image of the virtual desktop. Keeping it
    // behind the overlay makes the magnified detail match the selected point.
    Item {
        anchors.fill: parent
        clip: true
        visible: picker.magnifierReady
        Image {
            id: snapshot
            x: picker.desktopBounds.x - picker.screen.virtualX
            y: picker.desktopBounds.y - picker.screen.virtualY
            width: picker.desktopBounds.width
            height: picker.desktopBounds.height
            cache: false
            fillMode: Image.Stretch
            onStatusChanged: {
                if (status === Image.Error)
                    picker.captureError = qsTr("Bildschirmaufnahme konnte nicht geladen werden – Auswahl ohne Lupe")
                if (status === Image.Ready && Math.abs(sourceSize.width / sourceSize.height - width / height) > 0.01) {
                    picker.captureError = qsTr("Bildschirmaufnahme passt nicht zur Monitoranordnung – Auswahl ohne Lupe")
                    source = ""
                }
            }
        }
    }

    Rectangle { anchors.fill: parent; color: picker.previewOnly ? "transparent" : "#18151a20" }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: picker.inputReady ? Qt.CrossCursor : Qt.BusyCursor
        onPositionChanged: function(mouse) {
            if (picker.inputReady && !picker.previewOnly) picker.setTarget(mouse.x, mouse.y)
        }
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton || picker.previewOnly) picker.finish()
            else {
                picker.setTarget(mouse.x, mouse.y)
                picker.confirm()
            }
        }
    }

    Item {
        x: picker.targetX
        y: picker.targetY
        visible: picker.inputReady
        Rectangle { x: -18; y: -1; width: 37; height: 3; color: "black" }
        Rectangle { x: -1; y: -18; width: 3; height: 37; color: "black" }
        Rectangle { x: -17; width: 35; height: 1; color: "white" }
        Rectangle { y: -17; width: 1; height: 35; color: "white" }
        Rectangle {
            x: -9; y: -9; width: 19; height: 19
            radius: 10; color: "transparent"; border.width: 2; border.color: "#3daee9"
        }
    }

    Rectangle {
        id: magnifier
        visible: picker.magnifierReady && !picker.previewOnly
        x: picker.targetX + 180 < picker.width ? picker.targetX + 28 : picker.targetX - width - 28
        y: Math.max(0, Math.min(picker.targetY + 28, picker.height - height))
        width: 148; height: 148
        color: "#151a20"
        border.color: "#3daee9"; border.width: 2
        clip: true
        Image {
            x: parent.width / 2 - (picker.targetX + picker.screen.virtualX - picker.desktopBounds.x) * 4
            y: parent.height / 2 - (picker.targetY + picker.screen.virtualY - picker.desktopBounds.y) * 4
            width: picker.desktopBounds.width * 4
            height: picker.desktopBounds.height * 4
            source: snapshot.source
            cache: false
            smooth: false
        }
        Rectangle { anchors.centerIn: parent; width: 21; height: 1; color: "#ff4040" }
        Rectangle { anchors.centerIn: parent; width: 1; height: 21; color: "#ff4040" }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: picker.hintAtBottom ? picker.height - height - 12 : 12
        width: Math.min(picker.width - 24, message.implicitWidth + 32)
        height: message.implicitHeight + 20
        radius: Kirigami.Units.cornerRadius
        color: "#ee151a20"
        border.color: "#3daee9"
        // No input handler: every point, including the hint, is selectable.
        Controls.Label {
            id: message
            anchors.centerIn: parent
            width: Math.min(implicitWidth, picker.width - 56)
            color: "white"
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: picker.previewOnly
                ? qsTr("Zielposition · X: %1 · Y: %2").arg(picker.targetX).arg(picker.targetY)
                : qsTr("%1 · X: %2 · Y: %3\nKlicken / Enter: übernehmen · Pfeiltasten: 1 Schritt · Umschalt: 10 · Esc / Rechtsklick: abbrechen")
                    .arg(picker.screen.name).arg(picker.targetX).arg(picker.targetY)
                    + (picker.magnifierReady ? qsTr("\nLupe 4× · Standbild") : "")
                    + (picker.captureError.length ? "\n" + picker.captureError : "")
        }
    }

    Shortcut { enabled: picker.visible; sequence: StandardKey.Cancel; onActivated: picker.finish() }
    Item {
        id: keyboard
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            if (!picker.inputReady || picker.previewOnly) return
            const step = event.modifiers & Qt.ShiftModifier ? 10 : 1
            switch (event.key) {
            case Qt.Key_Left: picker.setTarget(picker.targetX - step, picker.targetY); break
            case Qt.Key_Right: picker.setTarget(picker.targetX + step, picker.targetY); break
            case Qt.Key_Up: picker.setTarget(picker.targetX, picker.targetY - step); break
            case Qt.Key_Down: picker.setTarget(picker.targetX, picker.targetY + step); break
            case Qt.Key_Return:
            case Qt.Key_Enter: picker.confirm(); break
            default: return
            }
            event.accepted = true
        }
    }
}
