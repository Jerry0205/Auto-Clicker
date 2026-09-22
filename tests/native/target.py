import json
import os
import sys
import time

from PySide6.QtCore import QEvent, Qt, QTimer
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtNetwork import QLocalServer
from PySide6.QtWidgets import QApplication, QWidget

base = os.environ["KLICKMEISTER_NATIVE_DIR"]
app = QApplication(sys.argv)
app.setApplicationName("Klickmeister Native Test Target")
log = open(base + "/mouse-events.jsonl", "a", buffering=1)


class Target(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Klickmeister – isoliertes Klicktestziel")
        self.setFocusPolicy(Qt.StrongFocus)
        self.setMouseTracking(True)
        self.count = 0

    def paintEvent(self, event):
        p = QPainter(self)
        p.fillRect(self.rect(), QColor("#152334"))
        p.setPen(QColor("white"))
        p.drawText(30, 50, "Klickmeister: native Funktionsprüfung – eigenes Testziel")
        p.drawText(30, 80, f"Empfangene Mausereignisse: {self.count}")
        p.drawText(30, 110, "Klickziel: X=80, Y=400. Tests werden automatisch beendet.")
        p.setPen(QPen(QColor("#5eeab0"), 3))
        p.drawEllipse(50, 370, 60, 60)
        p.drawLine(65, 400, 95, 400)
        p.drawLine(80, 385, 80, 415)

    def closeEvent(self, event):
        # Keep the sink mapped even if a window-manager shortcut is delivered
        # here while clicks repeatedly transfer focus back to the target.
        event.ignore()

    def event(self, e):
        if e.type() in (
            QEvent.MouseButtonPress,
            QEvent.MouseButtonDblClick,
            QEvent.MouseButtonRelease,
        ):
            self.count += 1
            log.write(
                json.dumps(
                    {
                        "t_ns": time.monotonic_ns(),
                        "type": e.type().name,
                        "button": e.button().value,
                        "buttons": e.buttons().value,
                        "x": e.position().x(),
                        "y": e.position().y(),
                        "global_x": e.globalPosition().x(),
                        "global_y": e.globalPosition().y(),
                    }
                )
                + "\n"
            )
            self.update()
        elif e.type() in (QEvent.KeyPress, QEvent.KeyRelease):
            log.write(
                json.dumps(
                    {"t_ns": time.monotonic_ns(), "type": e.type().name, "key": e.key()}
                )
                + "\n"
            )
        return super().event(e)


w = Target()
w.showFullScreen()
server = QLocalServer()
assert server.listen(base + "/target.sock")
connections = []


def accept():
    c = server.nextPendingConnection()
    connections.append(c)

    def read():
        while c.canReadLine():
            request = json.loads(bytes(c.readLine()))
            cmd = request["cmd"]
            if cmd == "activate":
                w.showFullScreen()
                w.raise_()
                w.activateWindow()
            elif cmd == "quit":
                QTimer.singleShot(50, app.quit)
            elif cmd == "grab":
                w.grab().save(request["path"])
            s = w.screen()
            g = s.geometry()
            response = {
                "count": w.count,
                "active": w.isActiveWindow(),
                "visible": w.isVisible(),
                "geometry": [g.x(), g.y(), g.width(), g.height()],
                "screen": {
                    "name": s.name(),
                    "manufacturer": s.manufacturer(),
                    "model": s.model(),
                    "serial": s.serialNumber(),
                    "width": g.width(),
                    "height": g.height(),
                    "scale": s.devicePixelRatio(),
                },
            }
            c.write((json.dumps(response) + "\n").encode())
            c.flush()

    c.readyRead.connect(read)

    def disconnected():
        connections.remove(c)
        c.deleteLater()

    c.disconnected.connect(disconnected)


server.newConnection.connect(accept)
# The click target must outlive all click runs. The orchestrator closes it only
# after the application has exited; an independent timeout is unsafe here.
sys.exit(app.exec())
