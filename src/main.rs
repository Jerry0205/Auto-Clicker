use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QQuickStyle, QString, QUrl};

fn main() {
    QQuickStyle::set_style(&QString::from("org.kde.desktop"));

    let mut app = QGuiApplication::new();
    let mut app_pin = app.pin_mut();
    app_pin
        .as_mut()
        .set_application_name(&QString::from("klickmeister"));
    app_pin
        .as_mut()
        .set_application_display_name(&QString::from("Klickmeister"));
    app_pin
        .as_mut()
        .set_application_version(&QString::from(env!("CARGO_PKG_VERSION")));
    app_pin
        .as_mut()
        .set_organization_name(&QString::from("Klickmeister"));

    let mut engine = QQmlApplicationEngine::new();
    let mut engine_pin = engine.pin_mut();
    engine_pin.as_mut().load(&QUrl::from(
        "qrc:/qt/qml/io/github/jerry0205/klickmeister/qml/Main.qml",
    ));
    let _ = app_pin.exec();
}
