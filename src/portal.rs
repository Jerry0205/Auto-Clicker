use ashpd::{
    desktop::{
        PersistMode, Session, SessionPortal,
        remote_desktop::{
            DeviceType, KeyState, NotifyPointerMotionAbsoluteOptions, RemoteDesktop,
            SelectDevicesOptions,
        },
        screencast::{CursorMode, Screencast, SelectSourcesOptions, SourceType},
    },
    zbus::Connection,
};
use thiserror::Error;
use tokio::{
    sync::oneshot,
    time::{Duration, timeout},
};

use crate::model::{ClickSettings, MonitorGeometry};

const EVENT_TIMEOUT: Duration = Duration::from_millis(250);
pub(crate) const CLOSE_TIMEOUT: Duration = Duration::from_secs(1);

/// Close a session, then its private connection, waiting at most CLOSE_TIMEOUT for each step.
pub(crate) async fn close_session<T: SessionPortal>(
    session: Option<&Session<T>>,
    connection: Connection,
) {
    if let Some(session) = session {
        let _ = timeout(CLOSE_TIMEOUT, session.close()).await;
    }
    let _ = timeout(CLOSE_TIMEOUT, connection.close()).await;
}

#[derive(Debug, Error)]
pub enum PortalError {
    #[error("Die Portal-Anfrage wurde abgebrochen.")]
    Cancelled,
    #[error("Das XDG RemoteDesktop-Portal ist nicht verfügbar: {0}")]
    Unavailable(#[source] ashpd::Error),
    #[error("Die Portal-Anfrage wurde abgelehnt oder abgebrochen: {0}")]
    Denied(#[source] ashpd::Error),
    #[error("KWin hat keine Berechtigung für Zeigersteuerung erteilt.")]
    PointerNotGranted,
    #[error("Für die feste Position wurde kein Monitor-Stream freigegeben.")]
    MissingMonitorStream,
    #[error(
        "Der freigegebene Monitor stimmt nicht mit der Positionsauswahl überein. Bitte beim nächsten Start denselben Monitor wie in der App freigeben."
    )]
    MonitorMismatch,
    #[error(
        "Das Portal liefert keine eindeutige Monitorposition. Die feste Position kann nicht sicher zugeordnet werden."
    )]
    MonitorUnverifiable,
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
    connection: Connection,
    portal: RemoteDesktop,
    session: Session<RemoteDesktop>,
    stream: Option<MonitorStream>,
}

#[derive(Debug, Clone, Copy)]
struct MonitorStream {
    node_id: u32,
    width: i32,
    height: i32,
    position: Option<(i32, i32)>,
}

impl PortalClickSession {
    /// Request pointer permission and verify any fixed-position monitor geometry.
    pub async fn create(
        monitor: Option<MonitorGeometry>,
        mut cancel: oneshot::Receiver<()>,
    ) -> Result<Self, PortalError> {
        // Own the connection so cancellation also cleans up a CreateSession
        // request whose session handle has not arrived yet.
        let connection = tokio::select! {
            biased;
            _ = &mut cancel => return Err(PortalError::Cancelled),
            result = Connection::session() =>
                result.map_err(|error| PortalError::Unavailable(error.into()))?,
        };
        let mut session = None;
        let result = tokio::select! {
            biased;
            _ = &mut cancel => Err(PortalError::Cancelled),
            result = Self::create_on(&connection, &mut session, monitor) => result,
        };
        match result {
            Ok((portal, stream)) => Ok(Self {
                connection,
                portal,
                session: session.ok_or(PortalError::Cancelled)?,
                stream,
            }),
            Err(error) => {
                close_session(session.as_ref(), connection).await;
                Err(error)
            }
        }
    }

    /// Negotiate permission while exposing the session to cancellation cleanup.
    async fn create_on(
        connection: &Connection,
        owned_session: &mut Option<Session<RemoteDesktop>>,
        monitor: Option<MonitorGeometry>,
    ) -> Result<(RemoteDesktop, Option<MonitorStream>), PortalError> {
        let portal = RemoteDesktop::with_connection(connection.clone())
            .await
            .map_err(PortalError::Unavailable)?;
        let available = portal
            .available_device_types()
            .await
            .map_err(PortalError::Unavailable)?;
        if !available.contains(DeviceType::Pointer) {
            return Err(PortalError::PointerNotGranted);
        }

        *owned_session = Some(
            portal
                .create_session(Default::default())
                .await
                .map_err(PortalError::Unavailable)?,
        );
        let session = owned_session.as_ref().ok_or(PortalError::Cancelled)?;
        portal
            .select_devices(
                session,
                SelectDevicesOptions::default()
                    .set_devices(Some(DeviceType::Pointer.into()))
                    .set_persist_mode(PersistMode::Application),
            )
            .await
            .map_err(PortalError::Unavailable)?;

        if monitor.is_some() {
            let screencast = Screencast::with_connection(connection.clone())
                .await
                .map_err(PortalError::Unavailable)?;
            screencast
                .select_sources(
                    session,
                    SelectSourcesOptions::default()
                        .set_sources(Some(SourceType::Monitor.into()))
                        .set_multiple(false)
                        .set_cursor_mode(CursorMode::Hidden),
                )
                .await
                .map_err(PortalError::Unavailable)?;
        }

        let selected = portal
            .start(session, None, Default::default())
            .await
            .map_err(PortalError::Unavailable)?
            .response()
            .map_err(PortalError::Denied)?;
        if !selected.devices().contains(DeviceType::Pointer) {
            return Err(PortalError::PointerNotGranted);
        }

        let stream = match monitor {
            Some(expected) => {
                let stream = selected
                    .streams()
                    .first()
                    .ok_or(PortalError::MissingMonitorStream)?;
                let (width, height) = stream.size().ok_or(PortalError::MissingMonitorStream)?;
                validate_monitor(expected, stream.position(), (width, height))?;
                Some(MonitorStream {
                    node_id: stream.pipe_wire_node_id(),
                    position: stream.position(),
                    width,
                    height,
                })
            }
            None => None,
        };

        Ok((portal, stream))
    }

    /// Reuse a session only when its granted monitor matches current settings.
    pub fn matches_monitor(&self, monitor: Option<MonitorGeometry>) -> bool {
        match (self.stream, monitor) {
            (None, None) => true,
            (Some(stream), Some(expected)) => {
                validate_monitor(expected, stream.position, (stream.width, stream.height)).is_ok()
            }
            _ => false,
        }
    }

    /// Move within the verified monitor if needed and emit a bounded click cycle.
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
        for _ in 0..settings.click_type.clicks_per_tick() {
            for state in [KeyState::Pressed, KeyState::Released] {
                if let Err(error) = self.send_button(button, state).await {
                    // Never leave the button held down, even if the press itself failed.
                    let _ = self.send_button(button, KeyState::Released).await;
                    return Err(error);
                }
            }
        }
        Ok(())
    }

    async fn send_button(&self, button: i32, state: KeyState) -> Result<(), PortalError> {
        timeout(
            EVENT_TIMEOUT,
            self.portal
                .notify_pointer_button(&self.session, button, state, Default::default()),
        )
        .await
        .map_err(|_| PortalError::EventTimeout)?
        .map_err(PortalError::Send)
    }

    pub async fn close(self) {
        close_session(Some(&self.session), self.connection).await;
    }
}

fn validate_monitor(
    expected: MonitorGeometry,
    position: Option<(i32, i32)>,
    size: (i32, i32),
) -> Result<(), PortalError> {
    let position = position.ok_or(PortalError::MonitorUnverifiable)?;
    if position != (expected.x, expected.y)
        || size != (expected.width, expected.height)
        || expected.width <= 0
        || expected.height <= 0
    {
        return Err(PortalError::MonitorMismatch);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn monitor_matching_checks_origin_size_and_missing_metadata() {
        let monitor = MonitorGeometry {
            x: -1920,
            y: 0,
            width: 1920,
            height: 1080,
        };
        assert!(validate_monitor(monitor, Some((-1920, 0)), (1920, 1080)).is_ok());
        assert!(matches!(
            validate_monitor(monitor, Some((0, 0)), (1920, 1080)),
            Err(PortalError::MonitorMismatch)
        ));
        assert!(matches!(
            validate_monitor(monitor, Some((-1920, 0)), (1280, 720)),
            Err(PortalError::MonitorMismatch)
        ));
        assert!(matches!(
            validate_monitor(monitor, None, (1920, 1080)),
            Err(PortalError::MonitorUnverifiable)
        ));
    }
}
