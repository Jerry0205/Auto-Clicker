use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("io.github.jerry0205.klickmeister")
            .qml_file("qml/Main.qml")
            .qml_file("qml/PositionPicker.qml"),
    )
    .qt_module("Network")
    .files(["src/controller.rs"])
    .build();
}
