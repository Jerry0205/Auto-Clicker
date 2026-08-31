use std::pin::Pin;

use crate::{
    config::{self, AppConfig},
    model::{ClickSettings, ClickType, MouseButton, PositionMode, RepeatMode},
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
        type AppController = super::AppControllerRust;

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
    worker: Option<WorkerHandle>,
    startup_error: Option<String>,
}

impl Default for AppControllerRust {
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
        let settings = match self.as_ref().settings() {
            Ok(settings) => settings,
            Err(error) => {
                self.as_mut().show_error(&error);
                return;
            }
        };
        let preferred_hotkey = self.hotkey().to_string();
        let qt_thread = self.qt_thread();
        let worker = WorkerHandle::spawn(settings, preferred_hotkey, move |event| {
            let _ = qt_thread.queue(move |mut controller| {
                controller.as_mut().handle_worker_event(event);
            });
        });
        self.as_mut().rust_mut().get_mut().worker = Some(worker);
    }

    pub fn start(mut self: Pin<&mut Self>) {
        self.as_mut().clear_error();
        let settings = match self.as_ref().settings() {
            Ok(settings) => settings,
            Err(error) => {
                self.as_mut().show_error(&error);
                return;
            }
        };
        if let Err(error) = self.as_ref().save_config() {
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

    pub fn shutdown(mut self: Pin<&mut Self>) {
        if let Some(worker) = self.as_mut().rust_mut().get_mut().worker.take() {
            worker.shutdown();
        }
        self.as_mut().set_running(false);
        self.as_mut().set_busy(false);
    }

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

    fn settings(self: Pin<&Self>) -> Result<ClickSettings, String> {
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
        };
        settings.validate().map_err(|error| error.to_string())?;
        Ok(settings)
    }

    fn save_config(self: Pin<&Self>) -> Result<(), String> {
        let settings = self.settings()?;
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
