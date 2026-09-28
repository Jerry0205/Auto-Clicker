use cxx_qt_lib::{
    QGuiApplication, QMap, QMapPair_QString_QVariant, QQmlApplicationEngine, QQuickStyle, QString,
    QUrl, QVariant,
};
use std::process::ExitCode;

const DESKTOP_FILE_NAME: &str = "io.github.jerry0205.klickmeister";

fn main() -> ExitCode {
    let smoke_test = std::env::args_os().any(|argument| argument == "--smoke-test");
    QQuickStyle::set_style(&QString::from("org.kde.desktop"));

    let mut app = QGuiApplication::new();
    QGuiApplication::set_desktop_file_name(&QString::from(DESKTOP_FILE_NAME));
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
    if smoke_test {
        let mut properties: QMap<QMapPair_QString_QVariant> = QMap::default();
        properties.insert_clone(&QString::from("smokeTest"), &QVariant::from(&smoke_test));
        engine_pin.as_mut().set_initial_properties(&properties);
    }
    engine_pin.as_mut().load(&QUrl::from(
        "qrc:/qt/qml/io/github/jerry0205/klickmeister/qml/Main.qml",
    ));
    if !klickmeister::qml_runtime::has_root_object(&engine) {
        eprintln!("Klickmeister konnte das eingebettete QML-Hauptfenster nicht laden.");
        return ExitCode::FAILURE;
    }
    if smoke_test {
        println!(
            "Qt desktop file name: {}",
            QGuiApplication::desktop_file_name()
        );
        return ExitCode::SUCCESS;
    }

    if app_pin.exec() == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
