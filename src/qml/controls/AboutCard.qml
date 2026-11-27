import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Settings › About: which build this is and which module it needs.
LogosFrame {
    id: root
    objectName: "aboutCard"

    property var info: ({})

    padding: Theme.spacing.medium
    backgroundColor: Theme.palette.surfaceRecessed
    borderColor: "transparent"
    radius: Theme.spacing.radiusMedium

    component Row2: RowLayout {
        property string k: ""
        property string v: ""
        Layout.fillWidth: true
        visible: v.length > 0
        LogosText {
            Layout.preferredWidth: 130
            text: parent.k
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosText {
            Layout.fillWidth: true
            text: parent.v
            elide: Text.ElideMiddle
            font.pixelSize: Theme.typography.secondaryText
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.tiny
        RowLayout {
            Layout.fillWidth: true
            LogosText {
                text: qsTr("About")
                font.weight: Theme.typography.weightBold
            }
            LogosBadge { text: root.info.build || qsTr("Unofficial Windows build") }
            Item { Layout.fillWidth: true }
        }
        Row2 { k: qsTr("Blockchain UI"); v: root.info.ui_version || "" }
        Row2 { k: qsTr("Needs module"); v: root.info.module_min ? qsTr("%1 or newer").arg(root.info.module_min) : "" }
        Row2 { k: qsTr("Node config"); v: root.info.config_path || "" }
        Row2 { k: qsTr("Keystore"); v: root.info.keystore_present === undefined ? "" : (root.info.keystore_present ? qsTr("found beside the config") : qsTr("not found")) }
        Row2 { k: qsTr("Maintainer"); v: "OPDE" }
        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Not an official Logos release. Includes QR Code generator by Project Nayuki (MIT).")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textTertiary
        }
    }
}
