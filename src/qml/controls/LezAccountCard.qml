import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

// The wallet's own LEZ public account (lez_account.json beside the keystore).
// Shows the address and balance, or a one-click "Create LEZ account". The
// secret key never reaches QML: back it up from Settings › Back up your keys.
LogosFrame {
    id: root
    objectName: "lezAccountCard"

    property bool supported: false
    property var account: ({ exists: false })
    property string balance: ""
    property string error: ""
    property bool busy: false
    property bool showUseButton: false

    signal createRequested()
    signal refreshRequested()
    signal useRequested(string accountId)
    signal copyToClipboard(string text)

    readonly property bool hasAccount: !!account && account.exists === true

    Layout.fillWidth: true
    visible: supported
    padding: Theme.spacing.medium
    backgroundColor: Theme.palette.surfaceRecessed
    borderColor: "transparent"
    radius: Theme.spacing.radiusMedium

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            LogosText {
                Accessible.name: text
                text: qsTr("Your LEZ account")
                font.weight: Theme.typography.weightMedium
            }
            LogosBadge {
                visible: root.hasAccount && root.account.backed_up !== true
                text: qsTr("Not backed up")
                color: Theme.palette.warning
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "lezRefreshButton"
                visible: root.hasAccount
                text: qsTr("Refresh")
                onClicked: root.refreshRequested()
            }
            LogosButton {
                objectName: "lezUseAccountButton"
                visible: root.hasAccount && root.showUseButton
                text: qsTr("Use as recipient")
                onClicked: root.useRequested(root.account.account_id)
            }
            LogosButton {
                objectName: "lezCreateAccountButton"
                visible: !root.hasAccount
                variant: LogosButton.Variant.Primary
                enabled: !root.busy
                text: root.busy ? qsTr("Creating…") : qsTr("Create LEZ account")
                onClicked: root.createRequested()
            }
        }

        LogosText {
            Accessible.name: text
            Layout.fillWidth: true
            visible: !root.hasAccount
            wrapMode: Text.WordWrap
            text: qsTr("No LEZ account yet. Create one here: its key is generated on this computer and "
                       + "saved as lez_account.json next to your keystore, and it becomes the default "
                       + "destination for the LEZ bridge.")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.hasAccount
            spacing: Theme.spacing.small
            LogosText {
                objectName: "lezAccountId"
                Layout.fillWidth: true
                text: root.hasAccount ? root.account.account_id : ""
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                elide: Text.ElideMiddle
                Accessible.name: qsTr("LEZ account %1").arg(text)
            }
            LogosCopyButton {
                value: root.hasAccount ? root.account.account_id : ""
            }
        }

        LogosText {
            Accessible.name: text
            objectName: "lezAccountBalance"
            visible: root.hasAccount
            text: root.balance.length
                  ? qsTr("Balance: %1 (%2 base units)").arg(Units.format(root.balance)).arg(root.balance)
                  : qsTr("Balance: —")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.text
        }

        LogosText {
            Accessible.name: text
            Layout.fillWidth: true
            visible: root.hasAccount && root.account.backed_up !== true
            wrapMode: Text.WordWrap
            text: qsTr("Back up its key: Settings › Back up your keys › Download lez_account.json. "
                       + "It can be imported into the LEZ wallet (wallet account import public).")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textTertiary
        }

        LogosText {
            Accessible.name: text
            Layout.fillWidth: true
            visible: root.error.length > 0
            wrapMode: Text.WordWrap
            text: root.error
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.error
        }
    }
}
