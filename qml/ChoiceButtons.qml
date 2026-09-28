import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Segmented buttons; assistive technology sees them as a radio group.
RowLayout {
    id: choices

    property var options: []
    property var value
    property bool iconOnly: false
    signal selected(var choice)

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: choices.options

        Controls.Button {
            id: option

            required property var modelData
            readonly property string description: modelData.description ?? modelData.text

            checkable: true
            autoExclusive: true
            checked: modelData.value === choices.value
            text: modelData.text
            icon.name: modelData.icon ?? ""
            display: choices.iconOnly ? Controls.AbstractButton.IconOnly : Controls.AbstractButton.TextBesideIcon
            onClicked: choices.selected(modelData.value)

            Controls.ToolTip.text: description
            Controls.ToolTip.visible: hovered && description !== text
            Controls.ToolTip.delay: Kirigami.Units.toolTipDelay

            Accessible.role: Accessible.RadioButton
            Accessible.name: description
            Accessible.onPressAction: option.clicked()
            Accessible.onToggleAction: option.clicked()
        }
    }
}
