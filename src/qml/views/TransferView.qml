import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units
import "../WalletTools.js" as WalletTools

// Transfer funds panel. Extracted from the former WalletView.
ColumnLayout {
    id: root

    // Rows, not the remoted model: the replica lands count-first, and a combo's
    // currentValue reads at currentIndex — so a quick Send could transfer from
    // an empty key. A QVariantList lands whole.
    required property var accountRows

    property bool nodeRunning: false
    // Why the node cannot answer, or empty when it can.
    property string nodeOffReason: ""
    // A LogosNotice.Severity for the banner above.
    property int nodeOffSeverity: LogosNotice.Info

    signal transferRequested(string fromKeyHex, string toKeyHex, string amount)
    // Fee preview: the host answers with setGasPrices(success, json).
    signal gasPricesRequested()
    signal copyToClipboard(string text)

    // The selected source's balance, for the availability check below. Reading
    // the row rather than currentValue: currentValue is the address.
    readonly property var fromRow:
        transferFromCombo.currentIndex >= 0
        && transferFromCombo.currentIndex < accountRows.length
            ? accountRows[transferFromCombo.currentIndex] : null
    readonly property string fromBalance: fromRow ? (fromRow.balance || "") : ""

    // parseAmount takes '.' or ',' on any locale and refuses (with a reason)
    // anything it cannot read exactly.
    readonly property var amountParse: Units.parseAmount(transferAmountField.text)
    readonly property string amountLepta: amountParse.lepta
    readonly property string amountError: amountParse.error
    // NaN when either side is not a figure — an unfetched balance cannot say
    // anything about affordability, so it must not read as "insufficient".
    readonly property bool overBalance:
        Units.compareLepta(amountLepta, fromBalance) > 0

    property string resultHash: ""
    property string resultError: ""

    // "" when the recipient is a usable wallet key, else the reason.
    readonly property string toError:
        transferToField.text.trim().length > 0
            ? WalletTools.walletKeyError(transferToField.text) : ""
    readonly property bool formValid:
        String(transferFromCombo.currentValue || "").trim().length > 0
        && transferToField.text.trim().length > 0
        && root.toError.length === 0
        && root.amountLepta.length > 0
        && root.amountLepta !== "0"
        && !root.overBalance

    function setTransferHash(hash) {
        root.resultHash = hash
        root.resultError = ""
        d.sending = false
        // A sent review is spent: a second click must not send it again.
        d.reviewing = false
        confirmSwitch.checked = false
    }

    function setTransferError(message) {
        root.resultError = message
        root.resultHash = ""
        d.sending = false
    }

    function setGasPrices(success, text) {
        d.pricesPending = false
        var ep = 1, sp = 7
        d.pricesLive = false
        if (success) {
            try {
                var o = JSON.parse(text)
                if (o.execution_base_gas_price !== undefined && o.storage_gas_price !== undefined) {
                    ep = Number(o.execution_base_gas_price)
                    sp = Number(o.storage_gas_price)
                    d.pricesLive = true
                }
            } catch (e) {}
        }
        d.feeLepta = WalletTools.estimateTransferFee(ep, sp)
        d.ep = ep
        d.sp = sp
    }

    QtObject {
        id: d
        property bool reviewing: false
        property bool sending: false
        property bool pricesPending: false
        property bool pricesLive: false
        property int feeLepta: 0
        property int ep: 0
        property int sp: 0
        // Snapshot of what was reviewed, so the confirm sends exactly that.
        property string fromKey: ""
        property string fromLabel: ""
        property string toKey: ""
        property string amount: ""
        property string amountLepta: ""
    }

    spacing: Theme.spacing.large

    NodeOffNotice {
        reason: root.nodeOffReason
        reasonSeverity: root.nodeOffSeverity
    }

    // No container of its own — WalletView provides the page surface. The form's
    // rows sit directly in the root layout.
    LogosScrollView {
        id: transferScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

    ColumnLayout {
        width: transferScroll.availableWidth
        spacing: Theme.spacing.small

        FieldLabel { text: qsTr("From") }

        LogosComboBox {
            id: transferFromCombo
            Layout.fillWidth: true
            implicitHeight: 40
            background: Rectangle {
                radius: Theme.spacing.radiusSmall
                color: Theme.palette.backgroundSecondary
                border.width: 1
                border.color: transferFromCombo.activeFocus
                              ? Theme.palette.overlayOrange
                              : Theme.palette.backgroundElevated
            }
            model: root.accountRows
            textRole: "label"
            valueRole: "address"
            placeholderText: qsTr("From account")
            objectName: "transferFromCombo"
            enabled: !d.reviewing
            editable: false

            delegate: LogosItemDelegate {
                required property var modelData
                required property int index
                width: transferFromCombo.width
                implicitHeight: Math.max(
                    36, implicitContentHeight + topPadding + bottomPadding)
                highlighted: transferFromCombo.highlightedIndex === index
                contentItem: AccountSummary {
                    keyName: modelData.name || ""
                    roleLabel: modelData.roleLabel || ""
                    address: modelData.address || ""
                    balance: modelData.balance || ""
                }
            }
        }

        FieldLabel { text: qsTr("To"); Layout.topMargin: Theme.spacing.small }

        LogosTextField {
            id: transferToField
            objectName: "transferToField"
            Layout.fillWidth: true
            placeholderText: qsTr("Recipient key — 64 hex characters")
            enabled: !d.reviewing
            Accessible.name: qsTr("Recipient wallet key")
        }

        LogosText {
            Layout.fillWidth: true
            visible: root.toError.length > 0
            text: qsTr(root.toError)
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.error
            wrapMode: Text.WordWrap
            Accessible.name: text
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.small
            FieldLabel { text: qsTr("Amount (%1)").arg(Units.SYMBOL) }
            LogosText {
                Layout.alignment: Qt.AlignRight
                visible: text.length > 0
                text: Units.format(root.fromBalance).length > 0
                      ? qsTr("Available: %1").arg(Units.format(root.fromBalance)) : ""
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
        }

        LogosTextField {
            id: transferAmountField
            objectName: "transferAmountField"
            Layout.fillWidth: true
            enabled: !d.reviewing
            Accessible.name: qsTr("Amount")
            placeholderText: qsTr("0.001 or 0,001")
        }

        LogosText {
            objectName: "transferAmountError"
            Layout.fillWidth: true
            visible: root.amountError.length > 0
            text: qsTr(root.amountError)
            Accessible.name: text
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.error
            wrapMode: Text.WordWrap
        }

        LogosText {
            objectName: "transferAmountBase"
            Layout.fillWidth: true
            visible: root.amountError.length === 0 && root.amountLepta.length > 0
            text: "= " + Units.format(root.amountLepta)
            Accessible.name: text
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }

        LogosText {
            Layout.fillWidth: true
            visible: root.overBalance
            text: qsTr("More than this account holds.")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.error
            wrapMode: Text.WordWrap
        }

        // Step 1: Review (fee preview). Step 2: Confirm and send.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.medium
            spacing: Theme.spacing.small
            visible: !d.reviewing

            LogosButton {
                id: transferButton
                objectName: "transferReviewButton"
                Layout.alignment: Qt.AlignTop
                text: qsTr("Review transfer")
                Accessible.name: text
                // A transfer needs a node to build and submit it. Without one
                // the form would take the details and fail at the module.
                enabled: root.nodeRunning && root.formValid && !d.sending
                onClicked: {
                    d.fromKey = String(transferFromCombo.currentValue || "").trim()
                    d.fromLabel = transferFromCombo.currentText
                    d.toKey = WalletTools.normalizeWalletKey(transferToField.text)
                    d.amount = root.amountParse.canonical
                    d.amountLepta = root.amountLepta
                    root.resultHash = ""
                    root.resultError = ""
                    confirmSwitch.checked = false
                    d.feeLepta = 0
                    d.pricesPending = true
                    d.reviewing = true
                    root.gasPricesRequested()
                }
            }
        }

        LogosFrame {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.medium
            visible: d.reviewing
            padding: Theme.spacing.medium
            backgroundColor: Theme.palette.surfaceRecessed
            borderColor: "transparent"
            radius: Theme.spacing.radiusMedium

            contentItem: ColumnLayout {
                spacing: Theme.spacing.small

                LogosText {
                    Layout.fillWidth: true
                    text: qsTr("Check the transfer. Nothing has been sent yet.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                    wrapMode: Text.WordWrap
                }
                LogosText {
                    Layout.fillWidth: true
                    text: qsTr("From: %1").arg(d.fromLabel)
                    wrapMode: Text.WrapAnywhere
                }
                LogosText {
                    Layout.fillWidth: true
                    text: qsTr("To: %1").arg(d.toKey)
                    wrapMode: Text.WrapAnywhere
                    Accessible.name: text
                }
                LogosText {
                    Layout.fillWidth: true
                    text: qsTr("Amount: %1").arg(Units.format(d.amountLepta))
                    wrapMode: Text.WordWrap
                    Accessible.name: text
                }
                LogosText {
                    objectName: "transferFeePreview"
                    Layout.fillWidth: true
                    text: d.pricesPending
                          ? qsTr("Estimating fee…")
                          : qsTr("Fee ≈ %1%2, paid from the same account%3.")
                                .arg(Units.format(String(d.feeLepta)))
                                .arg("")
                                .arg(d.pricesLive ? qsTr(" at gas prices %1/%2").arg(d.ep).arg(d.sp)
                                                  : qsTr(" (gas prices unavailable, default 1/7 used)"))
                    wrapMode: Text.WordWrap
                    Accessible.name: text
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosSwitch {
                        id: confirmSwitch
                        objectName: "transferConfirmSwitch"
                        checked: false
                        Accessible.name: qsTr("I checked the recipient and amount")
                    }
                    LogosText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("I checked the recipient and amount. A transfer cannot be undone.")
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosButton {
                        objectName: "transferEditButton"
                        text: qsTr("Edit")
                        Accessible.name: text
                        enabled: !d.sending
                        onClicked: { d.reviewing = false; confirmSwitch.checked = false }
                    }
                    Item { Layout.fillWidth: true }
                    LogosButton {
                        objectName: "transferConfirmButton"
                        text: qsTr("Confirm and send")
                        Accessible.name: text
                        enabled: root.nodeRunning && !d.sending && !d.pricesPending
                                 && confirmSwitch.checked
                        onClicked: {
                            d.sending = true
                            // Canonical tokens; the backend scales it to lepta.
                            root.transferRequested(d.fromKey, d.toKey, d.amount)
                        }
                    }
                }
                LogosText {
                    visible: d.sending
                    text: qsTr("Sending…")
                    color: Theme.palette.textSecondary
                }
            }
        }

        LogosNotice {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.medium

            readonly property bool sent: root.resultHash.length > 0

            severity: sent ? LogosNotice.Success : LogosNotice.Error
            title: sent ? qsTr("Transaction sent") : qsTr("Transfer failed")
            message: sent ? root.resultHash : root.resultError
            Accessible.name: (sent ? "Transaction sent " : "Transfer failed ") + message
            shown: sent || root.resultError.length > 0
            closable: false

            actions: [
                LogosCopyButton {
                    visible: root.resultHash.length > 0
                    value: root.resultHash
                }
            ]
        }
    }
    }

    component FieldLabel: LogosText {
        Layout.fillWidth: true
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
    }
}
