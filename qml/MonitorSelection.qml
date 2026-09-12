import QtQuick

QtObject {
    // Include the connector and hardware identity; geometry changes require confirmation.
    function identity(screen) {
        return JSON.stringify([screen.name, screen.manufacturer, screen.model,
            screen.serialNumber, screen.width, screen.height, screen.devicePixelRatio])
    }

    // Restore only an unambiguous match, never the first of several similar monitors.
    function restoreIndex(screens, savedIdentity) {
        if (!savedIdentity) return -1
        let match = -1
        for (let i = 0; i < screens.length; ++i) {
            if (identity(screens[i]) !== savedIdentity) continue
            if (match !== -1) return -1
            match = i
        }
        return match
    }
}
