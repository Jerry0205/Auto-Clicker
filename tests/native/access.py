import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib  # noqa: E402 -- require the version before import


def apps():
    d = Atspi.get_desktop(0)
    return [d.get_child_at_index(i) for i in range(d.get_child_count())]


def walk(node, depth=0):
    if node is None or depth > 25:
        return
    node.clear_cache()
    yield node, depth
    try:
        for i in range(node.get_child_count()):
            yield from walk(node.get_child_at_index(i), depth + 1)
    except Exception:
        pass


def nodes(app="klickmeister"):
    context = GLib.MainContext.default()
    while context.pending():
        context.iteration(False)
    for root in apps():
        if app.lower() in (root.get_name() or "").lower():
            yield from walk(root)


def info(node, depth=0):
    states = node.get_state_set()
    row = {
        "depth": depth,
        "role": node.get_role_name(),
        "name": node.get_name(),
        "visible": states.contains(Atspi.StateType.VISIBLE),
        "showing": states.contains(Atspi.StateType.SHOWING),
        "enabled": states.contains(Atspi.StateType.ENABLED),
        "focused": states.contains(Atspi.StateType.FOCUSED),
    }
    try:
        action = node.get_action_iface()
        if action:
            row["actions"] = [
                action.get_action_name(i) for i in range(action.get_n_actions())
            ]
    except Exception:
        pass
    try:
        text = node.get_text_iface()
        if text:
            row["text"] = Atspi.Text.get_text(node, 0, -1)
    except Exception:
        pass
    try:
        c = node.get_component_iface()
        if c:
            r = c.get_extents(Atspi.CoordType.SCREEN)
            row["rect"] = [r.x, r.y, r.width, r.height]
    except Exception:
        pass
    return row


def find(name, app="klickmeister", role=None, contains=False):
    found = []
    for n, d in nodes(app):
        if ((name in (n.get_name() or "")) if contains else n.get_name() == name) and (
            not role or n.get_role_name() == role
        ):
            found.append(n)
    if len(found) != 1:
        raise RuntimeError(f"Expected one {name!r} ({role}), got {len(found)}")
    return found[0]


def action(name, app="klickmeister", role=None, contains=False, index=0):
    n = find(name, app, role, contains)
    a = n.get_action_iface()
    if not a:
        raise RuntimeError("No action: " + name)
    if not a.do_action(index):
        raise RuntimeError("Action failed: " + name)


if __name__ == "__main__":
    app = sys.argv[1] if len(sys.argv) > 1 else "klickmeister"
    for n, d in nodes(app):
        try:
            print(json.dumps(info(n, d), ensure_ascii=False))
        except Exception:
            pass
