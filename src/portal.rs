use std::{pin::Pin, sync::Arc};

use ashpd::desktop::{
    PersistMode, Session,
    remote_desktop::{
        DeviceType, KeyState, NotifyPointerMotionAbsoluteOptions, RemoteDesktop,
        SelectDevicesOptions,
    },
    screencast::{CursorMode, Screencast, SelectSourcesOptions, SourceType},
};
use futures_util::{FutureExt, StreamExt, future::FusedFuture};
use thiserror::Error;
use tokio::{
    sync::oneshot,
    time::{Duration, timeout},
};

use crate::model::{ClickSettings, MonitorGeometry};

const EVENT_TIMEOUT: Duration = Duration::from_millis(250);
const CLOSE_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Debug, Error)]
pub enum PortalError {
    #[error("Die Freigabe wurde abgebrochen.")]
    Cancelled,
    #[error("Die Maussteuerung ist nicht verfügbar. Prüfe den KDE-Portaldienst. Details: {0}")]
    Unavailable(#[source] ashpd::Error),
    #[error("Die Freigabe wurde abgelehnt oder abgebrochen: {0}")]
    Denied(#[source] ashpd::Error),
    #[error(
        "Die Maussteuerung wurde nicht freigegeben. Erlaube sie beim nächsten Start im KDE-Dialog."
    )]
    PointerNotGranted,
    #[error(
        "Die Freigabe für die Maussteuerung kann nicht überwacht werden. Versuche den Start erneut."
    )]
    SessionWatchUnavailable,
    #[error("Die Freigabe für die Maussteuerung wurde beendet. Starte erneut, um sie anzufordern.")]
    SessionClosed,
    #[error(
        "Kein Bildschirm freigegeben. Wähle beim nächsten Start den Bildschirm der festen Position."
    )]
    MissingMonitorStream,
    #[error(
        "Der freigegebene Bildschirm stimmt nicht mit der Auswahl überein. Gib beim nächsten Start den in Klickmeister ausgewählten Bildschirm frei."
    )]
    MonitorMismatch,
    #[error(
        "Die feste Position kann keinem Bildschirm eindeutig zugeordnet werden. Wähle die aktuelle Mauszeigerposition oder versuche es erneut."
    )]
    MonitorUnverifiable,
    #[error(
        "Die Position ({x}, {y}) liegt außerhalb des freigegebenen Bildschirms ({width} × {height}). Wähle eine neue Position."
    )]
    PositionOutsideStream {
        x: u32,
        y: u32,
        width: i32,
        height: i32,
    },
    #[error("Der Klick konnte nicht ausgeführt werden: {0}")]
    Send(#[source] ashpd::Error),
    #[error("KDE hat die Maussteuerung nicht rechtzeitig bestätigt. Versuche den Start erneut.")]
    EventTimeout,
}

pub struct PortalClickSession {
    connection: ashpd::zbus::Connection,
    portal: RemoteDesktop,
    session: Arc<Session<RemoteDesktop>>,
    closed: ClosedWatcher,
    stream: Option<MonitorStream>,
}

type ClosedWatcher = Pin<Box<dyn FusedFuture<Output = ()> + Send>>;

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
            result = ashpd::zbus::Connection::session() =>
                result.map_err(|error| PortalError::Unavailable(error.into()))?,
        };
        let mut session = None;
        let mut closed = None;
        let result = tokio::select! {
            biased;
            _ = &mut cancel => Err(PortalError::Cancelled),
            result = Self::create_on(&connection, &mut session, &mut closed, monitor) => result,
        };
        match result {
            Ok((portal, stream)) => {
                let mut closed = closed.ok_or(PortalError::SessionWatchUnavailable)?;
                if closed.is_terminated() || closed.as_mut().now_or_never().is_some() {
                    if let Some(session) = session {
                        let _ = timeout(CLOSE_TIMEOUT, session.close()).await;
                    }
                    let _ = timeout(CLOSE_TIMEOUT, connection.close()).await;
                    return Err(PortalError::SessionClosed);
                }
                Ok(Self {
                    connection,
                    portal,
                    session: session.ok_or(PortalError::Cancelled)?,
                    closed,
                    stream,
                })
            }
            Err(error) => {
                if let Some(session) = session {
                    let _ = timeout(CLOSE_TIMEOUT, session.close()).await;
                }
                let _ = timeout(CLOSE_TIMEOUT, connection.close()).await;
                Err(error)
            }
        }
    }

    /// Negotiate permission while exposing the session to cancellation cleanup.
    async fn create_on(
        connection: &ashpd::zbus::Connection,
        owned_session: &mut Option<Arc<Session<RemoteDesktop>>>,
        owned_closed: &mut Option<ClosedWatcher>,
        monitor: Option<MonitorGeometry>,
    ) -> Result<(RemoteDesktop, Option<MonitorStream>), PortalError> {
        let fixed_position = monitor.is_some();
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

        *owned_session = Some(Arc::new(
            portal
                .create_session(Default::default())
                .await
                .map_err(PortalError::Unavailable)?,
        ));
        let session = owned_session.as_ref().ok_or(PortalError::Cancelled)?;
        let watched_session = Arc::clone(session);
        let (ready_tx, ready_rx) = oneshot::channel();
        let mut closed: ClosedWatcher = Box::pin(
            async move {
                if let Ok(mut events) = watched_session.receive_closed().await {
                    let _ = ready_tx.send(());
                    let _ = events.next().await;
                }
            }
            .fuse(),
        );
        let watching = timeout(CLOSE_TIMEOUT, async {
            tokio::select! {
                result = ready_rx => result.is_ok(),
                _ = &mut closed => false,
            }
        })
        .await
        .unwrap_or(false);
        if !watching {
            return Err(PortalError::SessionWatchUnavailable);
        }
        *owned_closed = Some(closed);
        let closed = owned_closed
            .as_mut()
            .ok_or(PortalError::SessionWatchUnavailable)?;
        let permission = async {
            portal
                .select_devices(
                    session,
                    SelectDevicesOptions::default()
                        .set_devices(Some(DeviceType::Pointer.into()))
                        .set_persist_mode(PersistMode::Application),
                )
                .await
                .map_err(PortalError::Unavailable)?;

            if fixed_position {
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

            let stream = if fixed_position {
                let Some(stream) = selected.streams().first() else {
                    return Err(PortalError::MissingMonitorStream);
                };
                let Some((width, height)) = stream.size() else {
                    return Err(PortalError::MissingMonitorStream);
                };
                if let Some(expected) = monitor
                    && let Err(error) =
                        validate_monitor(expected, stream.position(), (width, height))
                {
                    return Err(error);
                }
                Some(MonitorStream {
                    node_id: stream.pipe_wire_node_id(),
                    position: stream.position(),
                    width,
                    height,
                })
            } else {
                None
            };

            Ok((portal, stream))
        };
        tokio::select! {
            biased;
            _ = closed.as_mut() => Err(PortalError::SessionClosed),
            result = permission => result,
        }
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

    /// Resolve when the portal revokes this session, including while no run is active.
    pub async fn wait_closed(&mut self) {
        self.closed.as_mut().await;
    }

    /// Poll a queued revocation before reusing a session for a new run.
    pub fn is_closed(&mut self) -> bool {
        self.closed.is_terminated() || self.closed.as_mut().now_or_never().is_some()
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
                    // A failed or timed-out press may still have reached KWin.
                    let _ = self.send_button(button, KeyState::Released).await;
                    return Err(error);
                }
            }
        }
        Ok(())
    }

    /// Send each button transition with the same timeout and error handling.
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

    /// Close the portal session after clicking stops or permissions change.
    pub async fn close(self) {
        let _ = timeout(CLOSE_TIMEOUT, self.session.close()).await;
        let _ = timeout(CLOSE_TIMEOUT, self.connection.close()).await;
    }
}

/// Reject missing, mismatched or invalid monitor metadata before clicking.
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
