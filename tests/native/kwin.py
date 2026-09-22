import json
import os
import sys
import time
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
base = Path(os.environ["KLICKMEISTER_NATIVE_DIR"])
pids = json.loads((base / "pids.json").read_text())
op = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
allowed = {
    "snapshot",
    "place",
    "focus_app",
    "focus_target",
    "focus_picker",
    "close_app",
    "focus_portal",
}
assert op in allowed
bus = dbus.SessionBus(private=True)
name = dbus.service.BusName("io.github.klickmeister.NativeTestInspector", bus)
loop = GLib.MainLoop()
result = []


class Receiver(dbus.service.Object):
    @dbus.service.method(
        "io.github.klickmeister.NativeTestInspector", in_signature="s", out_signature=""
    )
    def Report(self, value):
        result.append(json.loads(value))
        print(value, flush=True)
        loop.quit()


receiver = Receiver(bus, "/NativeTest")
script = (
    """
const windows=workspace.windowList();
const app=windows.find(w=>w.pid===APP_PID && String(w.caption).startsWith('Klickmeister '));
const target=windows.find(w=>w.pid===TARGET_PID);
const picker=windows.find(w=>w.pid===APP_PID && w!==app);
const op=OP;
if(op==='focus_portal'){const dialogs=windows.filter(w=>String(w.resourceName).includes('portal'));if(dialogs.length===1)workspace.activeWindow=dialogs[0];}
if(op==='place'&&app){app.setMaximize(false,false);app.frameGeometry={x:1050,y:40,width:600,height:1040};workspace.activeWindow=app;}
if(op==='focus_app'&&app) workspace.activeWindow=app;
if(op==='focus_target'&&target) workspace.activeWindow=target;
if(op==='focus_picker'&&picker) workspace.activeWindow=picker;
if(op==='close_app'&&app) app.closeWindow();
const output=windows.filter(w=>w===app||w===target||w===picker||String(w.resourceName).includes('portal')).map(w=>({
caption:w.caption,resource:String(w.resourceName),active:w.active,pid:w.pid,
kind:w===app?"app":w===target?"target":w===picker?"picker":"portal",
geometry:{x:w.frameGeometry.x,y:w.frameGeometry.y,width:w.frameGeometry.width,height:w.frameGeometry.height}}));
callDBus('io.github.klickmeister.NativeTestInspector','/NativeTest','io.github.klickmeister.NativeTestInspector','Report',JSON.stringify(output));
""".replace("OP", json.dumps(op))
    .replace("APP_PID", str(pids["app"]))
    .replace("TARGET_PID", str(pids["target"]))
)
path = base / "inspect-window.js"
path.write_text(script)
scripting = dbus.Interface(
    bus.get_object("org.kde.KWin", "/Scripting", introspect=False),
    "org.kde.kwin.Scripting",
)
plugin = "klickmeister_native_test_" + str(time.monotonic_ns())
sid = scripting.loadScript(str(path), plugin, signature="ss")
try:
    control = dbus.Interface(
        bus.get_object("org.kde.KWin", "/Scripting/Script" + str(sid)),
        "org.kde.kwin.Script",
    )
    control.run()
    GLib.timeout_add_seconds(5, lambda: loop.quit())
    loop.run()
    if not result:
        raise TimeoutError("KWin did not report inspected windows")
finally:
    scripting.unloadScript(plugin)
    bus.close()
