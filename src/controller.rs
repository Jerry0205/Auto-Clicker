use std::{path::Path, pin::Pin};

use crate::{
    config::{self, AppConfig},
    model::{
        ClickSettings, ClickType, MAX_REPEAT_COUNT, MonitorGeometry, MouseButton, PositionMode,
        RepeatMode, validate_interval,
    },
    worker::{Command, WorkerEvent, WorkerHandle},
};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, status)]
        #[qproperty(QString, error_message)]
        #[qproperty(QString, hotkey)]
        #[qproperty(bool, running)]
        #[qproperty(bool, busy)]
        #[qproperty(i64, interval_ms)]
        #[qproperty(i32, mouse_button)]
        #[qproperty(i32, click_type)]
        #[qproperty(bool, repeat_until_stopped)]
        #[qproperty(i64, repeat_count)]
        #[qproperty(bool, current_position)]
        #[qproperty(i64, fixed_x)]
        #[qproperty(i64, fixed_y)]
        #[qproperty(QString, monitor_identity)]
        #[qproperty(bool, fixed_position_confirmed)]
        #[qproperty(i32, monitor_x)]
        #[qproperty(i32, monitor_y)]
        #[qproperty(i32, monitor_width)]
        #[qproperty(i32, monitor_height)]
        #[qproperty(bool, selecting_position)]
        type AppController = super::AppControllerRust;

        #[qsignal]
        fn screenshot_ready(
            self: Pin<&mut AppController>,
            request_id: i32,
            uri: QString,
            error: QString,
        );

        #[qinvokable]
        fn capture_screenshot(self: Pin<&mut AppController>, request_id: i32);

        #[qinvokable]
        fn cancel_screenshot(self: Pin<&mut AppController>, request_id: i32);

        #[qinvokable]
        fn initialize(self: Pin<&mut AppController>);

        #[qinvokable]
        fn start(self: Pin<&mut AppController>);

        #[qinvokable]
        fn stop(self: Pin<&mut AppController>);

        #[qinvokable]
        fn toggle(self: Pin<&mut AppController>);

        #[qinvokable]
        fn configure_hotkey(self: Pin<&mut AppController>);

        #[qinvokable]
        fn clear_error(self: Pin<&mut AppController>);

        #[qinvokable]
        fn save_config(self: Pin<&mut AppController>) -> bool;

        #[qinvokable]
        fn mark_settings_changed(self: Pin<&mut AppController>);

        #[qinvokable]
        fn shutdown(self: Pin<&mut AppController>);
    }

    impl cxx_qt::Threading for AppController {}
}

pub struct AppControllerRust {
    status: QString,
    error_message: QString,
    hotkey: QString,
    running: bool,
    busy: bool,
    interval_ms: i64,
    mouse_button: i32,
    click_type: i32,
    repeat_until_stopped: bool,
    repeat_count: i64,
    current_position: bool,
    fixed_x: i64,
    fixed_y: i64,
    monitor_identity: QString,
    fixed_position_confirmed: bool,
    monitor_x: i32,
    monitor_y: i32,
    monitor_width: i32,
    monitor_height: i32,
    selecting_position: bool,
    worker: Option<WorkerHandle>,
    worker_epoch: u64,
    startup_error: Option<String>,
    initial_config: AppConfig,
    config_dirty: bool,
}

impl Default for AppControllerRust {
    /// Load saved controls while requiring fixed-position monitor restoration.
    fn default() -> Self {
        let (config, startup_error) = match config::load() {
            Ok(config) => (config, None),
            Err(error) => (AppConfig::default(), Some(error.to_string())),
        };
        Self::from_config(config, startup_error)
    }
}

impl AppControllerRust {
    fn from_config(config: AppConfig, startup_error: Option<String>) -> Self {
        Self {
            status: QString::from("Bereit"),
            error_message: QString::default(),
            hotkey: QString::from(&config.hotkey),
            running: false,
            busy: false,
            interval_ms: i64::try_from(config.interval_ms).unwrap_or(100),
            mouse_button: match config.mouse_button {
                MouseButton::Left => 0,
                MouseButton::Right => 1,
                MouseButton::Middle => 2,
            },
            click_type: match config.click_type {
                ClickType::Single => 0,
                ClickType::Double => 1,
            },
            repeat_until_stopped: config.repeat_mode == RepeatMode::UntilStopped,
            repeat_count: i64::try_from(config.repeat_count).unwrap_or(100),
            current_position: config.position_mode == PositionMode::CurrentCursor,
            fixed_x: i64::from(config.fixed_x),
            fixed_y: i64::from(config.fixed_y),
            monitor_identity: QString::from(&config.monitor_identity),
            fixed_position_confirmed: false,
            monitor_x: 0,
            monitor_y: 0,
            monitor_width: 0,
            monitor_height: 0,
            selecting_position: false,
            worker: None,
            worker_epoch: 0,
            startup_error,
            initial_config: config,
            config_dirty: false,
        }
    }

    /// A draft needs valid values but does not need an approved monitor yet.
    fn config_snapshot(&self) -> Result<AppConfig, String> {
        let interval_ms = u64::try_from(self.interval_ms)
            .map_err(|_| "Das Intervall muss positiv sein.".to_owned())?;
        validate_interval(interval_ms).map_err(|error| error.to_string())?;
        let repeat_count = u64::try_from(self.repeat_count)
            .map_err(|_| "Die Wiederholungszahl muss positiv sein.".to_owned())?;
        if !(1..=MAX_REPEAT_COUNT).contains(&repeat_count) {
            return Err("Die Wiederholungszahl ist ungültig.".to_owned());
        }
        let fixed_x = u32::try_from(self.fixed_x)
            .map_err(|_| "X muss eine nichtnegative Ganzzahl sein.".to_owned())?;
        let fixed_y = u32::try_from(self.fixed_y)
            .map_err(|_| "Y muss eine nichtnegative Ganzzahl sein.".to_owned())?;
        if fixed_x > 100_000 || fixed_y > 100_000 {
            return Err(
                "Die festen Koordinaten liegen außerhalb des unterstützten Bereichs.".to_owned(),
            );
        }
        let mouse_button = match self.mouse_button {
            0 => MouseButton::Left,
            1 => MouseButton::Right,
            2 => MouseButton::Middle,
            _ => return Err("Unbekannte Maustaste.".to_owned()),
        };
        let click_type = match self.click_type {
            0 => ClickType::Single,
            1 => ClickType::Double,
            _ => return Err("Unbekannter Klicktyp.".to_owned()),
        };
        Ok(AppConfig {
            interval_ms,
            mouse_button,
            click_type,
            repeat_mode: if self.repeat_until_stopped {
                RepeatMode::UntilStopped
            } else {
                RepeatMode::Count
            },
            repeat_count,
            position_mode: if self.current_position {
                PositionMode::CurrentCursor
            } else {
                PositionMode::Fixed
            },
            fixed_x,
            fixed_y,
            hotkey: self.hotkey.to_string(),
            monitor_identity: if self.fixed_position_confirmed {
                self.monitor_identity.to_string()
            } else {
                String::new()
            },
        })
    }

    fn persist_config(&mut self, force: bool) -> Result<(), String> {
        if !force && !self.config_dirty {
            return Ok(());
        }
        let path = config::config_path().map_err(|error| error.to_string())?;
        self.persist_config_to(&path, force)
    }

    fn persist_config_to(&mut self, path: &Path, force: bool) -> Result<(), String> {
        if !force && !self.config_dirty {
            return Ok(());
        }
        let config = self.config_snapshot()?;
        if config != self.initial_config {
            config::save_to(path, &config).map_err(|error| error.to_string())?;
        }
        self.initial_config = config;
        self.config_dirty = false;
        Ok(())
    }
}

impl Drop for AppControllerRust {
    /// Shut down the worker before destroying the Qt controller.
    fn drop(&mut self) {
        if let Some(worker) = self.worker.take() {
            worker.shutdown();
        }
    }
}

impl qobject::AppController {
    /// Start the worker and hotkey even if saved coordinates need confirmation.
    pub fn initialize(mut self: Pin<&mut Self>) {
        if self.rust().worker.is_some() {
            return;
        }
        if let Some(error) = self.as_mut().rust_mut().get_mut().startup_error.take() {
            self.as_mut().set_error_message(QString::from(&error));
        }
        // The worker must remain available even when restored fixed coordinates
        // need confirmation. Every actual start still validates the current UI.
        let settings = ClickSettings {
            interval_ms: 100,
            button: MouseButton::Left,
            click_type: ClickType::Single,
            repeat: None,
            position: None,
            monitor: None,
        };
        let preferred_hotkey = self.hotkey().to_string();
        let worker_epoch = self.rust().worker_epoch.wrapping_add(1);
        self.as_mut().rust_mut().get_mut().worker_epoch = worker_epoch;
        let qt_thread = self.qt_thread();
        let worker = WorkerHandle::spawn(settings, preferred_hotkey, move |event| {
            let _ = qt_thread.queue(move |mut controller| {
                controller.as_mut().handle_worker_event(worker_epoch, event);
            });
        });
        self.as_mut().rust_mut().get_mut().worker = Some(worker);
    }

    /// Request a screenshot and report queue failures back to the picker.
    pub fn capture_screenshot(mut self: Pin<&mut Self>, request_id: i32) {
        let result = self
            .rust()
            .worker
            .as_ref()
            .ok_or("Der Hintergrund-Worker wurde nicht gestartet.")
            .and_then(|worker| worker.send(Command::CaptureScreenshot(request_id)));
        if let Err(error) = result {
            self.as_mut()
                .screenshot_ready(request_id, QString::default(), QString::from(error));
        }
    }

    /// Cancels only the screenshot belonging to the picker being closed.
    pub fn cancel_screenshot(mut self: Pin<&mut Self>, request_id: i32) {
        self.as_mut()
            .send_command(Command::CancelScreenshot(request_id));
    }

    /// Validate and save current controls before requesting a click run.
    pub fn start(mut self: Pin<&mut Self>) {
        if *self.selecting_position() {
            return;
        }
        self.as_mut().clear_error();
        let settings = match self.as_ref().settings() {
            Ok(settings) => settings,
            Err(error) => {
                self.as_mut().show_error(&error);
                return;
            }
        };
        self.as_mut().persist_config(true);
        self.as_mut().send_command(Command::Start(settings));
    }

    /// Stop a run or an outstanding start request.
    pub fn stop(mut self: Pin<&mut Self>) {
        self.as_mut().send_command(Command::Stop);
    }

    /// Toggle clicking using the latest controls rather than cached settings.
    pub fn toggle(mut self: Pin<&mut Self>) {
        if *self.running() || *self.busy() {
            self.as_mut().stop();
        } else {
            self.as_mut().start();
        }
    }

    /// Open the desktop portal configuration for the global shortcut.
    pub fn configure_hotkey(mut self: Pin<&mut Self>) {
        self.as_mut().send_command(Command::ConfigureHotkey);
    }

    /// Dismiss the current user-visible error message.
    pub fn clear_error(mut self: Pin<&mut Self>) {
        self.as_mut().set_error_message(QString::default());
    }

    /// Record deliberate edits; display initialization must not rewrite a config.
    pub fn mark_settings_changed(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().get_mut().config_dirty = true;
    }

    /// Save a changed draft, including settings that do not require a click run.
    pub fn save_config(mut self: Pin<&mut Self>) -> bool {
        self.as_mut().persist_config(false)
    }

    fn persist_config(mut self: Pin<&mut Self>, force: bool) -> bool {
        match self.as_mut().rust_mut().get_mut().persist_config(force) {
            Ok(()) => true,
            Err(error) => {
                self.as_mut().set_error_message(QString::from(&error));
                false
            }
        }
    }

    /// Join the worker and clear running indicators during window closure.
    pub fn shutdown(mut self: Pin<&mut Self>) {
        let worker = {
            let rust = self.as_mut().rust_mut().get_mut();
            rust.worker_epoch = rust.worker_epoch.wrapping_add(1);
            rust.worker.take()
        };
        if let Some(worker) = worker {
            worker.shutdown();
        }
        self.as_mut().set_running(false);
        self.as_mut().set_busy(false);
        self.as_mut().set_status(QString::from("Bereit"));
    }

    /// Send through the bounded worker channel and surface delivery failures.
    fn send_command(mut self: Pin<&mut Self>, command: Command) {
        let result = self
            .rust()
            .worker
            .as_ref()
            .ok_or("Der Hintergrund-Worker wurde nicht gestartet.")
            .and_then(|worker| worker.send(command));
        if let Err(error) = result {
            self.as_mut().show_error(error);
        }
    }

    /// Build validated settings; unconfirmed fixed positions cannot start.
    fn settings(self: Pin<&Self>) -> Result<ClickSettings, String> {
        if !*self.current_position() && !*self.fixed_position_confirmed() {
            return Err("Bitte den Monitor und die feste Position erneut bestätigen.".to_owned());
        }
        let button = match *self.mouse_button() {
            0 => MouseButton::Left,
            1 => MouseButton::Right,
            2 => MouseButton::Middle,
            _ => return Err("Unbekannte Maustaste.".to_owned()),
        };
        let click_type = match *self.click_type() {
            0 => ClickType::Single,
            1 => ClickType::Double,
            _ => return Err("Unbekannter Klicktyp.".to_owned()),
        };
        let interval_ms = u64::try_from(*self.interval_ms())
            .map_err(|_| "Das Intervall muss positiv sein.".to_owned())?;
        let repeat = if *self.repeat_until_stopped() {
            None
        } else {
            Some(
                u64::try_from(*self.repeat_count())
                    .map_err(|_| "Die Wiederholungszahl muss positiv sein.".to_owned())?,
            )
        };
        let position = if *self.current_position() {
            None
        } else {
            Some((
                u32::try_from(*self.fixed_x())
                    .map_err(|_| "X muss eine nichtnegative Ganzzahl sein.".to_owned())?,
                u32::try_from(*self.fixed_y())
                    .map_err(|_| "Y muss eine nichtnegative Ganzzahl sein.".to_owned())?,
            ))
        };
        let settings = ClickSettings {
            interval_ms,
            button,
            click_type,
            repeat,
            position,
            monitor: position.map(|_| MonitorGeometry {
                x: *self.monitor_x(),
                y: *self.monitor_y(),
                width: *self.monitor_width(),
                height: *self.monitor_height(),
            }),
        };
        settings.validate().map_err(|error| error.to_string())?;
        Ok(settings)
    }

    /// Display an error and reset the running and busy indicators.
    fn show_error(mut self: Pin<&mut Self>, message: &str) {
        self.as_mut().set_running(false);
        self.as_mut().set_busy(false);
        self.as_mut().set_status(QString::from("Fehler"));
        self.as_mut().set_error_message(QString::from(message));
    }

    /// Apply worker results on the Qt thread and route capture responses.
    fn handle_worker_event(mut self: Pin<&mut Self>, worker_epoch: u64, event: WorkerEvent) {
        if worker_epoch != self.rust().worker_epoch {
            return;
        }
        match event {
            WorkerEvent::Screenshot(request_id, result) => {
                let (uri, error) = match result {
                    Ok(uri) => (uri, String::new()),
                    Err(error) => (String::new(), error),
                };
                self.as_mut().screenshot_ready(
                    request_id,
                    QString::from(&uri),
                    QString::from(&error),
                );
            }
            WorkerEvent::Status(status) => {
                let busy = status.contains("Warte auf Wayland");
                self.as_mut().set_busy(busy);
                self.as_mut().set_status(QString::from(&status));
            }
            WorkerEvent::Running(running) => {
                self.as_mut().set_running(running);
                self.as_mut().set_busy(false);
            }
            WorkerEvent::Hotkey(hotkey) => {
                if self.hotkey().to_string() != hotkey {
                    self.as_mut().set_hotkey(QString::from(&hotkey));
                    self.as_mut().mark_settings_changed();
                }
            }
            WorkerEvent::StartRequested => {
                if !*self.running() && !*self.busy() {
                    self.as_mut().start();
                }
            }
            WorkerEvent::Error(error) => self.as_mut().show_error(&error),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_ID: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn draft_survives_close_and_reload_without_confirming_position_or_starting() {
        let mut controller = AppControllerRust::from_config(AppConfig::default(), None);
        controller.interval_ms = 250;
        controller.mouse_button = 1;
        controller.click_type = 1;
        controller.repeat_until_stopped = false;
        controller.repeat_count = 42;
        controller.current_position = false;
        controller.fixed_x = 640;
        controller.fixed_y = 480;
        controller.monitor_identity = QString::from("monitor-a");
        controller.hotkey = QString::from("F8");
        controller.config_dirty = true;
        // The monitor has not been confirmed, so this draft cannot start.
        assert!(!controller.fixed_position_confirmed);

        let directory = std::env::temp_dir().join(format!(
            "klickmeister-controller-test-{}-{}",
            std::process::id(),
            NEXT_ID.fetch_add(1, Ordering::Relaxed)
        ));
        let path = directory.join("config.toml");
        assert!(controller.persist_config_to(&path, false).is_ok());
        let loaded = config::load_from(&path).unwrap_or_else(|error| panic!("{error}"));
        assert!(loaded.monitor_identity.is_empty());
        let reopened = AppControllerRust::from_config(loaded, None);
        assert_eq!(reopened.interval_ms, 250);
        assert_eq!(reopened.mouse_button, 1);
        assert_eq!(reopened.click_type, 1);
        assert_eq!(reopened.repeat_count, 42);
        assert_eq!(reopened.fixed_x, 640);
        assert_eq!(reopened.fixed_y, 480);
        assert_eq!(reopened.hotkey.to_string(), "F8");
        assert!(!reopened.current_position);
        assert!(!reopened.fixed_position_confirmed);
        assert!(!reopened.running);
        assert!(reopened.worker.is_none());
        let _ = std::fs::remove_dir_all(directory);
    }

    #[test]
    fn closing_unchanged_does_not_replace_another_write_or_a_malformed_file() {
        let directory = std::env::temp_dir().join(format!(
            "klickmeister-controller-test-{}-{}",
            std::process::id(),
            NEXT_ID.fetch_add(1, Ordering::Relaxed)
        ));
        let path = directory.join("config.toml");
        let initial = AppConfig::default();
        assert!(config::save_to(&path, &initial).is_ok());
        let mut first = AppControllerRust::from_config(initial.clone(), None);
        let mut second = AppControllerRust::from_config(initial.clone(), None);
        first.interval_ms = 250;
        first.config_dirty = true;
        assert!(first.persist_config_to(&path, false).is_ok());
        assert!(second.persist_config_to(&path, false).is_ok());
        assert_eq!(
            config::load_from(&path).ok().map(|c| c.interval_ms),
            Some(250)
        );

        let malformed = "interval_ms = [\n";
        assert!(std::fs::write(&path, malformed).is_ok());
        assert!(config::load_from(&path).is_err());
        let mut failed_load = AppControllerRust::from_config(initial, Some("parse error".into()));
        assert!(failed_load.persist_config_to(&path, false).is_ok());
        assert_eq!(
            std::fs::read_to_string(&path).ok().as_deref(),
            Some(malformed)
        );
        let _ = std::fs::remove_dir_all(directory);
    }
}
