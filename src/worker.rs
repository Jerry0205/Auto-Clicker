use std::{
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration,
};

use ashpd::desktop::{
    Session,
    global_shortcuts::{
        Activated, BindShortcutsOptions, ConfigureShortcutsOptions, GlobalShortcuts, NewShortcut,
        ShortcutsChanged,
    },
};
use futures_util::{Stream, StreamExt, future};
use tokio::{
    runtime::Builder,
    sync::{mpsc, oneshot, watch},
    task::JoinHandle,
    time::{Instant, sleep_until, timeout},
};

use crate::{
    model::{ClickSettings, MonitorGeometry, ValidationError},
    portal::PortalClickSession,
    scheduler::Schedule,
    state::{RunState, StateMachine},
};

const COMMAND_CAPACITY: usize = 16;
const PORTAL_CLOSE_TIMEOUT: Duration = Duration::from_secs(1);
const HOTKEY_ID: &str = "toggle-clicking";

#[derive(Debug)]
pub enum Command {
    Start(ClickSettings),
    Stop,
    ConfigureHotkey,
    CaptureScreenshot(i32),
    CancelScreenshot(i32),
    Shutdown,
}

#[derive(Debug, Clone)]
pub enum WorkerEvent {
    Status(String),
    Running(bool),
    Hotkey(String),
    StartRequested,
    Screenshot(i32, Result<String, String>),
    Error(String),
}

pub struct WorkerHandle {
    tx: mpsc::Sender<QueuedCommand>,
    control: watch::Sender<ControlState>,
    closing: Arc<AtomicBool>,
    join: Option<thread::JoinHandle<()>>,
}

#[derive(Clone, Copy, Default)]
struct ControlState {
    generation: u64,
    shutdown: bool,
}

struct QueuedCommand {
    command: Command,
    generation: u64,
}

impl WorkerHandle {
    pub fn spawn<F>(initial: ClickSettings, preferred_hotkey: String, emit: F) -> Self
    where
        F: Fn(WorkerEvent) + Send + Sync + 'static,
    {
        let (tx, rx) = mpsc::channel(COMMAND_CAPACITY);
        let (control, control_rx) = watch::channel(ControlState::default());
        let closing = Arc::new(AtomicBool::new(false));
        let worker_closing = Arc::clone(&closing);
        let emit = Arc::new(emit);
        let join = thread::Builder::new()
            .name("klickmeister-worker".to_owned())
            .spawn(move || {
                let runtime = Builder::new_current_thread().enable_all().build();
                match runtime {
                    Ok(runtime) => runtime.block_on(run_worker(
                        rx,
                        control_rx,
                        initial,
                        preferred_hotkey,
                        emit,
                        worker_closing,
                    )),
                    Err(error) => {
                        // Runtime construction only fails for OS resource exhaustion.
                        eprintln!("Klickmeister worker runtime failed: {error}");
                    }
                }
            })
            .ok();
        Self {
            tx,
            control,
            closing,
            join,
        }
    }

    pub fn send(&self, command: Command) -> Result<(), &'static str> {
        if self.closing.load(Ordering::Acquire) {
            return Err("Die Anwendung wird bereits beendet.");
        }
        if self.control.is_closed() {
            return Err("Der Hintergrund-Worker ist nicht mehr erreichbar.");
        }
        if matches!(command, Command::Stop) {
            self.control.send_modify(|state| {
                state.generation = state.generation.wrapping_add(1);
            });
            return Ok(());
        }
        if matches!(command, Command::Shutdown) {
            self.request_shutdown();
            return Ok(());
        }
        let generation = self.control.borrow().generation;
        self.tx
            .try_send(QueuedCommand {
                command,
                generation,
            })
            .map_err(|error| match error {
                mpsc::error::TrySendError::Full(_) => "Der interne Befehlskanal ist ausgelastet.",
                mpsc::error::TrySendError::Closed(_) => {
                    "Der Hintergrund-Worker ist nicht mehr erreichbar."
                }
            })
    }

    pub fn shutdown(mut self) {
        self.request_shutdown();
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }

    fn request_shutdown(&self) {
        if !self.closing.swap(true, Ordering::AcqRel) {
            self.control.send_modify(|state| {
                state.generation = state.generation.wrapping_add(1);
                state.shutdown = true;
            });
        }
    }
}

impl Drop for WorkerHandle {
    fn drop(&mut self) {
        self.request_shutdown();
    }
}

struct HotkeyState {
    connection: ashpd::zbus::Connection,
    portal: Arc<GlobalShortcuts>,
    session: Arc<Session<GlobalShortcuts>>,
    events: Pin<Box<dyn Stream<Item = HotkeySignal> + Send>>,
}

enum HotkeySignal {
    Activated(Activated),
    Changed(ShortcutsChanged),
    Closed,
}

struct ActiveRun {
    settings: ClickSettings,
    schedule: Schedule,
    next_tick: Instant,
}

type Emitter = Arc<dyn Fn(WorkerEvent) + Send + Sync>;

struct HotkeyRegistration {
    connection: ashpd::zbus::Connection,
    portal: GlobalShortcuts,
    session: Session<GlobalShortcuts>,
    actual: String,
}

/// Bind the stop hotkey on an owned connection and clean up failed or cancelled requests.
async fn setup_hotkey(
    preferred_hotkey: String,
    mut cancel: oneshot::Receiver<()>,
) -> Result<HotkeyRegistration, String> {
    let connection = tokio::select! {
        biased;
        _ = &mut cancel => return Err("Hotkey-Anfrage abgebrochen.".to_owned()),
        result = ashpd::zbus::Connection::session() => result.map_err(|error| error.to_string())?,
    };
    let mut session = None;
    let operation = async {
        let portal = GlobalShortcuts::with_connection(connection.clone())
            .await
            .map_err(|error| format!("GlobalShortcuts-Portal nicht verfügbar: {error}"))?;
        session = Some(
            portal
                .create_session(Default::default())
                .await
                .map_err(|error| format!("Hotkey-Sitzung konnte nicht erstellt werden: {error}"))?,
        );
        let owned_session = session.as_ref().ok_or("Hotkey-Sitzung fehlt.")?;
        let shortcut = NewShortcut::new(HOTKEY_ID, "Auto Clicker starten oder stoppen")
            .preferred_trigger(Some(preferred_hotkey.as_str()));
        let response = portal
            .bind_shortcuts(
                owned_session,
                &[shortcut],
                None,
                BindShortcutsOptions::default(),
            )
            .await
            .map_err(|error| format!("Hotkey konnte nicht angefragt werden: {error}"))?
            .response()
            .map_err(|error| format!("Hotkey wurde nicht freigegeben: {error}"))?;
        let actual = response
            .shortcuts()
            .iter()
            .find(|shortcut| shortcut.id() == HOTKEY_ID)
            .map(|shortcut| shortcut.trigger_description().to_owned())
            .ok_or_else(|| "KWin hat keinen globalen Hotkey gebunden.".to_owned())?;
        Ok((portal, actual))
    };
    let result = tokio::select! {
        biased;
        _ = &mut cancel => Err("Hotkey-Anfrage abgebrochen.".to_owned()),
        result = operation => result,
    };
    match result {
        Ok((portal, actual)) => Ok(HotkeyRegistration {
            connection,
            portal,
            actual,
            session: session.ok_or("Hotkey-Sitzung fehlt.")?,
        }),
        Err(error) => {
            if let Some(session) = session {
                let _ = timeout(PORTAL_CLOSE_TIMEOUT, session.close()).await;
            }
            let _ = timeout(PORTAL_CLOSE_TIMEOUT, connection.close()).await;
            Err(error)
        }
    }
}

/// Cancel registration and close even a session completed just before cancellation.
async fn cancel_hotkey(
    task: &mut Option<JoinHandle<Result<HotkeyRegistration, String>>>,
    cancel: &mut Option<oneshot::Sender<()>>,
) {
    if let Some(cancel) = cancel.take() {
        let _ = cancel.send(());
    }
    if let Some(task) = task.take()
        && let Ok(Ok(registration)) = task.await
    {
        let _ = timeout(PORTAL_CLOSE_TIMEOUT, registration.session.close()).await;
        let _ = timeout(PORTAL_CLOSE_TIMEOUT, registration.connection.close()).await;
    }
}

/// Signal cancellation and allow the capture owner to close its portal handle.
async fn cancel_capture(
    task: &mut Option<JoinHandle<Result<String, String>>>,
    cancel: &mut Option<oneshot::Sender<()>>,
) {
    if let Some(cancel) = cancel.take() {
        let _ = cancel.send(());
    }
    if let Some(task) = task.take() {
        // Screenshot cleanup has its own bounded Close and disconnect calls.
        let _ = task.await;
    }
}

/// Keep the owner alive until its pending dialog/session has been closed.
async fn cancel_start(
    task: &mut Option<JoinHandle<Result<PortalClickSession, String>>>,
    cancel: &mut Option<oneshot::Sender<()>>,
) {
    if let Some(cancel) = cancel.take() {
        let _ = cancel.send(());
    }
    if let Some(task) = task.take()
        && let Ok(Ok(session)) = task.await
    {
        // The permission may have completed just before cancellation.
        session.close().await;
    }
}

/// Create a portal session for the selected monitor or current cursor.
async fn setup_click_session(
    monitor: Option<MonitorGeometry>,
    cancel: oneshot::Receiver<()>,
) -> Result<PortalClickSession, String> {
    PortalClickSession::create(monitor, cancel)
        .await
        .map_err(|error| error.to_string())
}

async fn wait_for_tick(deadline: Option<Instant>) {
    match deadline {
        Some(deadline) => sleep_until(deadline).await,
        None => future::pending().await,
    }
}

async fn next_hotkey(stream: &mut Option<HotkeyState>) -> Option<HotkeySignal> {
    match stream {
        Some(state) => state.events.next().await,
        None => future::pending().await,
    }
}

async fn wait_task<T>(task: &mut Option<JoinHandle<T>>) -> Result<T, tokio::task::JoinError> {
    match task {
        Some(task) => task.await,
        None => future::pending().await,
    }
}

/// Bound signal registration without limiting the subsequent session lifetime.
async fn register_hotkey_watcher(
    ready: oneshot::Receiver<()>,
    closed: impl std::future::Future<Output = HotkeySignal>,
) -> bool {
    timeout(PORTAL_CLOSE_TIMEOUT, async {
        tokio::select! {
            result = ready => result.is_ok(),
            _ = closed => false,
        }
    })
    .await
    .unwrap_or(false)
}

/// Serialize clicks, permissions, shortcut events and cancellable captures.
async fn run_worker(
    mut commands: mpsc::Receiver<QueuedCommand>,
    mut control: watch::Receiver<ControlState>,
    mut latest_settings: ClickSettings,
    preferred_hotkey: String,
    emit: Emitter,
    closing: Arc<AtomicBool>,
) {
    let mut machine = StateMachine::default();
    let mut click_session: Option<PortalClickSession> = None;
    let mut active: Option<ActiveRun> = None;
    let mut start_task: Option<JoinHandle<Result<PortalClickSession, String>>> = None;
    let mut start_cancel = None;
    let (tx, rx) = oneshot::channel();
    let mut hotkey_cancel = Some(tx);
    let mut hotkey_task = Some(tokio::spawn(setup_hotkey(preferred_hotkey, rx)));
    let mut configure_task: Option<JoinHandle<Result<(), String>>> = None;
    let mut hotkey: Option<HotkeyState> = None;
    let mut screenshot_task: Option<JoinHandle<Result<String, String>>> = None;
    let mut screenshot_id = 0;
    let mut screenshot_cancel = None;

    (emit)(WorkerEvent::Status(
        "Bereit – Hotkey wird eingerichtet …".to_owned(),
    ));

    loop {
        let tick_deadline = active.as_ref().map(|run| run.next_tick);
        tokio::select! {
            biased;
            changed = control.changed() => {
                if changed.is_err() || control.borrow().shutdown {
                    break;
                }
                cancel_start(&mut start_task, &mut start_cancel).await;
                stop_run(&mut machine, &mut active, &emit);
            }
            queued = commands.recv() => {
                let Some(QueuedCommand { command, generation }) = queued else { break; };
                match command {
                    Command::Start(settings) => {
                        if generation != control.borrow().generation {
                            continue;
                        }
                        if hotkey.is_none() {
                            (emit)(WorkerEvent::Error("Vor dem Start muss der globale Stop-Hotkey von KWin bestätigt sein.".to_owned()));
                            continue;
                        }
                        match request_validated_start(&mut machine, &settings) {
                            Ok(true) => latest_settings = settings.clone(),
                            Ok(false) => continue,
                            Err(error) => {
                                (emit)(WorkerEvent::Error(error.to_string()));
                                continue;
                            }
                        }
                        if click_session.as_ref().is_some_and(|session| session.matches_monitor(settings.monitor)) {
                            start_run(&mut machine, &mut active, settings, &emit);
                        } else {
                            if let Some(old_session) = click_session.take() {
                                old_session.close().await;
                            }
                            (emit)(WorkerEvent::Status("Warte auf Wayland-Berechtigung …".to_owned()));
                            let (tx, rx) = oneshot::channel();
                            start_cancel = Some(tx);
                            start_task = Some(tokio::spawn(setup_click_session(settings.monitor, rx)));
                        }
                    }
                    Command::CaptureScreenshot(request_id) => {
                        cancel_capture(&mut screenshot_task, &mut screenshot_cancel).await;
                        screenshot_id = request_id;
                        let (tx, rx) = oneshot::channel();
                        screenshot_cancel = Some(tx);
                        screenshot_task = Some(tokio::spawn(crate::screenshot::capture(rx)));
                    }
                    Command::CancelScreenshot(request_id) => {
                        if request_id == screenshot_id {
                            cancel_capture(&mut screenshot_task, &mut screenshot_cancel).await;
                        }
                    }
                    Command::ConfigureHotkey => {
                        if configure_task.is_some() {
                            continue;
                        }
                        if let Some(state) = &hotkey {
                            let portal = Arc::clone(&state.portal);
                            let session = Arc::clone(&state.session);
                            configure_task = Some(tokio::spawn(async move {
                                portal
                                    .configure_shortcuts(
                                        &session,
                                        None,
                                        ConfigureShortcutsOptions::default(),
                                    )
                                    .await
                                    .map_err(|error| format!("Hotkey-Dialog konnte nicht geöffnet werden: {error}"))
                            }));
                        } else {
                            (emit)(WorkerEvent::Error("Der globale Hotkey ist noch nicht verfügbar.".to_owned()));
                        }
                    }
                    Command::Stop | Command::Shutdown => unreachable!("control commands bypass the bounded queue"),
                }
            }
            result = wait_task(&mut screenshot_task), if screenshot_task.is_some() => {
                screenshot_task = None;
                screenshot_cancel = None;
                (emit)(WorkerEvent::Screenshot(screenshot_id, result.unwrap_or_else(|error| Err(error.to_string()))));
            }
            result = wait_task(&mut start_task), if start_task.is_some() => {
                start_task = None;
                start_cancel = None;
                match result {
                    Ok(Ok(session)) => {
                        click_session = Some(session);
                        start_run(&mut machine, &mut active, latest_settings.clone(), &emit);
                    }
                    Ok(Err(error)) => {
                        machine.fail();
                        (emit)(WorkerEvent::Running(false));
                        (emit)(WorkerEvent::Error(error));
                    }
                    Err(error) if error.is_cancelled() => {
                        stop_run(&mut machine, &mut active, &emit);
                    }
                    Err(error) => {
                        machine.fail();
                        (emit)(WorkerEvent::Running(false));
                        (emit)(WorkerEvent::Error(format!("Portal-Aufgabe ist fehlgeschlagen: {error}")));
                    }
                }
            }
            result = wait_task(&mut hotkey_task), if hotkey_task.is_some() => {
                hotkey_task = None;
                hotkey_cancel = None;
                match result {
                    Ok(Ok(HotkeyRegistration { connection, portal, session, actual })) => {
                        let streams = timeout(PORTAL_CLOSE_TIMEOUT, async {
                            let activations = portal.receive_activated().await.map_err(|error| error.to_string())?;
                            let changes = portal.receive_shortcuts_changed().await.map_err(|error| error.to_string())?;
                            Ok::<_, String>((activations, changes))
                        }).await;
                        match streams {
                            Ok(Ok((activations, changes))) => {
                                let session = Arc::new(session);
                                let watched_session = Arc::clone(&session);
                                let (ready_tx, ready_rx) = oneshot::channel();
                                let mut closed = Box::pin(async move {
                                    if let Ok(events) = watched_session.receive_closed().await {
                                        let _ = ready_tx.send(());
                                        futures_util::pin_mut!(events);
                                        let _ = events.next().await;
                                    }
                                    HotkeySignal::Closed
                                });
                                // Register the Closed signal before any start can be accepted.
                                let watching = register_hotkey_watcher(ready_rx, &mut closed).await;
                                if !watching {
                                    let _ = timeout(PORTAL_CLOSE_TIMEOUT, session.close()).await;
                                    let _ = timeout(PORTAL_CLOSE_TIMEOUT, connection.close()).await;
                                    (emit)(WorkerEvent::Error("Die Hotkey-Sitzung kann nicht überwacht werden.".to_owned()));
                                    continue;
                                }
                                let events = futures_util::stream::select(
                                    futures_util::stream::select(
                                        activations.map(HotkeySignal::Activated),
                                        changes.map(HotkeySignal::Changed),
                                    ),
                                    futures_util::stream::once(closed),
                                );
                                hotkey = Some(HotkeyState {
                                    connection,
                                    portal: Arc::new(portal),
                                    session,
                                    events: Box::pin(events),
                                });
                                (emit)(WorkerEvent::Hotkey(actual));
                                if machine.state() == RunState::Ready {
                                    (emit)(WorkerEvent::Status("Bereit".to_owned()));
                                }
                            }
                            result => {
                                let _ = timeout(PORTAL_CLOSE_TIMEOUT, session.close()).await;
                                let _ = timeout(PORTAL_CLOSE_TIMEOUT, connection.close()).await;
                                let error = match result {
                                    Ok(Err(error)) => error,
                                    Err(_) => "Zeitüberschreitung bei der Hotkey-Signalanmeldung".to_owned(),
                                    Ok(Ok(_)) => unreachable!(),
                                };
                                (emit)(WorkerEvent::Error(format!("Hotkey-Signale sind nicht verfügbar: {error}")));
                            }
                        }
                    }
                    Ok(Err(error)) => (emit)(WorkerEvent::Error(error)),
                    Err(error) if !error.is_cancelled() => (emit)(WorkerEvent::Error(format!("Hotkey-Aufgabe ist fehlgeschlagen: {error}"))),
                    Err(_) => {}
                }
            }
            result = wait_task(&mut configure_task), if configure_task.is_some() => {
                configure_task = None;
                match result {
                    Ok(Ok(())) => {}
                    Ok(Err(error)) => {
                        stop_run(&mut machine, &mut active, &emit);
                        machine.fail();
                        (emit)(WorkerEvent::Error(error));
                    }
                    Err(error) if !error.is_cancelled() => {
                        stop_run(&mut machine, &mut active, &emit);
                        machine.fail();
                        (emit)(WorkerEvent::Error(format!("Hotkey-Dialog ist fehlgeschlagen: {error}")));
                    }
                    Err(_) => {}
                }
            }
            hotkey_event = next_hotkey(&mut hotkey), if hotkey.is_some() => {
                match hotkey_event {
                    Some(HotkeySignal::Activated(activation)) if activation.shortcut_id() == HOTKEY_ID => {
                        if matches!(machine.state(), RunState::Starting | RunState::Clicking) {
                            cancel_start(&mut start_task, &mut start_cancel).await;
                            stop_run(&mut machine, &mut active, &emit);
                        } else {
                            // Ask the Qt side to start so the current UI values are
                            // collected, validated and saved. Keeping a settings copy
                            // here made hotkey starts use values from the previous run.
                            (emit)(WorkerEvent::StartRequested);
                        }
                    }
                    Some(HotkeySignal::Changed(changed)) => {
                        if let Some(shortcut) = changed.shortcuts().iter().find(|shortcut| shortcut.id() == HOTKEY_ID) {
                            (emit)(WorkerEvent::Hotkey(shortcut.trigger_description().to_owned()));
                        } else {
                            cancel_start(&mut start_task, &mut start_cancel).await;
                            stop_run(&mut machine, &mut active, &emit);
                            machine.fail();
                            if let Some(state) = hotkey.take() {
                                let _ = timeout(PORTAL_CLOSE_TIMEOUT, state.session.close()).await;
                                let _ = timeout(PORTAL_CLOSE_TIMEOUT, state.connection.close()).await;
                            }
                            (emit)(WorkerEvent::Error("Der globale Stop-Hotkey wurde entfernt.".to_owned()));
                        }
                    }
                    Some(HotkeySignal::Activated(_)) => {}
                    Some(HotkeySignal::Closed) | None => {
                        cancel_start(&mut start_task, &mut start_cancel).await;
                        stop_run(&mut machine, &mut active, &emit);
                        machine.fail();
                        (emit)(WorkerEvent::Error("Die globale Hotkey-Sitzung wurde beendet.".to_owned()));
                        if let Some(state) = hotkey.take() {
                            let _ = timeout(PORTAL_CLOSE_TIMEOUT, state.connection.close()).await;
                        }
                    }
                }
            }
            () = wait_for_tick(tick_deadline), if active.is_some() => {
                let Some(run) = active.as_mut() else { continue; };
                let Some(session) = click_session.as_ref() else {
                    machine.fail();
                    active = None;
                    (emit)(WorkerEvent::Running(false));
                    (emit)(WorkerEvent::Error("Die Wayland-Sitzung wurde unerwartet beendet.".to_owned()));
                    continue;
                };
                if !run.schedule.record_tick() {
                    stop_run(&mut machine, &mut active, &emit);
                    continue;
                }
                if let Err(error) = session.click(&run.settings).await {
                    machine.fail();
                    active = None;
                    (emit)(WorkerEvent::Running(false));
                    (emit)(WorkerEvent::Error(error.to_string()));
                    // A revoked or failed session cannot safely be reused on retry.
                    if let Some(failed_session) = click_session.take() {
                        failed_session.close().await;
                    }
                    continue;
                }
                if run.schedule.is_finished() {
                    stop_run(&mut machine, &mut active, &emit);
                } else {
                    let scheduled = run.next_tick + run.schedule.interval();
                    let now = Instant::now();
                    run.next_tick = if scheduled > now { scheduled } else { now + run.schedule.interval() };
                }
            }
        }
    }

    machine.close();
    closing.store(true, Ordering::Release);
    cancel_capture(&mut screenshot_task, &mut screenshot_cancel).await;
    cancel_start(&mut start_task, &mut start_cancel).await;
    cancel_hotkey(&mut hotkey_task, &mut hotkey_cancel).await;
    if let Some(task) = configure_task {
        task.abort();
    }
    if let Some(session) = click_session {
        session.close().await;
    }
    if let Some(state) = hotkey {
        let _ = timeout(PORTAL_CLOSE_TIMEOUT, state.session.close()).await;
        let _ = timeout(PORTAL_CLOSE_TIMEOUT, state.connection.close()).await;
    }
    (emit)(WorkerEvent::Running(false));
}

/// Ignore duplicate starts before they can change a run or its pending settings.
fn request_validated_start(
    machine: &mut StateMachine,
    settings: &ClickSettings,
) -> Result<bool, ValidationError> {
    if !machine.request_start() {
        return Ok(false);
    }
    if let Err(error) = settings.validate() {
        machine.fail();
        return Err(error);
    }
    Ok(true)
}

fn start_run(
    machine: &mut StateMachine,
    active: &mut Option<ActiveRun>,
    settings: ClickSettings,
    emit: &Emitter,
) {
    if !machine.started() {
        return;
    }
    let schedule = Schedule::new(settings.interval(), settings.repeat);
    let cps = settings.cps();
    *active = Some(ActiveRun {
        settings,
        schedule,
        next_tick: Instant::now(),
    });
    (emit)(WorkerEvent::Running(true));
    (emit)(WorkerEvent::Status(format!("Klickt • {cps:.0} CPS")));
}

fn stop_run(machine: &mut StateMachine, active: &mut Option<ActiveRun>, emit: &Emitter) {
    if machine.stop() {
        *active = None;
        (emit)(WorkerEvent::Running(false));
        (emit)(WorkerEvent::Status("Gestoppt".to_owned()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Hold the worker receiver still so the queue is deterministically full.
    fn stalled_handle(
        capacity: usize,
    ) -> (
        WorkerHandle,
        mpsc::Receiver<QueuedCommand>,
        watch::Receiver<ControlState>,
    ) {
        let (tx, rx) = mpsc::channel(capacity);
        let (control, control_rx) = watch::channel(ControlState::default());
        let handle = WorkerHandle {
            tx,
            control,
            closing: Arc::new(AtomicBool::new(false)),
            join: None,
        };
        (handle, rx, control_rx)
    }

    #[test]
    fn stop_bypasses_full_queue_and_discards_older_starts() {
        let (handle, mut commands, mut control) = stalled_handle(1);
        assert!(handle.send(Command::Start(settings())).is_ok());
        assert!(handle.send(Command::ConfigureHotkey).is_err());

        assert!(handle.send(Command::Stop).is_ok());
        assert!(control.has_changed().is_ok_and(|changed| changed));
        assert_eq!(control.borrow_and_update().generation, 1);
        let old_start = commands.try_recv().unwrap_or_else(|_| unreachable!());
        assert!(matches!(old_start.command, Command::Start(_)));
        assert_ne!(old_start.generation, control.borrow().generation);

        assert!(handle.send(Command::Start(settings())).is_ok());
        let new_start = commands.try_recv().unwrap_or_else(|_| unreachable!());
        assert_eq!(new_start.generation, control.borrow().generation);
    }

    #[test]
    fn shutdown_bypasses_full_queue() {
        let (handle, _commands, control) = stalled_handle(1);
        assert!(handle.send(Command::Start(settings())).is_ok());
        handle.shutdown();
        assert!(control.borrow().shutdown);
    }

    #[tokio::test]
    async fn stalled_hotkey_registration_times_out() {
        let (_ready_tx, ready_rx) = oneshot::channel();
        let result = timeout(
            PORTAL_CLOSE_TIMEOUT * 2,
            register_hotkey_watcher(ready_rx, future::pending()),
        )
        .await;
        assert_eq!(result.ok(), Some(false));
    }

    #[tokio::test]
    async fn registered_hotkey_watcher_still_delivers_session_closure() {
        let (ready_tx, ready_rx) = oneshot::channel();
        let (close_tx, close_rx) = oneshot::channel();
        let mut closed = Box::pin(async move {
            let _ = ready_tx.send(());
            let _ = close_rx.await;
            HotkeySignal::Closed
        });
        assert!(register_hotkey_watcher(ready_rx, &mut closed).await);
        assert!(close_tx.send(()).is_ok());
        assert!(matches!(
            timeout(PORTAL_CLOSE_TIMEOUT, closed).await,
            Ok(HotkeySignal::Closed)
        ));
    }

    #[tokio::test]
    async fn session_closed_before_registration_is_not_ready() {
        let (_ready_tx, ready_rx) = oneshot::channel();
        assert!(!register_hotkey_watcher(ready_rx, async { HotkeySignal::Closed }).await);
    }

    fn settings() -> ClickSettings {
        ClickSettings {
            interval_ms: 100,
            button: crate::model::MouseButton::Left,
            click_type: crate::model::ClickType::Single,
            repeat: Some(3),
            position: None,
            monitor: None,
        }
    }

    #[test]
    fn duplicate_start_keeps_pending_settings_and_active_run_stoppable() {
        for clicking in [false, true] {
            let mut machine = StateMachine::default();
            assert_eq!(request_validated_start(&mut machine, &settings()), Ok(true));
            if clicking {
                assert!(machine.started());
            }
            let expected = machine.state();
            for interval_ms in [0, 250] {
                let duplicate = ClickSettings {
                    interval_ms,
                    ..settings()
                };
                assert_eq!(request_validated_start(&mut machine, &duplicate), Ok(false));
                assert_eq!(machine.state(), expected);
            }
            assert!(machine.stop());
            assert!(!machine.started());
        }
    }

    #[test]
    fn invalid_initial_start_can_be_corrected() {
        let mut machine = StateMachine::default();
        let invalid = ClickSettings {
            interval_ms: 0,
            ..settings()
        };
        assert!(request_validated_start(&mut machine, &invalid).is_err());
        assert_eq!(machine.state(), RunState::Error);
        assert_eq!(request_validated_start(&mut machine, &settings()), Ok(true));
        assert!(machine.started());
    }

    #[test]
    fn failed_portal_connection_leaves_no_active_run() {
        let mut machine = StateMachine::default();
        let active: Option<ActiveRun> = None;
        assert!(machine.request_start());
        machine.fail();
        assert_eq!(machine.state(), RunState::Error);
        assert!(active.is_none());
    }
}
