import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Wallet › Accounts: one scrollable page, so nothing is cut off on a small
// screen. Accounts with balances, New account, Receive (address + QR), Rename,
// and the built-in LEZ account at the end.
LogosScrollView {
    id: root
    objectName: "accountsScroll"

    required property var accountsModel

    property string nodeOffReason: ""
    property int nodeOffSeverity: LogosNotice.Info
    property bool nodeRunning: false
    property bool keysBackedUp: true

    property bool lezSupported: false
    property var lezAccount: ({ exists: false })
    property string lezBalance: ""
    property string lezError: ""
    property bool lezBusy: false

    signal lezCreateRequested()
    signal lezRefreshRequested()
    signal refreshAccountsRequested()
    signal copyToClipboard(string text)
    signal createAccountRequested(string title)
    signal renameRequested(string address, string label)
    signal qrRequested(string text)
    signal restartNodeRequested()
    signal backupKeysRequested()

    // ---- Results back in ----
    function setCreateResult(success, value) {
        d.createBusy = false
        if (success) {
            d.createError = ""
            d.created = value || ({})
            const p = Object.assign({}, d.pending)
            p[String(d.created.public_key || "").toLowerCase()] = true
            d.pending = p
            newName.text = ""
            d.showCreate = false
        } else {
            d.created = null
            d.createError = String(value || qsTr("Could not create the account."))
        }
    }
    function setQr(success, value) {
        qr.matrix = success ? value : null
    }
    // Called once the node is back after a restart: the new keys are tracked.
    function clearPending() { d.pending = ({}); d.created = null }

    // A restart (stop, then run again) is what makes the node track new keys.
    onNodeRunningChanged: {
        if (Object.keys(d.pending).length === 0)
            return
        if (!nodeRunning)
            d.sawStop = true
        else if (d.sawStop) {
            d.sawStop = false
            clearPending()
            refreshAccountsRequested()
        }
    }

    QtObject {
        id: d
        property bool sawStop: false
        property bool showCreate: false
        property bool createBusy: false
        property string createError: ""
        property var created: null
        property var pending: ({})
        property string receiveAddress: ""
        property string receiveName: ""
        property string renameAddress: ""
    }

    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.spacing.medium

        NodeOffNotice {
            reason: root.nodeOffReason
            reasonSeverity: root.nodeOffSeverity
        }

        // Header: title + actions, always visible at the top of the page.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText {
                text: qsTr("Accounts")
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightBold
            }
            LogosText {
                visible: accountsRepeater.count > 0
                text: "· " + accountsRepeater.count
                color: Theme.palette.textSecondary
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "newAccountButton"
                text: d.showCreate ? qsTr("Cancel") : qsTr("+ New account")
                variant: d.showCreate ? LogosButton.Variant.Secondary : LogosButton.Variant.Primary
                enabled: !d.createBusy
                onClicked: { d.showCreate = !d.showCreate; d.createError = "" }
            }
            LogosButton {
                id: refreshButton
                text: qsTr("Refresh")
                enabled: root.nodeOffReason.length === 0
                onClicked: root.refreshAccountsRequested()
            }
        }

        // ---- New account ----
        LogosFrame {
            Layout.fillWidth: true
            visible: d.showCreate
            padding: Theme.spacing.medium
            backgroundColor: Theme.palette.surfaceRecessed
            borderColor: Theme.palette.primary
            radius: Theme.spacing.radiusMedium

            contentItem: ColumnLayout {
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("New account")
                    font.weight: Theme.typography.weightBold
                }
                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("① Your keys are backed up first  ② a new key is added  ③ restart the node to use it.")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosTextField {
                        id: newName
                        objectName: "newAccountName"
                        Layout.fillWidth: true
                        placeholderText: qsTr("Name (optional), e.g. Savings")
                        enabled: !d.createBusy
                    }
                    LogosButton {
                        objectName: "createAccountButton"
                        text: d.createBusy ? qsTr("Creating…") : qsTr("Create")
                        variant: LogosButton.Variant.Primary
                        enabled: !d.createBusy
                        onClicked: {
                            d.createBusy = true
                            d.createError = ""
                            root.createAccountRequested(newName.text)
                        }
                    }
                }
                LogosText {
                    Layout.fillWidth: true
                    visible: d.createError.length > 0
                    wrapMode: Text.WordWrap
                    text: d.createError
                    color: Theme.palette.error
                    font.pixelSize: Theme.typography.secondaryText
                }
            }
        }

        // ---- Created: restart to start tracking ----
        LogosNotice {
            objectName: "accountCreatedNotice"
            Layout.fillWidth: true
            shown: !!d.created
            severity: LogosNotice.Success
            title: d.created ? qsTr("“%1” created").arg(d.created.title) : ""
            message: d.created
                     ? (qsTr("Keys backed up to Documents\\LogosBackups (%1 files).").arg((d.created.backups || []).length)
                        + (d.created.backup_after_ok === false ? qsTr(" Back up again in Settings.") : "")
                        + "\n" + qsTr("Restart the node so it tracks the new account."))
                     : ""
            actions: [
                LogosButton {
                    text: qsTr("Restart node now")
                    variant: LogosButton.Variant.Primary
                    enabled: root.nodeRunning
                    onClicked: root.restartNodeRequested()
                }
            ]
        }

        LogosNotice {
            Layout.fillWidth: true
            shown: !root.keysBackedUp && !d.created
            severity: LogosNotice.Warning
            message: qsTr("Your keys are not backed up yet.")
            actions: [
                LogosButton {
                    text: qsTr("Back up now")
                    onClicked: root.backupKeysRequested()
                }
            ]
        }

        LogosText {
            text: qsTr("No accounts yet.")
            color: Theme.palette.textSecondary
            visible: accountsRepeater.count === 0 && root.nodeOffReason.length === 0
        }

        Repeater {
            id: accountsRepeater
            model: root.accountsModel
            delegate: AccountCard {
                required property var model
                name: model.name || ""
                roleLabel: model.roleLabel || ""
                address: model.address || ""
                balance: model.balance || ""
                pendingRestart: !!d.pending[String(model.address || "").toLowerCase()]
                onReceiveRequested: (address) => {
                    d.receiveAddress = address
                    d.receiveName = name.length ? name : roleLabel
                    qr.matrix = null
                    root.qrRequested(address)
                    receivePopup.open()
                }
                onRenameRequested: (address, currentName) => {
                    d.renameAddress = address
                    renameField.text = currentName
                    renamePopup.open()
                }
            }
        }

        LezAccountCard {
            supported: root.lezSupported
            account: root.lezAccount
            balance: root.lezBalance
            error: root.lezError
            busy: root.lezBusy
            onCreateRequested: root.lezCreateRequested()
            onRefreshRequested: root.lezRefreshRequested()
            onCopyToClipboard: (text) => root.copyToClipboard(text)
        }

        Item { Layout.preferredHeight: Theme.spacing.small }
    }

    // ---- Receive: address + QR ----
    Popup {
        id: receivePopup
        objectName: "receivePopup"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        padding: Theme.spacing.large
        width: Math.min(380, (parent ? parent.width : 380) - 40)
        background: Rectangle {
            color: Theme.palette.backgroundSecondary
            border.color: Theme.palette.border
            radius: Theme.spacing.radiusLarge
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium
            LogosText {
                text: d.receiveName.length ? qsTr("Receive to “%1”").arg(d.receiveName) : qsTr("Receive")
                font.weight: Theme.typography.weightBold
                font.pixelSize: Theme.typography.primaryText
            }
            QrCode {
                id: qr
                objectName: "receiveQr"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(220, receivePopup.availableWidth)
                Layout.preferredHeight: Layout.preferredWidth
            }
            LogosText {
                Layout.fillWidth: true
                text: d.receiveAddress
                wrapMode: Text.WrapAnywhere
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                horizontalAlignment: Text.AlignHCenter
            }
            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Share this address to receive tokens on the Logos blockchain.")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacing.small
                LogosButton {
                    text: qsTr("Copy address")
                    variant: LogosButton.Variant.Primary
                    onClicked: root.copyToClipboard(d.receiveAddress)
                }
                LogosButton {
                    text: qsTr("Close")
                    onClicked: receivePopup.close()
                }
            }
        }
    }

    // ---- Rename (display name only) ----
    Popup {
        id: renamePopup
        objectName: "renamePopup"
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        padding: Theme.spacing.large
        width: Math.min(380, (parent ? parent.width : 380) - 40)
        background: Rectangle {
            color: Theme.palette.backgroundSecondary
            border.color: Theme.palette.border
            radius: Theme.spacing.radiusLarge
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium
            LogosText {
                text: qsTr("Rename account")
                font.weight: Theme.typography.weightBold
            }
            LogosTextField {
                id: renameField
                Layout.fillWidth: true
                placeholderText: qsTr("Name (empty = default)")
            }
            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Only the name shown here changes. Keys stay as they are.")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing.small
                LogosButton { text: qsTr("Cancel"); onClicked: renamePopup.close() }
                LogosButton {
                    text: qsTr("Save")
                    variant: LogosButton.Variant.Primary
                    onClicked: { root.renameRequested(d.renameAddress, renameField.text); renamePopup.close() }
                }
            }
        }
    }
}
