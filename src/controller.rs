use std::pin::Pin;

use crate::{
    config::{self, AppConfig},
    model::{ClickSettings, ClickType, MonitorGeometry, MouseButton, PositionMode, RepeatMode},
    worker::{Command, WorkerEvent, WorkerHandle},
};

/// QML exposes the choices as integer indices in this order.
const MOUSE_BUTTONS: [MouseButton; 3] =
    [MouseButton::Left, MouseButton::Right, MouseButton::Middle];
const CLICK_TYPES: [ClickType; 2] = [ClickType::Single, ClickType::Double];

fn index_of<T: PartialEq>(choices: &[T], value: &T) -> i32 {
    choices
        .iter()
        .position(|choice| choice == value)
        .and_then(|index| i32::try_from(index).ok())
        .unwrap_or_default()
}

fn choice_at<T: Copy>(choices: &[T], index: i32) -> Option<T> {
    usize::try_from(index)
        .ok()
        .and_then(|index| choices.get(index).copied())
}
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
    startup_error: Option<String>,
}

impl Default for AppControllerRust {
    /// A saved fixed position stays unconfirmed until QML has matched its monitor.
    fn default() -> Self {
        let (config, startup_error) = match config::load() {
            Ok(config) => (config, None),
            Err(error) => (AppConfig::default(), Some(error.to_string())),
        };
        Self {
            status: QString::from("Bereit"),
            error_message: QString::default(),
            hotkey: QString::from(&config.hotkey),
            running: false,
            busy: false,
            interval_ms: i64::try_from(config.interval_ms).unwrap_or(100),
            mouse_button: index_of(&MOUSE_BUTTONS, &config.mouse_button),
            click_type: index_of(&CLICK_TYPES, &config.click_type),
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
            startup_error,
        }
    }
}

impl Drop for AppControllerRust {
    fn drop(&mut self) {
        if let Some(worker) = self.worker.take() {
            worker.shutdown();
        }
    }
}

impl qobject::AppController {
    pub fn initialize(mut self: Pin<&mut Self>) {
        if self.rust().worker.is_some() {
            return;
        }
        if let Some(error) = self.as_mut().rust_mut().get_mut().startup_error.take() {
            self.as_mut().set_error_message(QString::from(&error));
        }
        let preferred_hotkey = self.hotkey().to_string();
        let qt_thread = self.qt_thread();
        let worker = WorkerHandle::spawn(preferred_hotkey, move |event| {
            let _ = qt_thread.queue(move |mut controller| {
                controller.as_mut().handle_worker_event(event);
            });
        });
        self.as_mut().rust_mut().get_mut().worker = Some(worker);
    }

    pub fn capture_screenshot(mut self: Pin<&mut Self>, request_id: i32) {
        if let Err(error) = self.try_send(Command::CaptureScreenshot(request_id)) {
            self.as_mut()
                .screenshot_ready(request_id, QString::default(), QString::from(error));
        }
    }

    pub fn cancel_screenshot(mut self: Pin<&mut Self>, request_id: i32) {
        self.as_mut()
            .send_command(Command::CancelScreenshot(request_id));
    }

    /// Validate and save the current controls, then request a click run.
    pub fn start(mut self: Pin<&mut Self>) {
        if *self.selecting_position() {
            return;
        }
        self.as_mut().clear_error();
        let settings = match self.settings() {
            Ok(settings) => settings,
            Err(error) => {
                self.as_mut().show_error(&error);
                return;
            }
        };
        if let Err(error) = self.save_config(&settings) {
            self.as_mut().set_error_message(QString::from(&error));
        }
        self.as_mut().send_command(Command::Start(settings));
    }

    pub fn stop(mut self: Pin<&mut Self>) {
        self.as_mut().send_command(Command::Stop);
    }

    pub fn toggle(mut self: Pin<&mut Self>) {
        if *self.running() || *self.busy() {
            self.as_mut().stop();
        } else {
            self.as_mut().start();
        }
    }

    pub fn configure_hotkey(mut self: Pin<&mut Self>) {
        self.as_mut().send_command(Command::ConfigureHotkey);
    }

    pub fn clear_error(mut self: Pin<&mut Self>) {
        self.as_mut().set_error_message(QString::default());
    }

    /// Join the worker so that portal sessions are closed before the window goes away.
    pub fn shutdown(mut self: Pin<&mut Self>) {
        if let Some(worker) = self.as_mut().rust_mut().get_mut().worker.take() {
            worker.shutdown();
        }
        self.as_mut().set_running(false);
        self.as_mut().set_busy(false);
    }

    fn try_send(&self, command: Command) -> Result<(), &'static str> {
        self.rust()
            .worker
            .as_ref()
            .ok_or("Der Hintergrund-Worker wurde nicht gestartet.")?
            .send(command)
    }

    fn send_command(mut self: Pin<&mut Self>, command: Command) {
        if let Err(error) = self.try_send(command) {
            self.as_mut().show_error(error);
        }
    }

    /// Unconfirmed fixed positions cannot start.
    fn settings(&self) -> Result<ClickSettings, String> {
        if !*self.current_position() && !*self.fixed_position_confirmed() {
            return Err("Bitte den Monitor und die feste Position erneut bestätigen.".to_owned());
        }
        let button =
            choice_at(&MOUSE_BUTTONS, *self.mouse_button()).ok_or("Unbekannte Maustaste.")?;
        let click_type =
            choice_at(&CLICK_TYPES, *self.click_type()).ok_or("Unbekannter Klicktyp.")?;
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

    /// The monitor identity is only saved for a confirmed position.
    fn save_config(&self, settings: &ClickSettings) -> Result<(), String> {
        let config = AppConfig {
            interval_ms: settings.interval_ms,
            mouse_button: settings.button,
            click_type: settings.click_type,
            repeat_mode: if settings.repeat.is_some() {
                RepeatMode::Count
            } else {
                RepeatMode::UntilStopped
            },
            repeat_count: u64::try_from(*self.repeat_count()).unwrap_or(100),
            position_mode: if settings.position.is_some() {
                PositionMode::Fixed
            } else {
                PositionMode::CurrentCursor
            },
            fixed_x: u32::try_from(*self.fixed_x()).unwrap_or(0),
            fixed_y: u32::try_from(*self.fixed_y()).unwrap_or(0),
            hotkey: self.hotkey().to_string(),
            monitor_identity: if *self.fixed_position_confirmed() {
                self.monitor_identity().to_string()
            } else {
                String::new()
            },
        };
        config::save(&config).map_err(|error| error.to_string())
    }

    fn show_error(mut self: Pin<&mut Self>, message: &str) {
        self.as_mut().set_running(false);
        self.as_mut().set_busy(false);
        self.as_mut().set_status(QString::from("Fehler"));
        self.as_mut().set_error_message(QString::from(message));
    }

    fn handle_worker_event(mut self: Pin<&mut Self>, event: WorkerEvent) {
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
            WorkerEvent::Hotkey(hotkey) => self.as_mut().set_hotkey(QString::from(&hotkey)),
            WorkerEvent::StartRequested => {
                if !*self.running() && !*self.busy() {
                    self.as_mut().start();
                }
            }
            WorkerEvent::Error(error) => self.as_mut().show_error(&error),
        }
    }
}
