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
    sync::mpsc,
    task::JoinHandle,
    time::{Instant, sleep_until, timeout},
};

use crate::{
    model::ClickSettings,
    portal::PortalClickSession,
    scheduler::Schedule,
    state::{RunState, StateMachine},
};

const COMMAND_CAPACITY: usize = 16;
const PORTAL_CLOSE_TIMEOUT: Duration = Duration::from_secs(1);
const HOTKEY_ID: &str = "toggle-clicking";

/// Commands sent from the main thread to the worker thread.
#[derive(Debug)]
pub enum Command {
    Start(ClickSettings),
    Stop,
    ConfigureHotkey,
    Shutdown,
}

/// Events sent from the worker thread to the main UI thread.
#[derive(Debug, Clone)]
pub enum WorkerEvent {
    Status(String),
    Running(bool),
    Hotkey(String),
    Error(String),
}

/// Handle to the worker thread for sending commands and managing lifecycle.
pub struct WorkerHandle {
    tx: mpsc::Sender<Command>,
    closing: Arc<AtomicBool>,
    join: Option<thread::JoinHandle<()>>,
}

impl WorkerHandle {
    /// Spawns a new worker thread.
    ///
    /// The worker manages portal connections, global hotkey bindings, and click scheduling.
    /// Events are sent back to the UI via the provided `emit` callback.
    pub fn spawn<F>(initial: ClickSettings, preferred_hotkey: String, emit: F) -> Self
    where
        F: Fn(WorkerEvent) + Send + Sync + 'static,
    {
        let (tx, rx) = mpsc::channel(COMMAND_CAPACITY);
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
        Self { tx, closing, join }
    }

    /// Sends a command to the worker thread.
    ///
    /// Returns an error if the worker is shutting down or the command queue is full.
    pub fn send(&self, command: Command) -> Result<(), &'static str> {
        if self.closing.load(Ordering::Acquire) {
            return Err("Die Anwendung wird bereits beendet.");
        }
        self.tx
            .try_send(command)
            .map_err(|_| "Der interne Befehlskanal ist ausgelastet.")
    }

    /// Initiates shutdown and blocks until the worker thread exits.
    pub fn shutdown(mut self) {
        if !self.closing.swap(true, Ordering::AcqRel) {
            let _ = self.tx.blocking_send(Command::Shutdown);
        }
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}

impl Drop for WorkerHandle {
    fn drop(&mut self) {
        if !self.closing.swap(true, Ordering::AcqRel) {
            let _ = self.tx.try_send(Command::Shutdown);
        }
        // Rust does not wait for detached threads at process exit. Explicit
        // shutdown joins in the window closing handler.
    }
}

struct HotkeyState {
    portal: Arc<GlobalShortcuts>,
    session: Arc<Session<GlobalShortcuts>>,
    events: Pin<Box<dyn Stream<Item = HotkeySignal> + Send>>,
}

enum HotkeySignal {
    Activated(Activated),
    Changed(ShortcutsChanged),
}

struct ActiveRun {
    settings: ClickSettings,
    schedule: Schedule,
    next_tick: Instant,
}

type Emitter = Arc<dyn Fn(WorkerEvent) + Send + Sync>;

/// Sets up a global shortcut through the XDG GlobalShortcuts portal.
///
/// Requests the user's preferred hotkey and returns the actual bound key.
async fn setup_hotkey(
    preferred_hotkey: String,
) -> Result<(GlobalShortcuts, Session<GlobalShortcuts>, String), String> {
    let portal = GlobalShortcuts::new()
        .await
        .map_err(|error| format!("GlobalShortcuts-Portal nicht verfügbar: {error}"))?;
    let session = portal
        .create_session(Default::default())
        .await
        .map_err(|error| format!("Hotkey-Sitzung konnte nicht erstellt werden: {error}"))?;
    let shortcut = NewShortcut::new(HOTKEY_ID, "Auto Clicker starten oder stoppen")
        .preferred_trigger(Some(preferred_hotkey.as_str()));
    let response = portal
        .bind_shortcuts(&session, &[shortcut], None, BindShortcutsOptions::default())
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
    Ok((portal, session, actual))
}

/// Creates a portal session for sending mouse clicks.
async fn setup_click_session(fixed: bool) -> Result<PortalClickSession, String> {
    PortalClickSession::create(fixed)
        .await
        .map_err(|error| error.to_string())
}

/// Sleeps until the next scheduled tick, or waits indefinitely if no deadline is set.
async fn wait_for_tick(deadline: Option<Instant>) {
    match deadline {
        Some(deadline) => sleep_until(deadline).await,
        None => future::pending().await,
    }
}

/// Waits for the next hotkey event from the stream, or waits indefinitely if no stream exists.
async fn next_hotkey(stream: &mut Option<HotkeyState>) -> Option<HotkeySignal> {
    match stream {
        Some(state) => state.events.next().await,
        None => future::pending().await,
    }
}

/// Waits for a task to complete, or waits indefinitely if the task handle is None.
async fn wait_task<T>(task: &mut Option<JoinHandle<T>>) -> Result<T, tokio::task::JoinError> {
    match task {
        Some(task) => task.await,
        None => future::pending().await,
    }
}

/// Main worker thread event loop.
///
/// Manages portal connections, hotkey bindings, click scheduling, and command processing.
/// Runs until a shutdown command is received or the command channel closes.
async fn run_worker(
    mut commands: mpsc::Receiver<Command>,
    mut latest_settings: ClickSettings,
    preferred_hotkey: String,
    emit: Emitter,
    closing: Arc<AtomicBool>,
) {
    let mut machine = StateMachine::default();
    let mut click_session: Option<PortalClickSession> = None;
    let mut active: Option<ActiveRun> = None;
    let mut start_task: Option<JoinHandle<Result<PortalClickSession, String>>> = None;
    let mut hotkey_task = Some(tokio::spawn(setup_hotkey(preferred_hotkey)));
    let mut configure_task: Option<JoinHandle<Result<(), String>>> = None;
    let mut hotkey: Option<HotkeyState> = None;

    (emit)(WorkerEvent::Status(
        "Bereit – Hotkey wird eingerichtet …".to_owned(),
    ));

    loop {
        let tick_deadline = active.as_ref().map(|run| run.next_tick);
        tokio::select! {
            command = commands.recv() => {
                let Some(command) = command else { break; };
                match command {
                    Command::Start(settings) => {
                        latest_settings = settings.clone();
                        if hotkey.is_none() {
                            (emit)(WorkerEvent::Error("Vor dem Start muss der globale Stop-Hotkey von KWin bestätigt sein.".to_owned()));
                            continue;
                        }
                        if let Err(error) = settings.validate() {
                            machine.fail();
                            (emit)(WorkerEvent::Error(error.to_string()));
                            continue;
                        }
                        if !machine.request_start() {
                            continue;
                        }
                        let needs_fixed = settings.position.is_some();
                        if click_session.as_ref().is_some_and(|session| session.supports_fixed_position() == needs_fixed) {
                            start_run(&mut machine, &mut active, settings, &emit);
                        } else {
                            if let Some(old_session) = click_session.take() {
                                let _ = timeout(PORTAL_CLOSE_TIMEOUT, old_session.close()).await;
                            }
                            (emit)(WorkerEvent::Status("Warte auf Wayland-Berechtigung …".to_owned()));
                            start_task = Some(tokio::spawn(setup_click_session(needs_fixed)));
                        }
                    }
                    Command::Stop => {
                        if let Some(task) = start_task.take() {
                            task.abort();
                        }
                        stop_run(&mut machine, &mut active, &emit);
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
                    Command::Shutdown => break,
                }
            }
            result = wait_task(&mut start_task), if start_task.is_some() => {
                start_task = None;
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
                        (emit)(WorkerEvent::Error(format!("Portal-Aufgabe ist fehlgeschlagen: {error}")));
                    }
                }
            }
            result = wait_task(&mut hotkey_task), if hotkey_task.is_some() => {
                hotkey_task = None;
                match result {
                    Ok(Ok((portal, session, actual))) => {
                        let activation_stream = portal.receive_activated().await;
                        let changed_stream = portal.receive_shortcuts_changed().await;
                        match (activation_stream, changed_stream) {
                            (Ok(activations), Ok(changes)) => {
                                let events = futures_util::stream::select(
                                    activations.map(HotkeySignal::Activated),
                                    changes.map(HotkeySignal::Changed),
                                );
                                hotkey = Some(HotkeyState {
                                    portal: Arc::new(portal),
                                    session: Arc::new(session),
                                    events: Box::pin(events),
                                });
                                (emit)(WorkerEvent::Hotkey(actual));
                                if machine.state() == RunState::Ready {
                                    (emit)(WorkerEvent::Status("Bereit".to_owned()));
                                }
                            }
                            (Err(error), _) | (_, Err(error)) => (emit)(WorkerEvent::Error(format!("Hotkey-Signale sind nicht verfügbar: {error}"))),
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
                            if let Some(task) = start_task.take() { task.abort(); }
                            stop_run(&mut machine, &mut active, &emit);
                        } else if latest_settings.validate().is_ok() && machine.request_start() {
                            let needs_fixed = latest_settings.position.is_some();
                            if click_session.as_ref().is_some_and(|session| session.supports_fixed_position() == needs_fixed) {
                                start_run(&mut machine, &mut active, latest_settings.clone(), &emit);
                            } else {
                                if let Some(old_session) = click_session.take() {
                                    let _ = timeout(PORTAL_CLOSE_TIMEOUT, old_session.close()).await;
                                }
                                (emit)(WorkerEvent::Status("Warte auf Wayland-Berechtigung …".to_owned()));
                                start_task = Some(tokio::spawn(setup_click_session(needs_fixed)));
                            }
                        }
                    }
                    Some(HotkeySignal::Changed(changed)) => {
                        if let Some(shortcut) = changed.shortcuts().iter().find(|shortcut| shortcut.id() == HOTKEY_ID) {
                            (emit)(WorkerEvent::Hotkey(shortcut.trigger_description().to_owned()));
                        } else {
                            stop_run(&mut machine, &mut active, &emit);
                            machine.fail();
                            if let Some(state) = hotkey.take() {
                                let _ = timeout(PORTAL_CLOSE_TIMEOUT, state.session.close()).await;
                            }
                            (emit)(WorkerEvent::Error("Der globale Stop-Hotkey wurde entfernt.".to_owned()));
                        }
                    }
                    Some(HotkeySignal::Activated(_)) => {}
                    None => {
                        stop_run(&mut machine, &mut active, &emit);
                        machine.fail();
                        (emit)(WorkerEvent::Error("Die globale Hotkey-Sitzung wurde beendet.".to_owned()));
                        hotkey = None;
                    }
                }
            }
            () = wait_for_tick(tick_deadline), if active.is_some() => {
                let Some(run) = active.as_mut() else { continue; };
                let Some(session) = click_session.as_ref() else {
                    machine.fail();
                    active = None;
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
    if let Some(task) = start_task {
        task.abort();
    }
    if let Some(task) = hotkey_task {
        task.abort();
    }
    if let Some(task) = configure_task {
        task.abort();
    }
    if let Some(session) = click_session {
        let _ = timeout(PORTAL_CLOSE_TIMEOUT, session.close()).await;
    }
    if let Some(state) = hotkey {
        let _ = timeout(PORTAL_CLOSE_TIMEOUT, state.session.close()).await;
    }
    (emit)(WorkerEvent::Running(false));
}

/// Initiates a new clicking run with the given settings.
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

/// Stops the currently running click sequence.
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
