# Virtual Wayland test environment

`bash tests/qml-wayland.sh` starts a private D-Bus session and a virtual KWin
with three outputs, including an output above and left of the others. It runs the
complete QML suite using real Wayland windows. The script isolates runtime and
configuration directories and cleans up the entire session process group.
Python 3 is required to verify the effective output configuration before QML runs.

The `virtual-wayland` CI job uses the **2026/10/13 Arch Linux Archive** snapshot:
KWin `6.7.5-3`, Qt Base `6.12.0-2`, Qt Declarative/Wayland `6.12.0-1`, and
libkscreen `6.7.5-1`. Only this job is pinned. The build, offscreen QML, and
package checks continue to use rolling Arch dependencies.

## Why the snapshot is required

KWin 6.8 removed the virtual backend's QPainter renderer. Compare
[6.7.5's supported compositors](https://github.com/KDE/kwin/blob/v6.7.5/src/backends/virtual/virtual_backend.cpp#L89-L106)
with [6.8.0's OpenGL-only backend](https://github.com/KDE/kwin/blob/v6.8.0/src/backends/virtual/virtual_backend.cpp#L37-L44).
Our script deliberately uses `KWIN_COMPOSE=Q` to run without host graphics devices.

In a device-free container, KWin 6.8 also has no render device: its
[GPU manager](https://github.com/KDE/kwin/blob/v6.8.0/src/core/gpumanager.cpp#L80-L99)
requires `/dev/udmabuf` for a software device or an accessible DRM device.
The [QPA integration](https://github.com/KDE/kwin/blob/v6.8.0/src/plugins/qpa/integration.cpp#L203-L206)
dereferences the missing primary device during startup. With Arch's KWin
`6.8.0-1`, gdb stops in `KWin::RenderDevice::eglShareContext()`; the test script
exits 139 before QML tests run, with empty compositor and output logs.
`KWIN_COMPOSE=O2 LIBGL_ALWAYS_SOFTWARE=1` fails at the same point because it
does not supply the missing device.

The archive pins the entire package set together. Installing an older KWin
beside rolling Qt/KDE libraries would create an unsupported partial downgrade.
`pacman -Syyuu` refreshes the archive databases and allows the base container's
newer packages to be downgraded to the same date. Package signatures remain
enabled. This requires no host devices, desktop mounts, or extra privileges.

The old script also requested a negative position for `Virtual-2`. KWin rejects
that request, while `kscreen-doctor` returns zero with an error message. The
entire configuration, including scale changes, then remains unapplied. The
layout is now translated 1920 logical pixels to the right: `Virtual-0` at
`1920,1080`, `Virtual-1` at `3840,1080`, and `Virtual-2` at `0,0`. This preserves
their relative positions. `check_virtual_outputs.py` checks KScreen's JSON for
exactly those three connected, enabled outputs, their positions, and all
requested scales. A mismatch fails the session before any QML tests run.

## Reproduce CI locally

Build a disposable image with this Dockerfile, keeping the snapshot and package
list in sync with `.github/workflows/ci.yml`:

```dockerfile
FROM archlinux:base-devel
RUN printf 'Server = https://archive.archlinux.org/repos/2026/10/13/$repo/os/$arch\n' > /etc/pacman.d/mirrorlist \
 && pacman -Syyuu --noconfirm --needed \
      git ca-certificates python qt6-base qt6-declarative qt6-wayland \
      kirigami qqc2-desktop-style kwin libkscreen dbus mesa libcap \
 && setcap -r /usr/bin/kwin_wayland
WORKDIR /work
```

With the resulting image tagged `klickmeister-virtual-wayland:local`, run from
the checkout root:

```bash
docker run --rm --network none \
  --mount "type=bind,source=$PWD,target=/work,readonly" \
  klickmeister-virtual-wayland:local bash tests/qml-wayland.sh
```

Additional runs can pass `-e KLICKMEISTER_TEST_SCALE=1.5`, or
`-e KLICKMEISTER_TEST_SCALE_1=1.5 -e KLICKMEISTER_TEST_SCALE_2=2`, to Docker.
The runtime container needs no network access or mounts from a desktop session.

## Updating the environment

Advance the date in the virtual job and this document together only after
checking the candidate KWin's virtual rendering requirements. To remove the pin,
verify that the current compositor supports a device-free virtual session again.
Install the complete dependency set from the candidate repositories into a fresh
container; avoid pinning KWin alone. Keep the same device-free Docker invocation,
the three-output layout, and the full QML assertions. Require the complete suite
to pass at scale 1, scale 1.5, and mixed scales before changing the constraint.
A startup crash remains a failing test, including when it produces no QML log.
