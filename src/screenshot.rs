//! Screenshot requests with an explicit, cancellable portal handle.
//!
//! ashpd 0.13 waits for the response before exposing its Request. Using the
//! underlying typed D-Bus calls here lets cancellation close the active dialog.
//! Interactive capture avoids the synchronous first-permission AccessDialog in
//! xdg-desktop-portal 1.22.1, which holds the lock needed by Request.Close.
use std::{collections::HashMap, future::Future, time::Duration};

use ashpd::zbus::{
    self,
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};
use futures_util::StreamExt;
use tokio::{sync::oneshot, time::timeout};

const PORTAL: &str = "org.freedesktop.portal.Desktop";
const CAPTURE_TIMEOUT: Duration = Duration::from_secs(30);
const CLOSE_TIMEOUT: Duration = Duration::from_secs(1);

/// Capture a local screenshot; cancellation also closes the portal interaction.
pub async fn capture(mut cancel: oneshot::Receiver<()>) -> Result<String, String> {
    // A private connection also bounds cleanup if the portal stops responding
    // while creating or closing the request. It never owns the click session.
    let connection = tokio::select! {
        _ = &mut cancel => return Err("Bildschirmaufnahme abgebrochen.".to_owned()),
        result = timeout(CAPTURE_TIMEOUT, zbus::Connection::session()) =>
            result.map_err(|_| "Screenshot-Verbindung dauert zu lange.".to_owned())?
                .map_err(|error| error.to_string())?,
    };
    let result = capture_on(&connection, PORTAL, &mut cancel).await;
    let _ = timeout(CLOSE_TIMEOUT, connection.close()).await;
    result
}

/// Subscribe before requesting the screenshot to avoid losing a fast response.
async fn capture_on(
    connection: &zbus::Connection,
    destination: &str,
    cancel: &mut oneshot::Receiver<()>,
) -> Result<String, String> {
    let sender = connection
        .unique_name()
        .ok_or("Screenshot-Verbindung hat keinen Namen.")?
        .as_str()
        .trim_start_matches(':')
        .replace('.', "_");
    let mut random = [0u8; 16];
    getrandom::fill(&mut random).map_err(|error| error.to_string())?;
    let token = format!("klickmeister_{:032x}", u128::from_ne_bytes(random));
    let mut path = format!("/org/freedesktop/portal/desktop/request/{sender}/{token}");
    // Keep the path outside the future so cleanup can close it even if the
    // Screenshot method itself has not returned yet.
    let operation = async {
        let request = zbus::Proxy::new(
            connection,
            destination,
            path.as_str(),
            "org.freedesktop.portal.Request",
        )
        .await
        .map_err(|error| error.to_string())?;
        let mut responses = request
            .receive_signal("Response")
            .await
            .map_err(|error| error.to_string())?;
        let portal = zbus::Proxy::new(
            connection,
            destination,
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot",
        )
        .await
        .map_err(|error| error.to_string())?;
        let options = HashMap::from([
            ("handle_token", Value::from(token.as_str())),
            ("interactive", Value::from(true)),
        ]);
        let returned: OwnedObjectPath = portal
            .call("Screenshot", &("", options))
            .await
            .map_err(|error| error.to_string())?;
        if returned.as_str() != path {
            // Older portals can return a different handle. Close that actual
            // request instead of assuming the predicted path was accepted.
            drop(responses);
            drop(request);
            path = returned.to_string();
            return Err(
                "Das Screenshot-Portal unterstützt keine vorab bekannte Anfragekennung.".to_owned(),
            );
        }
        let message = responses
            .next()
            .await
            .ok_or("Keine Antwort auf die Bildschirmaufnahme.")?;
        let (status, results): (u32, HashMap<String, OwnedValue>) = message
            .body()
            .deserialize()
            .map_err(|error| error.to_string())?;
        if status != 0 {
            return Err("Bildschirmaufnahme abgelehnt oder abgebrochen.".to_owned());
        }
        let uri = results
            .get("uri")
            .and_then(|value| <&str>::try_from(value).ok())
            .ok_or("Die Bildschirmaufnahme enthält keine Datei-Adresse.")?;
        if !uri.starts_with("file://") {
            return Err("Die Bildschirmaufnahme ist keine lokale Datei.".to_owned());
        }
        Ok(uri.to_owned())
    };
    let result = wait_for_capture(operation, cancel, CAPTURE_TIMEOUT).await;
    // Also close on errors: an unsuccessful method/response need not imply
    // that a buggy backend has already dismissed its interaction.
    if result.is_err() {
        let _ = timeout(CLOSE_TIMEOUT, async {
            let request = zbus::Proxy::new(
                connection,
                destination,
                path.as_str(),
                "org.freedesktop.portal.Request",
            )
            .await?;
            request.call::<_, _, ()>("Close", &()).await
        })
        .await;
    }
    result
}

/// Race response, cancellation and timeout without aborting the cleanup owner.
async fn wait_for_capture<T>(
    operation: impl Future<Output = Result<T, String>>,
    cancel: &mut oneshot::Receiver<()>,
    duration: Duration,
) -> Result<T, String> {
    tokio::select! {
        biased;
        _ = cancel => Err("Bildschirmaufnahme abgebrochen.".to_owned()),
        result = timeout(duration, operation) => result.unwrap_or_else(|_| Err("Zeitüberschreitung bei der Bildschirmaufnahme.".to_owned())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn cancellation_wins_over_ready_capture() {
        let (tx, mut rx) = oneshot::channel();
        assert!(tx.send(()).is_ok());
        assert!(
            wait_for_capture(async { Ok(()) }, &mut rx, CAPTURE_TIMEOUT)
                .await
                .is_err()
        );
    }

    #[tokio::test]
    async fn dropping_owner_cancels_inflight_capture() {
        let (tx, mut rx) = oneshot::channel();
        drop(tx);
        assert!(
            wait_for_capture(
                std::future::pending::<Result<(), String>>(),
                &mut rx,
                CAPTURE_TIMEOUT
            )
            .await
            .is_err()
        );
    }

    #[tokio::test]
    async fn unanswered_capture_times_out() {
        let (_tx, mut rx) = oneshot::channel();
        let error = wait_for_capture(
            std::future::pending::<Result<(), String>>(),
            &mut rx,
            Duration::from_millis(1),
        )
        .await;
        assert!(error.is_err_and(|error| error.contains("Zeitüberschreitung")));
    }

    struct FakeRequest(std::sync::Arc<std::sync::atomic::AtomicUsize>);

    #[zbus::interface(name = "org.freedesktop.portal.Request", crate = "ashpd::zbus")]
    impl FakeRequest {
        async fn close(&self) {
            self.0.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        }
    }

    struct FakeScreenshot {
        started: std::sync::Arc<tokio::sync::Notify>,
        closed: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    }

    #[zbus::interface(name = "org.freedesktop.portal.Screenshot", crate = "ashpd::zbus")]
    impl FakeScreenshot {
        async fn screenshot(
            &self,
            _parent: &str,
            options: HashMap<String, OwnedValue>,
            #[zbus(connection)] connection: &zbus::Connection,
            #[zbus(header)] header: zbus::message::Header<'_>,
        ) -> zbus::fdo::Result<OwnedObjectPath> {
            assert_eq!(
                options
                    .get("interactive")
                    .and_then(|value| bool::try_from(value).ok()),
                Some(true),
                "non-interactive first permission can deadlock the desktop portal"
            );
            let sender = header
                .sender()
                .ok_or_else(|| zbus::fdo::Error::Failed("missing sender".into()))?
                .as_str()
                .trim_start_matches(':')
                .replace('.', "_");
            let token = options
                .get("handle_token")
                .and_then(|value| <&str>::try_from(value).ok())
                .ok_or_else(|| zbus::fdo::Error::Failed("missing token".into()))?;
            let path = OwnedObjectPath::try_from(format!(
                "/org/freedesktop/portal/desktop/request/{sender}/{token}"
            ))
            .map_err(|error| zbus::fdo::Error::Failed(error.to_string()))?;
            connection
                .object_server()
                .at(path.clone(), FakeRequest(self.closed.clone()))
                .await?;
            self.started.notify_one();
            Ok(path)
        }
    }

    /// Run on a private bus: dbus-run-session cargo test closes_real_dbus_request -- --ignored.
    #[tokio::test]
    #[ignore = "requires a private D-Bus session via dbus-run-session"]
    async fn closes_real_dbus_request() -> Result<(), Box<dyn std::error::Error>> {
        use std::sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        };
        let started = Arc::new(tokio::sync::Notify::new());
        let closed = Arc::new(AtomicUsize::new(0));
        let service = zbus::connection::Builder::session()?
            .name("io.github.klickmeister.TestScreenshot")?
            .serve_at(
                "/org/freedesktop/portal/desktop",
                FakeScreenshot {
                    started: started.clone(),
                    closed: closed.clone(),
                },
            )?
            .build()
            .await?;
        let connection = zbus::Connection::session().await?;
        // Replacing a capture and worker shutdown use the same cancellation
        // channel. Both must issue Close, not merely drop their futures.
        for drop_sender in [false, true] {
            let (tx, mut rx) = oneshot::channel();
            let result = async {
                started.notified().await;
                if drop_sender {
                    drop(tx);
                } else {
                    let _ = tx.send(());
                }
            };
            let (capture, ()) = timeout(Duration::from_secs(5), async {
                tokio::join!(
                    capture_on(
                        &connection,
                        "io.github.klickmeister.TestScreenshot",
                        &mut rx
                    ),
                    result
                )
            })
            .await?;
            assert!(capture.is_err());
        }
        assert_eq!(closed.load(Ordering::SeqCst), 2);
        connection.close().await?;
        service.close().await?;
        Ok(())
    }
}
