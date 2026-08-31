#include "qml_runtime.h"

bool klickmeisterQmlEngineHasRootObject(const QQmlApplicationEngine& engine)
{
    return !engine.rootObjects().isEmpty();
}
