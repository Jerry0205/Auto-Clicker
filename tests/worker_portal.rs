//! End-to-end worker protocol tests on a private bus, without real pointer input.
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

use ashpd::zbus::{
    self,
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};
use klickmeister::{
    model::{ClickSettings, ClickType, MonitorGeometry, MouseButton},
    worker::{Command, WorkerEvent, WorkerHandle},
};
use tokio::{
    sync::{Notify, mpsc},
    time::{sleep, timeout},
};

type Options = HashMap<String, OwnedValue>;
type TestResult = Result<(), Box<dyn std::error::Error>>;
const PATH: &str = "/org/freedesktop/portal/desktop";

#[derive(Default)]
struct Observed {
    hotkey_session: String,
    remote_session: Option<OwnedObjectPath>,
    revoked_session: Option<OwnedObjectPath>,
    buttons: Vec<(i32, u32)>,
    release_failures: usize,
    closed: usize,
    stall_close: bool,
    close_releases: Vec<Arc<Notify>>,
    remote_owner: String,
    hotkey_owner: String,
    fixed_stream: bool,
    motions: Vec<(u32, f64, f64)>,
    delay_hotkey: bool,
    hotkey_seen: Arc<Notify>,
    hotkey_release: Arc<Notify>,
    delay_start: bool,
    start_seen: Arc<Notify>,
    start_release: Arc<Notify>,
    delay_button: bool,
    button_seen: Arc<Notify>,
    button_release: Arc<Notify>,
}
type Shared = Arc<Mutex<Observed>>;

fn failed(error: impl std::fmt::Display) -> zbus::fdo::Error {
    zbus::fdo::Error::Failed(error.to_string())
}

fn handle(
    header: &zbus::message::Header<'_>,
    options: &Options,
    key: &str,
    kind: &str,
) -> zbus::fdo::Result<OwnedObjectPath> {
    let sender = header
        .sender()
        .ok_or_else(|| failed("missing sender"))?
        .as_str()
        .trim_start_matches(':')
        .replace('.', "_");
    let token = options
        .get(key)
        .and_then(|v| <&str>::try_from(v).ok())
        .ok_or_else(|| failed("missing token"))?;
    OwnedObjectPath::try_from(format!("{PATH}/{kind}/{sender}/{token}")).map_err(failed)
}

async fn respond(
    connection: &zbus::Connection,
    header: &zbus::message::Header<'_>,
    options: &Options,
    results: Options,
) -> zbus::fdo::Result<OwnedObjectPath> {
    let path = handle(header, options, "handle_token", "request")?;
    connection
        .emit_signal(
            header.sender().cloned(),
            &path,
            "org.freedesktop.portal.Request",
            "Response",
            &(0_u32, results),
        )
        .await
        .map_err(failed)?;
    Ok(path)
}

struct FakeSession(Shared);
#[zbus::interface(name = "org.freedesktop.portal.Session", crate = "ashpd::zbus")]
impl FakeSession {
    /// Record each close and optionally hold its reply until the test releases it.
    async fn close(&self) {
        let release = {
            let mut state = self.0.lock().unwrap_or_else(|e| e.into_inner());
            state.closed += 1;
            if state.stall_close {
                let release = Arc::new(Notify::new());
                state.close_releases.push(release.clone());
                Some(release)
            } else {
                None
            }
        };
        if let Some(release) = release {
            release.notified().await;
        }
    }
    #[zbus(property)]
    fn version(&self) -> u32 {
        1
    }
}

async fn create(
    connection: &zbus::Connection,
    header: &zbus::message::Header<'_>,
    options: &Options,
    observed: &Shared,
    hotkey: bool,
) -> zbus::fdo::Result<OwnedObjectPath> {
    let session = handle(header, options, "session_handle_token", "session")?;
    connection
        .object_server()
        .at(session.clone(), FakeSession(observed.clone()))
        .await
        .map_err(failed)?;
    if hotkey {
        observed
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .hotkey_session = session.to_string();
    } else {
        observed
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remote_session = Some(session.clone());
    }
    {
        let mut state = observed.lock().unwrap_or_else(|e| e.into_inner());
        let owner = header
            .sender()
            .ok_or_else(|| failed("missing owner"))?
            .to_string();
        if hotkey {
            state.hotkey_owner = owner;
        } else {
            state.remote_owner = owner;
        }
    }
    let results = HashMap::from([(
        "session_handle".into(),
        Value::from(session).try_into().map_err(failed)?,
    )]);
    respond(connection, header, options, results).await
}

struct FakeHotkeys(Shared);
#[zbus::interface(name = "org.freedesktop.portal.GlobalShortcuts", crate = "ashpd::zbus")]
impl FakeHotkeys {
    #[zbus(property)]
    fn version(&self) -> u32 {
        2
    }

    async fn create_session(
        &self,
        options: Options,
        #[zbus(connection)] connection: &zbus::Connection,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        create(connection, &header, &options, &self.0, true).await
    }

    async fn bind_shortcuts(
        &self,
        _session: OwnedObjectPath,
        _shortcuts: Vec<(String, Options)>,
        _parent: String,
        options: Options,
        #[zbus(connection)] connection: &zbus::Connection,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        let (delay, seen, release) = {
            let state = self.0.lock().unwrap_or_else(|e| e.into_inner());
            (
                state.delay_hotkey,
                state.hotkey_seen.clone(),
                state.hotkey_release.clone(),
            )
        };
        if delay {
            seen.notify_one();
            release.notified().await;
        }
        let shortcuts = vec![(
            "toggle-clicking",
            HashMap::from([
                ("description", Value::from("Start/Stop")),
                ("trigger_description", Value::from("Pause")),
            ]),
        )];
        let results = HashMap::from([(
            "shortcuts".into(),
            Value::new(shortcuts).try_into().map_err(failed)?,
        )]);
        respond(connection, &header, &options, results).await
    }
}

struct FakeRemote(Shared);
#[zbus::interface(name = "org.freedesktop.portal.RemoteDesktop", crate = "ashpd::zbus")]
impl FakeRemote {
    #[zbus(property)]
    fn version(&self) -> u32 {
        2
    }
    #[zbus(property)]
    fn available_device_types(&self) -> u32 {
        2
    }

    async fn create_session(
        &self,
        options: Options,
        #[zbus(connection)] connection: &zbus::Connection,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .fixed_stream = false;
        create(connection, &header, &options, &self.0, false).await
    }
    async fn select_devices(
        &self,
        _session: OwnedObjectPath,
        options: Options,
        #[zbus(connection)] connection: &zbus::Connection,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        assert_eq!(
            options.get("types").and_then(|v| u32::try_from(v).ok()),
            Some(2)
        );
        respond(connection, &header, &options, Options::new()).await
    }
    async fn start(
        &self,
        _session: OwnedObjectPath,
        _parent: String,
        options: Options,
        #[zbus(connection)] connection: &zbus::Connection,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        let (fixed, delay, seen, release) = {
            let state = self.0.lock().unwrap_or_else(|e| e.into_inner());
            (
                state.fixed_stream,
                state.delay_start,
                state.start_seen.clone(),
                state.start_release.clone(),
            )
        };
        if delay {
            seen.notify_one();
            release.notified().await;
        }
        let mut results = HashMap::from([("devices".into(), OwnedValue::from(2_u32))]);
        if fixed {
            let stream = vec![(
                42_u32,
                HashMap::from([
                    ("position", Value::new((-1920_i32, 0_i32))),
                    ("size", Value::new((1920_i32, 1080_i32))),
                ]),
            )];
            results.insert(
                "streams".into(),
                Value::new(stream).try_into().map_err(failed)?,
            );
        }
        respond(connection, &header, &options, results).await
    }
    async fn notify_pointer_button(
        &self,
        session: OwnedObjectPath,
        _options: Options,
        button: i32,
        state: u32,
    ) -> zbus::fdo::Result<()> {
        let delay = {
            let mut observed = self.0.lock().unwrap_or_else(|e| e.into_inner());
            if observed.revoked_session.as_ref() == Some(&session) {
                return Err(failed("session revoked"));
            }
            observed.buttons.push((button, state));
            if state == 0 && observed.release_failures > 0 {
                observed.release_failures -= 1;
                return Err(failed("simulated release failure"));
            }
            (state == 1 && observed.delay_button).then(|| {
                (
                    observed.button_seen.clone(),
                    observed.button_release.clone(),
                )
            })
        };
        if let Some((seen, release)) = delay {
            seen.notify_one();
            release.notified().await;
        }
        Ok(())
    }

    async fn notify_pointer_motion_absolute(
        &self,
        _session: OwnedObjectPath,
        _options: Options,
        stream: u32,
        x: f64,
        y: f64,
    ) {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .motions
            .push((stream, x, y));
    }
}

struct FakeScreencast(Shared);
#[zbus::interface(name = "org.freedesktop.portal.ScreenCast", crate = "ashpd::zbus")]
impl FakeScreencast {
    #[zbus(property)]
    fn version(&self) -> u32 {
        5
    }

    async fn select_sources(
        &self,
        _session: OwnedObjectPath,
        options: Options,
        #[zbus(connection)] connection: &zbus::Connection,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<OwnedObjectPath> {
        assert_eq!(
            options.get("types").and_then(|v| u32::try_from(v).ok()),
            Some(1)
        );
        assert_eq!(
            options.get("multiple").and_then(|v| bool::try_from(v).ok()),
            Some(false)
        );
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .fixed_stream = true;
        respond(connection, &header, &options, Options::new()).await
    }
}

async fn event(
    events: &mut mpsc::UnboundedReceiver<WorkerEvent>,
    matches: impl Fn(&WorkerEvent) -> bool,
) -> Result<WorkerEvent, Box<dyn std::error::Error>> {
    timeout(Duration::from_secs(3), async {
        while let Some(event) = events.recv().await {
            if matches(&event) {
                return Ok(event);
            }
            if let WorkerEvent::Error(error) = event {
                return Err(error.into());
            }
        }
        Err("worker event stream ended".into())
    })
    .await?
}

/// Run with: dbus-run-session -- cargo test --test worker_portal -- --ignored
#[tokio::test]
#[ignore = "requires a private D-Bus session via dbus-run-session"]
async fn clicks_stop_hotkey_loss_and_shutdown() -> TestResult {
    let observed = Shared::default();
    let service = zbus::connection::Builder::session()?
        .name("org.freedesktop.portal.Desktop")?
        .serve_at(PATH, FakeHotkeys(observed.clone()))?
        .serve_at(PATH, FakeRemote(observed.clone()))?
        .serve_at(PATH, FakeScreencast(observed.clone()))?
        .build()
        .await?;
    let settings = ClickSettings {
        interval_ms: 10,
        button: MouseButton::Left,
        click_type: ClickType::Single,
        repeat: Some(3),
        position: None,
        monitor: None,
    };
    let (tx, mut events) = mpsc::unbounded_channel();
    let worker = WorkerHandle::spawn(settings.clone(), "Pause".into(), move |event| {
        let _ = tx.send(event);
    });
    let result: TestResult = async {
        event(&mut events, |e| matches!(e, WorkerEvent::Hotkey(_))).await?;
        let session = OwnedObjectPath::try_from(
            observed
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .hotkey_session
                .clone(),
        )?;
        let activation = (&session, "toggle-clicking", 0_u64, Options::new());
        service
            .emit_signal(
                None::<&str>,
                PATH,
                "org.freedesktop.portal.GlobalShortcuts",
                "Activated",
                &activation,
            )
            .await?;
        event(&mut events, |e| matches!(e, WorkerEvent::StartRequested(_))).await?;
        for button in [MouseButton::Left, MouseButton::Right, MouseButton::Middle] {
            for click_type in [ClickType::Single, ClickType::Double] {
                observed
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .buttons
                    .clear();
                worker.send(Command::Start(ClickSettings {
                    button,
                    click_type,
                    ..settings.clone()
                }))?;
                event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
                event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
                let buttons = observed
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .buttons
                    .clone();
                let expected = [(button.evdev_code(), 1), (button.evdev_code(), 0)]
                    .repeat(3 * usize::from(click_type.clicks_per_tick()));
                assert_eq!(buttons, expected);
            }
        }
        {
            let mut state = observed.lock().unwrap_or_else(|e| e.into_inner());
            state.revoked_session = state.remote_session.clone();
        }
        worker.send(Command::Start(settings.clone()))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Error(_))).await?;
        // Retry must request a fresh session instead of reusing the revoked one.
        worker.send(Command::Start(settings.clone()))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        {
            let state = observed.lock().unwrap_or_else(|e| e.into_inner());
            assert_ne!(state.remote_session, state.revoked_session);
        }

        let fixed = ClickSettings {
            position: Some((1919, 1079)),
            monitor: Some(MonitorGeometry { x: -1920, y: 0, width: 1920, height: 1080 }),
            ..settings.clone()
        };
        worker.send(Command::Start(fixed.clone()))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        assert_eq!(observed.lock().unwrap_or_else(|e| e.into_inner()).motions,
            vec![(42, 1919.0, 1079.0); 3]);

        // A different monitor must fail before sending motion or button events.
        let before = observed.lock().unwrap_or_else(|e| e.into_inner()).buttons.len();
        worker.send(Command::Start(ClickSettings {
            monitor: Some(MonitorGeometry { x: 0, y: 0, width: 1920, height: 1080 }),
            ..fixed.clone()
        }))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Error(message) if message.contains("Monitor stimmt nicht"))).await?;
        assert_eq!(observed.lock().unwrap_or_else(|e| e.into_inner()).buttons.len(), before);

        let (seen, release) = {
            let mut state = observed.lock().unwrap_or_else(|e| e.into_inner());
            state.delay_start = true;
            state.motions.clear();
            (state.start_seen.clone(), state.start_release.clone())
        };
        worker.send(Command::Start(fixed.clone()))?;
        timeout(Duration::from_secs(3), seen.notified()).await?;
        worker.send(Command::Start(ClickSettings { position: Some((100, 150)), ..fixed.clone() }))?;
        let closed_before_stop = observed.lock().unwrap_or_else(|e| e.into_inner()).closed;
        // This subsequent worker roundtrip proves the duplicate was processed.
        worker.send(Command::Stop)?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        assert!(observed.lock().unwrap_or_else(|e| e.into_inner()).closed > closed_before_stop,
            "Stop must close the pending RemoteDesktop session before confirming it");
        release.notify_one();
        sleep(Duration::from_millis(80)).await;
        assert_eq!(observed.lock().unwrap_or_else(|e| e.into_inner()).buttons.len(), before);
        assert!(observed.lock().unwrap_or_else(|e| e.into_inner()).motions.is_empty());
        observed.lock().unwrap_or_else(|e| e.into_inner()).delay_start = false;

        // A cancelled request must not prevent a later valid start.
        worker.send(Command::Start(fixed))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        assert_eq!(observed.lock().unwrap_or_else(|e| e.into_inner()).motions,
            vec![(42, 1919.0, 1079.0); 3]);

        {
            let mut observed = observed.lock().unwrap_or_else(|e| e.into_inner());
            observed.buttons.clear();
            observed.release_failures = 1;
        }
        worker.send(Command::Start(settings.clone()))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Error(_))).await?;
        assert_eq!(
            observed.lock().unwrap_or_else(|e| e.into_inner()).buttons,
            vec![(0x110, 1), (0x110, 0), (0x110, 0)]
        );

        worker.send(Command::Start(ClickSettings {
            repeat: None,
            ..settings.clone()
        }))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        worker.send(Command::Start(ClickSettings {
            interval_ms: 0,
            ..settings.clone()
        }))?;
        worker.send(Command::Stop)?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        let count = observed
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .buttons
            .len();
        sleep(Duration::from_millis(40)).await;
        assert_eq!(
            observed
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .buttons
                .len(),
            count
        );

        // Hold an actual click while all 16 command slots fill. Stop must
        // still reach the worker, and queued starts from before Stop must not
        // restart it once the blocked click finishes.
        let (button_seen, button_release) = {
            let mut state = observed.lock().unwrap_or_else(|e| e.into_inner());
            state.delay_button = true;
            (state.button_seen.clone(), state.button_release.clone())
        };
        let continuous = ClickSettings { repeat: None, ..settings.clone() };
        worker.send(Command::Start(continuous.clone()))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        timeout(Duration::from_secs(3), button_seen.notified()).await?;
        for _ in 0..16 {
            worker.send(Command::Start(continuous.clone()))?;
        }
        assert!(worker.send(Command::Start(continuous.clone())).is_err());
        // The activation reaches the portal receiver while the worker is
        // still blocked in a click. Stop must invalidate it as an old event.
        service
            .emit_signal(
                None::<&str>,
                PATH,
                "org.freedesktop.portal.GlobalShortcuts",
                "Activated",
                &activation,
            )
            .await?;
        worker.send(Command::Stop)?;
        button_release.notify_one();
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        observed.lock().unwrap_or_else(|e| e.into_inner()).delay_button = false;
        let count = observed.lock().unwrap_or_else(|e| e.into_inner()).buttons.len();
        sleep(Duration::from_millis(120)).await;
        assert_eq!(observed.lock().unwrap_or_else(|e| e.into_inner()).buttons.len(), count);
        while let Ok(event) = events.try_recv() {
            assert!(!matches!(event, WorkerEvent::Running(true)),
                "a queued start must not restart after Stop");
            assert!(!matches!(event, WorkerEvent::StartRequested(_)),
                "an activation received before Stop must not start a new run");
        }

        // Starting with the button before the old key is released must not
        // rearm it. A late activation can stop the new run, but cannot start it.
        worker.send(Command::Start(continuous.clone()))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        service
            .emit_signal(
                None::<&str>,
                PATH,
                "org.freedesktop.portal.GlobalShortcuts",
                "Activated",
                &activation,
            )
            .await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;

        // A short manual run can finish before an old activation arrives.
        // It must not turn that delayed activation into another start request.
        worker.send(Command::Start(settings.clone()))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        service
            .emit_signal(
                None::<&str>,
                PATH,
                "org.freedesktop.portal.GlobalShortcuts",
                "Activated",
                &activation,
            )
            .await?;
        sleep(Duration::from_millis(120)).await;
        while let Ok(event) = events.try_recv() {
            assert!(!matches!(event, WorkerEvent::StartRequested(_)),
                "a delayed activation must not restart a completed manual run");
        }

        // The delayed key release rearms the shortcut. A later press can start.
        service
            .emit_signal(
                None::<&str>,
                PATH,
                "org.freedesktop.portal.GlobalShortcuts",
                "Deactivated",
                &activation,
            )
            .await?;
        sleep(Duration::from_millis(20)).await;
        service
            .emit_signal(
                None::<&str>,
                PATH,
                "org.freedesktop.portal.GlobalShortcuts",
                "Activated",
                &activation,
            )
            .await?;
        let pending_start = event(&mut events, |e| matches!(e, WorkerEvent::StartRequested(_))).await?;
        let WorkerEvent::StartRequested(pending_generation) = pending_start else {
            unreachable!()
        };

        worker.send(Command::Start(ClickSettings {
            repeat: None,
            ..settings.clone()
        }))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        service
            .emit_signal(
                None::<&str>,
                PATH,
                "org.freedesktop.portal.GlobalShortcuts",
                "Activated",
                &activation,
            )
            .await?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(false))).await?;
        assert!(!worker.accepts_hotkey_start(pending_generation),
            "a hotkey stop must invalidate earlier Qt start callbacks");
        worker.send(Command::Start(ClickSettings {
            repeat: None,
            ..settings
        }))?;
        event(&mut events, |e| matches!(e, WorkerEvent::Running(true))).await?;
        let session = observed
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .hotkey_session
            .clone();
        service
            .emit_signal(
                None::<&str>,
                session.as_str(),
                "org.freedesktop.portal.Session",
                "Closed",
                &(Options::new(),),
            )
            .await?;
        event(
            &mut events,
            |e| matches!(e, WorkerEvent::Error(message) if message.contains("Hotkey-Sitzung")),
        )
        .await?;
        let count = observed
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .buttons
            .len();
        sleep(Duration::from_millis(40)).await;
        assert_eq!(
            observed
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .buttons
                .len(),
            count
        );
        // Cover both permission dialogs, with responsive and stalled Session.Close.
        for hotkey_pending in [true, false] {
            for stall_close in [false, true] {
                let (seen, release, closed_before) = {
                    let mut state = observed.lock().unwrap_or_else(|e| e.into_inner());
                    state.delay_hotkey = hotkey_pending;
                    state.delay_start = !hotkey_pending;
                    state.stall_close = stall_close;
                    let (seen, release) = if hotkey_pending {
                        (state.hotkey_seen.clone(), state.hotkey_release.clone())
                    } else {
                        (state.start_seen.clone(), state.start_release.clone())
                    };
                    (seen, release, state.closed)
                };
                let (tx, mut pending_events) = mpsc::unbounded_channel();
                let settings = ClickSettings {
                    interval_ms: 100, button: MouseButton::Left, click_type: ClickType::Single,
                    repeat: Some(1), position: None, monitor: None,
                };
                let pending_worker = WorkerHandle::spawn(settings.clone(), "Pause".into(), move |event| {
                    let _ = tx.send(event);
                });
                if !hotkey_pending {
                    event(&mut pending_events, |e| matches!(e, WorkerEvent::Hotkey(_))).await?;
                    pending_worker.send(Command::Start(settings))?;
                }
                timeout(Duration::from_secs(3), seen.notified()).await?;
                let owner = {
                    let state = observed.lock().unwrap_or_else(|e| e.into_inner());
                    if hotkey_pending { state.hotkey_owner.clone() } else { state.remote_owner.clone() }
                };
                let before = std::time::Instant::now();
                timeout(Duration::from_secs(4), tokio::task::spawn_blocking(move || pending_worker.shutdown())).await??;
                eprintln!("Pending {} shutdown, stalled Close={stall_close}: {:?}",
                    if hotkey_pending { "hotkey" } else { "mouse" }, before.elapsed());
                assert!(observed.lock().unwrap_or_else(|e| e.into_inner()).closed > closed_before,
                    "Shutdown must close its pending permission session");
                let bus = zbus::fdo::DBusProxy::new(&service).await?;
                assert!(!bus.name_has_owner(owner.as_str().try_into()?).await?,
                    "Permission owner must disconnect even when Session.Close stalls");
                release.notify_one();
                // Mouse shutdown also closes the hotkey session. Give every
                // stalled close its own retained permit, including late waiters.
                let close_releases = std::mem::take(
                    &mut observed.lock().unwrap_or_else(|e| e.into_inner()).close_releases,
                );
                for close_release in close_releases {
                    close_release.notify_one();
                }
                sleep(Duration::from_millis(30)).await;
                while let Ok(event) = pending_events.try_recv() {
                    assert!(!matches!(event, WorkerEvent::Running(true)),
                        "A late permission response must not start clicking");
                }
                observed.lock().unwrap_or_else(|e| e.into_inner()).stall_close = false;
            }
        }
        Ok(())
    }
    .await;
    tokio::task::spawn_blocking(move || worker.shutdown()).await?;
    assert!(observed.lock().unwrap_or_else(|e| e.into_inner()).closed >= 1);
    result?;
    service.close().await?;
    Ok(())
}
