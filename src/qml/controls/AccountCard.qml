import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

// One wallet account: name, what it is for, balance in tokens, short address
// with copy, and Receive / Rename.
LogosFrame {
    id: root

    property string name: ""
    property string roleLabel: ""
    property string address: ""
    property string balance: ""   // base units, as the node reports them
    property bool pendingRestart: false

    signal receiveRequested(string address)
    signal renameRequested(string address, string currentName)

    readonly property string title: name.length > 0 ? name
                                  : (roleLabel.length > 0 ? roleLabel : qsTr("Account"))
    readonly property bool known: /^[0-9]+$/.test(balance)

    Layout.fillWidth: true
    padding: Theme.spacing.medium
    backgroundColor: Theme.palette.surfaceRecessed
    borderColor: "transparent"
    radius: Theme.spacing.radiusMedium

    contentItem: ColumnLayout {
        spacing: Theme.spacing.tiny

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                Layout.maximumWidth: Math.max(80, root.availableWidth * 0.55)
                text: root.title
                elide: Text.ElideRight
                font.weight: Theme.typography.weightBold
                Accessible.name: text
            }
            LogosBadge {
                visible: root.roleLabel.length > 0 && root.name.length > 0
                         && root.roleLabel.toLowerCase() !== root.name.toLowerCase()
                text: root.roleLabel
            }
            LogosBadge {
                objectName: "pendingBadge"
                visible: root.pendingRestart
                text: qsTr("activates on next node start")
                color: Theme.palette.warning
            }
            Item { Layout.fillWidth: true }
            LogosText {
                objectName: "accountBalance"
                text: root.known ? Units.format(root.balance) : "—"
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.tiny
            LogosText {
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                text: root.address
                elide: Text.ElideMiddle
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            LogosCopyButton {
                visible: root.address.length > 0
                value: root.address
            }
            LogosButton {
                objectName: "receiveButton"
                text: qsTr("Receive")
                compact: true
                enabled: root.address.length > 0
                onClicked: root.receiveRequested(root.address)
            }
            LogosButton {
                objectName: "renameButton"
                text: qsTr("Rename")
                compact: true
                enabled: root.address.length > 0
                onClicked: root.renameRequested(root.address, root.name)
            }
        }
    }
}
