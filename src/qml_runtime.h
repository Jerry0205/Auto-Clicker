#pragma once

#include <QtQml/QQmlApplicationEngine>

/// Checks whether the QML engine has successfully loaded at least one root object.
///
/// @param engine The QML application engine to check.
/// @return true if the engine has root objects, false otherwise.
bool klickmeisterQmlEngineHasRootObject(const QQmlApplicationEngine& engine);
