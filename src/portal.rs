use ashpd::desktop::{
    PersistMode, Session,
    remote_desktop::{
        DeviceType, KeyState, NotifyPointerMotionAbsoluteOptions, RemoteDesktop,
        SelectDevicesOptions,
    },
    screencast::{CursorMode, Screencast, SelectSourcesOptions, SourceType},
};
use thiserror::Error;
use tokio::time::{Duration, timeout};

use crate::model::{ClickSettings, ClickType};

const EVENT_TIMEOUT: Duration = Duration::from_millis(250);

#[derive(Debug, Error)]
pub enum PortalError {
    #[error("Das XDG RemoteDesktop-Portal ist nicht verfügbar: {0}")]
    Unavailable(#[source] ashpd::Error),
    #[error("Die Portal-Anfrage wurde abgelehnt oder abgebrochen: {0}")]
    Denied(#[source] ashpd::Error),
    #[error("KWin hat keine Berechtigung für Zeigersteuerung erteilt.")]
    PointerNotGranted,
    #[error("Für die feste Position wurde kein Monitor-Stream freigegeben.")]
    MissingMonitorStream,
    #[error(
        "Die feste Position ({x}, {y}) liegt außerhalb des freigegebenen Monitors ({width} × {height})."
    )]
    PositionOutsideStream {
        x: u32,
        y: u32,
        width: i32,
        height: i32,
    },
    #[error("Der Klick konnte nicht an KWin gesendet werden: {0}")]
    Send(#[source] ashpd::Error),
    #[error("KWin hat ein Zeigerereignis nicht innerhalb von 250 ms bestätigt.")]
    EventTimeout,
}

#[derive(Debug)]
pub struct PortalClickSession {
    portal: RemoteDesktop,
    session: Session<RemoteDesktop>,
    stream: Option<MonitorStream>,
}

#[derive(Debug, Clone, Copy)]
struct MonitorStream {
    node_id: u32,
    width: i32,
    height: i32,
}

impl PortalClickSession {
    pub async fn create(fixed_position: bool) -> Result<Self, PortalError> {
        let portal = RemoteDesktop::new()
            .await
            .map_err(PortalError::Unavailable)?;
        let available = portal
            .available_device_types()
            .await
            .map_err(PortalError::Unavailable)?;
        if !available.contains(DeviceType::Pointer) {
            return Err(PortalError::PointerNotGranted);
        }

        let session = portal
            .create_session(Default::default())
            .await
            .map_err(PortalError::Unavailable)?;
        portal
            .select_devices(
                &session,
                SelectDevicesOptions::default()
                    .set_devices(Some(DeviceType::Pointer.into()))
                    .set_persist_mode(PersistMode::Application),
            )
            .await
            .map_err(PortalError::Unavailable)?;

        if fixed_position {
            let screencast = Screencast::new().await.map_err(PortalError::Unavailable)?;
            screencast
                .select_sources(
                    &session,
                    SelectSourcesOptions::default()
                        .set_sources(Some(SourceType::Monitor.into()))
                        .set_multiple(false)
                        .set_cursor_mode(CursorMode::Hidden),
                )
                .await
                .map_err(PortalError::Unavailable)?;
        }

        let selected = portal
            .start(&session, None, Default::default())
            .await
            .map_err(PortalError::Unavailable)?
            .response()
            .map_err(PortalError::Denied)?;
        if !selected.devices().contains(DeviceType::Pointer) {
            let _ = session.close().await;
            return Err(PortalError::PointerNotGranted);
        }

        let stream = if fixed_position {
            let Some(stream) = selected.streams().first() else {
                let _ = session.close().await;
                return Err(PortalError::MissingMonitorStream);
            };
            let Some((width, height)) = stream.size() else {
                let _ = session.close().await;
                return Err(PortalError::MissingMonitorStream);
            };
            Some(MonitorStream {
                node_id: stream.pipe_wire_node_id(),
                width,
                height,
            })
        } else {
            None
        };

        Ok(Self {
            portal,
            session,
            stream,
        })
    }

    pub const fn supports_fixed_position(&self) -> bool {
        self.stream.is_some()
    }

    pub async fn click(&self, settings: &ClickSettings) -> Result<(), PortalError> {
        if let Some((x, y)) = settings.position {
            let stream = self.stream.ok_or(PortalError::MissingMonitorStream)?;
            if x >= stream.width.max(0) as u32 || y >= stream.height.max(0) as u32 {
                return Err(PortalError::PositionOutsideStream {
                    x,
                    y,
                    width: stream.width,
                    height: stream.height,
                });
            }
            timeout(
                EVENT_TIMEOUT,
                self.portal.notify_pointer_motion_absolute(
                    &self.session,
                    stream.node_id,
                    f64::from(x),
                    f64::from(y),
                    NotifyPointerMotionAbsoluteOptions::default(),
                ),
            )
            .await
            .map_err(|_| PortalError::EventTimeout)?
            .map_err(PortalError::Send)?;
        }

        let button = settings.button.evdev_code();
        let count = match settings.click_type {
            ClickType::Single => 1,
            ClickType::Double => 2,
        };
        for _ in 0..count {
            let press = timeout(
                EVENT_TIMEOUT,
                self.portal.notify_pointer_button(
                    &self.session,
                    button,
                    KeyState::Pressed,
                    Default::default(),
                ),
            )
            .await;
            match press {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    self.best_effort_release(button).await;
                    return Err(PortalError::Send(error));
                }
                Err(_) => {
                    self.best_effort_release(button).await;
                    return Err(PortalError::EventTimeout);
                }
            }
            let release = timeout(
                EVENT_TIMEOUT,
                self.portal.notify_pointer_button(
                    &self.session,
                    button,
                    KeyState::Released,
                    Default::default(),
                ),
            )
            .await;
            match release {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    self.best_effort_release(button).await;
                    return Err(PortalError::Send(error));
                }
                Err(_) => {
                    self.best_effort_release(button).await;
                    return Err(PortalError::EventTimeout);
                }
            }
        }
        Ok(())
    }

    async fn best_effort_release(&self, button: i32) {
        let _ = timeout(
            EVENT_TIMEOUT,
            self.portal.notify_pointer_button(
                &self.session,
                button,
                KeyState::Released,
                Default::default(),
            ),
        )
        .await;
    }

    pub async fn close(self) {
        let _ = self.session.close().await;
    }
}
