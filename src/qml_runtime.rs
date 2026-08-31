#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("klickmeister/src/qml_runtime.h");

        type QQmlApplicationEngine = cxx_qt_lib::QQmlApplicationEngine;

        #[rust_name = "qml_engine_has_root_object"]
        fn klickmeisterQmlEngineHasRootObject(engine: &QQmlApplicationEngine) -> bool;
    }
}

/// Checks whether the QML engine has successfully loaded a root object.
///
/// Returns false if QML loading failed, indicating the application should exit.
pub fn has_root_object(engine: &cxx_qt_lib::QQmlApplicationEngine) -> bool {
    ffi::qml_engine_has_root_object(engine)
}
