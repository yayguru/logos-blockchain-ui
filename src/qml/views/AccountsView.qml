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
    function clearPending() { d.created = null }

    // windows.17: { lib_slot, accounts: [{ public_key, received_lepta, first_slot, ... }] }
    // from the backend. Pending = made while the node runs; the node lists it
    // from its next start, and nothing forces that start.
    property var pendingInfo: null
    readonly property var pendingReceipts: {
        const out = []
        const info = root.pendingInfo
        if (!info || !info.accounts)
            return out
        for (let i = 0; i < info.accounts.length; ++i) {
            const a = info.accounts[i]
            if (String(a.received_lepta || "0") !== "0" && Number(a.first_slot) > 0)
                out.push({ pk: String(a.public_key), lepta: String(a.received_lepta),
                           left: Number(a.first_slot) - Number(info.lib_slot || 0) })
        }
        return out
    }
    readonly property int pendingCount: root.pendingInfo && root.pendingInfo.accounts ? root.pendingInfo.accounts.length : 0

    QtObject {
        id: d
        property bool showCreate: false
        property bool createBusy: false
        property string createError: ""
        property var created: null
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
                    text: qsTr("Your keys are backed up first, then a new key is added. Its address works at once (copy it or show the QR code); the node starts listing its balance the next time it starts. No restart needed.")
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

        // ---- Created: usable now, no restart ----
        LogosNotice {
            objectName: "accountCreatedNotice"
            Layout.fillWidth: true
            shown: !!d.created
            severity: LogosNotice.Success
            title: d.created ? qsTr("“%1” created").arg(d.created.title) : ""
            message: d.created
                     ? (qsTr("Keys backed up to Documents\\LogosBackups (%1 files).").arg((d.created.backups || []).length)
                        + (d.created.backup_after_ok === false ? qsTr(" Back up again in Settings.") : "")
                        + "\n" + qsTr("Its address can receive LGO now. Incoming transfers show on its card right away; the node adds them to its spendable balance when it next starts. Nothing to restart now."))
                     : ""
            actions: [
                LogosButton {
                    text: qsTr("Close")
                    onClicked: d.created = null
                }
            ]
        }

        // ---- Something arrived at a pending account ----
        LogosNotice {
            objectName: "pendingReceiptNotice"
            Layout.fillWidth: true
            shown: root.pendingReceipts.length > 0
            severity: LogosNotice.Warning
            title: qsTr("LGO arrived at a new account")
            message: {
                if (root.pendingReceipts.length === 0)
                    return ""
                let left = Infinity
                for (let i = 0; i < root.pendingReceipts.length; ++i)
                    left = Math.min(left, root.pendingReceipts[i].left)
                const h = Math.max(0, Math.floor(left / 3600)), m = Math.max(0, Math.floor((left % 3600) / 60))
                return qsTr("The funds are on chain and safe. The node adds them to its spendable balance when it next starts, and that start has to happen within about %1 h %2 min while it can still re-read those blocks. If it has not restarted by about an hour before that, the app restarts it once by itself (about a minute; mining resumes).").arg(h).arg(m)
            }
            actions: [
                LogosButton {
                    text: qsTr("Apply now (restarts the node)")
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
                pendingRestart: !!model.pending
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
