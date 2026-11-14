import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units
import "../WalletTools.js" as WalletTools

// LEZ bridge: move an exact amount from a wallet account into a LEZ public
// account.
//
// On L1 this is a ChannelDeposit into the LEZ channel (0101…01 on the testnet)
// with the LEZ account's 32 bytes as metadata. A deposit consumes whole notes,
// so the form looks for a note worth exactly the amount. When there is none it
// first splits one off with an ordinary transfer to the same account, waits for
// that note to land, then deposits it — two transactions, both shown in the
// preview before anything is sent. The amount-based channel_deposit binding is
// not used: it builds an unfunded transaction that block builders skip.
ColumnLayout {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: true

    property var accountRows: []
    onAccountRowsChanged: {
        if (accountRows && accountRows.length > 0 && fromCombo.currentIndex < 0)
            fromCombo.currentIndex = 0
    }
    property bool nodeRunning: false
    property string nodeOffReason: ""
    property int nodeOffSeverity: LogosNotice.Info
    // From metadata.json (lez_channel_id). Editable under "Channel" if empty.
    property string lezChannelId: ""

    signal notesRequested(string addressHex)
    signal gasPricesRequested()
    signal splitRequested(string fromKeyHex, string amountTokens)
    signal depositRequested(string channelIdHex, var inputNoteIdHexes,
                            string metadataBase58, string changePublicKeyHex,
                            var fundingPublicKeyHexes, string maxTxFeeTokens)
    signal copyToClipboard(string text)

    // ---- Results from the host ----
    function setGasPrices(success, text) {
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
        d.ep = ep
        d.sp = sp
        d.pricesPending = false
        d.recomputePlan()
    }

    function setNotes(success, text) {
        if (!success) {
            if (d.phase === 1) {
                d.notesPending = false
                d.fail(qsTr("Could not read this account's notes: %1").arg(text))
            }
            // While waiting for the split note a failed poll is just retried.
            return
        }
        var notes = []
        try {
            notes = JSON.parse(text).notes || []
        } catch (e) {
            if (d.phase === 1) {
                d.notesPending = false
                d.fail(qsTr("Could not parse the notes answer."))
            }
            return
        }
        if (d.phase === 1) {
            d.notesPending = false
            var exact = WalletTools.findExactNote(notes, d.amountLepta, [])
            d.exactNoteId = exact ? exact.id : ""
            d.recomputePlan()
        } else if (d.phase === 2 && d.waitingForNote) {
            var fresh = WalletTools.findExactNote(notes, d.amountLepta, [])
            if (fresh) {
                d.waitingForNote = false
                d.exactNoteId = fresh.id
                d.status = qsTr("Split landed. Sending the deposit…")
                d.sendDeposit()
            }
        }
    }

    function setSplitResult(success, text) {
        if (!success) {
            d.fail(qsTr("The split transfer failed; nothing was deposited: %1").arg(text))
            return
        }
        d.splitTx = String(text)
        d.waitingForNote = true
        d.waitStarted = Date.now()
        d.status = qsTr("Split sent. Waiting for it to land in a block (usually under a minute)…")
    }

    function setDepositResult(success, text) {
        d.depositPending = false
        if (!success) {
            d.fail(qsTr("The deposit failed: %1").arg(text))
            return
        }
        d.depositTx = String(text)
        d.phase = 3
        d.status = qsTr("Deposit submitted. The LEZ account is credited once this L1 block is final (LIB), which currently takes many hours.")
    }

    spacing: Theme.spacing.large

    QtObject {
        id: d
        // 0 form, 1 preview, 2 sending, 3 done, 4 failed
        property int phase: 0
        property bool notesPending: false
        property bool pricesPending: false
        property bool pricesLive: false
        property bool depositPending: false
        property bool waitingForNote: false
        property real waitStarted: 0
        property int ep: 1
        property int sp: 7

        // Snapshot of the reviewed request.
        property string fromKey: ""
        property string fromLabel: ""
        property string recipient: ""
        property string recipientHex: ""
        property string channelId: ""
        property string amountTokens: ""
        property string amountLepta: ""

        property string exactNoteId: ""
        property int splitFee: 0
        property int depositFee: 0
        property int depositCap: 0

        property string splitTx: ""
        property string depositTx: ""
        property string status: ""
        property string error: ""

        readonly property bool planReady: phase === 1 && !notesPending && !pricesPending
        readonly property bool needsSplit: exactNoteId.length === 0

        function channel() {
            var c = channelField.text.trim()
            return c.length ? c : root.lezChannelId
        }

        function formError() {
            if (!String(fromCombo.currentValue || "").length)
                return qsTr("Choose the account to send from.")
            var e = WalletTools.lezAccountError(recipientField.text)
            if (e.length)
                return qsTr(e)
            if (!/^(0x)?[0-9a-fA-F]{64}$/.test(channel()))
                return qsTr("The LEZ channel id must be 64 hex characters.")
            var lepta = Units.toLepta(Units.normalizeInput(amountField.text))
            if (!lepta.length || lepta === "0")
                return qsTr("Enter an amount.")
            if (Units.compareLepta(lepta, fromBalance()) > 0)
                return qsTr("More than this account holds.")
            return ""
        }

        function fromBalance() {
            var i = fromCombo.currentIndex
            return i >= 0 && i < root.accountRows.length ? (root.accountRows[i].balance || "") : ""
        }

        function startPreview() {
            fromKey = String(fromCombo.currentValue || "")
            fromLabel = fromCombo.currentText
            recipient = recipientField.text.trim()
            recipientHex = WalletTools.lezAccountHex(recipient)
            channelId = channel().replace(/^0x/i, "").toLowerCase()
            amountTokens = Units.normalizeInput(amountField.text)
            amountLepta = Units.toLepta(amountTokens)
            exactNoteId = ""
            splitTx = ""
            depositTx = ""
            status = ""
            error = ""
            confirmSwitch.checked = false
            notesPending = true
            pricesPending = true
            phase = 1
            root.gasPricesRequested()
            root.notesRequested(fromKey)
        }

        function recomputePlan() {
            splitFee = needsSplit ? WalletTools.estimateTransferFee(ep, sp) : 0
            depositFee = WalletTools.estimateDepositFee(1, ep, sp)
            depositCap = WalletTools.depositFeeCap(depositFee)
        }

        function confirm() {
            phase = 2
            if (needsSplit) {
                status = qsTr("Sending the split transfer…")
                root.splitRequested(fromKey, amountTokens)
            } else {
                status = qsTr("Sending the deposit…")
                sendDeposit()
            }
        }

        function sendDeposit() {
            depositPending = true
            root.depositRequested(channelId, [exactNoteId], recipient, fromKey,
                                  [fromKey], WalletTools.leptaSmallToTokens(depositCap))
        }

        function fail(message) {
            waitingForNote = false
            depositPending = false
            error = message
            phase = 4
        }

        function reset() {
            phase = 0
            status = ""
            error = ""
            splitTx = ""
            depositTx = ""
            exactNoteId = ""
            waitingForNote = false
            confirmSwitch.checked = false
        }
    }

    // Polls the account's notes while the split transfer is in flight.
    Timer {
        interval: 10000
        repeat: true
        running: d.waitingForNote && root.nodeRunning
        onTriggered: {
            if (Date.now() - d.waitStarted > 20 * 60 * 1000) {
                d.fail(qsTr("The split transfer %1 has not landed after 20 minutes, so no deposit was sent. When it lands, the exact note can be deposited from Channel Deposit.").arg(d.splitTx))
                return
            }
            root.notesRequested(d.fromKey)
        }
    }

    NodeOffNotice {
        reason: root.nodeOffReason
        reasonSeverity: root.nodeOffSeverity
    }

    LogosScrollView {
        id: lezScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: lezScroll.availableWidth
            spacing: Theme.spacing.medium

            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Bridge tokens to a LEZ public account. You see the plan and fees first; nothing is sent until you confirm. The LEZ side credits the deposit after the L1 block is final.")
                color: Theme.palette.textSecondary
            }

            FieldLabel { text: qsTr("From") }
            LogosComboBox {
                id: fromCombo
                objectName: "lezFromCombo"
                Layout.fillWidth: true
                implicitHeight: 40
                model: root.accountRows
                textRole: "label"
                valueRole: "address"
                enabled: d.phase === 0 || d.phase === 4
                onModelChanged: {
                    if (count > 0 && currentIndex < 0)
                        currentIndex = 0
                }
            }

            FieldLabel { text: qsTr("LEZ recipient account (base58)") }
            LogosTextField {
                id: recipientField
                objectName: "lezRecipientField"
                Layout.fillWidth: true
                placeholderText: qsTr("e.g. 7JSTY… (44 characters)")
                enabled: d.phase === 0 || d.phase === 4
                Accessible.name: qsTr("LEZ recipient account")
            }
            LogosText {
                Layout.fillWidth: true
                visible: recipientField.text.trim().length > 0
                readonly property string err: WalletTools.lezAccountError(recipientField.text)
                text: err.length ? qsTr(err)
                                 : qsTr("Account bytes: %1").arg(WalletTools.lezAccountHex(recipientField.text))
                color: err.length ? Theme.palette.error : Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WrapAnywhere
                Accessible.name: text
            }

            RowLayout {
                Layout.fillWidth: true
                FieldLabel { text: qsTr("Amount (%1)").arg(Units.SYMBOL) }
                LogosText {
                    visible: text.length > 0
                    text: Units.format(d.fromBalance()).length > 0
                          ? qsTr("Available: %1").arg(Units.format(d.fromBalance())) : ""
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }
            LogosTextField {
                id: amountField
                objectName: "lezAmountField"
                Layout.fillWidth: true
                placeholderText: qsTr("0.001")
                enabled: d.phase === 0 || d.phase === 4
                Accessible.name: qsTr("Amount")
                validator: RegularExpressionValidator {
                    regularExpression: Units.inputRegExp(Qt.locale())
                }
            }

            FieldLabel {
                text: root.lezChannelId.length
                      ? qsTr("LEZ channel (from this build: %1). Leave empty to use it.").arg(root.lezChannelId)
                      : qsTr("LEZ channel id (64 hex)")
                wrapMode: Text.WrapAnywhere
            }
            LogosTextField {
                id: channelField
                objectName: "lezChannelField"
                Layout.fillWidth: true
                placeholderText: root.lezChannelId.length ? root.lezChannelId : qsTr("64 hex characters")
                enabled: d.phase === 0 || d.phase === 4
            }

            RowLayout {
                visible: d.phase === 0 || d.phase === 4
                LogosButton {
                    objectName: "lezReviewButton"
                    text: qsTr("Review bridge")
                    Accessible.name: text
                    enabled: root.nodeRunning && d.formError().length === 0
                    onClicked: d.startPreview()
                }
            }
            LogosText {
                Layout.fillWidth: true
                visible: (d.phase === 0 || d.phase === 4)
                         && recipientField.text.trim().length > 0
                         && amountField.text.trim().length > 0
                         && d.formError().length > 0
                text: d.formError()
                color: Theme.palette.error
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
                Accessible.name: text
            }

            // ---- Preview / progress ----
            LogosFrame {
                Layout.fillWidth: true
                visible: d.phase >= 1 && d.phase <= 3
                padding: Theme.spacing.medium
                backgroundColor: Theme.palette.surfaceRecessed
                borderColor: "transparent"
                radius: Theme.spacing.radiusMedium

                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small

                    LogosText {
                        visible: d.phase === 1 && !d.planReady
                        text: qsTr("Reading notes and gas prices…")
                        color: Theme.palette.textSecondary
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: qsTr("To LEZ account: %1").arg(d.recipient)
                        wrapMode: Text.WrapAnywhere
                        Accessible.name: text
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: qsTr("Amount: %1 (%2 base units)").arg(Units.format(d.amountLepta)).arg(d.amountLepta)
                        wrapMode: Text.WordWrap
                        Accessible.name: text
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: qsTr("Channel: %1").arg(d.channelId)
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                        wrapMode: Text.WrapAnywhere
                    }
                    LogosText {
                        objectName: "lezPlanText"
                        Layout.fillWidth: true
                        visible: d.planReady || d.phase >= 2
                        wrapMode: Text.WordWrap
                        text: d.needsSplit
                              ? qsTr("Plan: 2 transactions. (1) split an exact %1-unit note off with a transfer to the same account, fee about %2; (2) deposit that note to LEZ, fee about %3, capped at %4. Total fees about %5 base units%6.")
                                    .arg(d.amountLepta).arg(d.splitFee).arg(d.depositFee).arg(d.depositCap)
                                    .arg(d.splitFee + d.depositFee)
                                    .arg(d.pricesLive ? qsTr(" (gas %1/%2)").arg(d.ep).arg(d.sp) : qsTr(" (default gas 1/7)"))
                              : qsTr("Plan: 1 transaction. A note worth exactly %1 units already exists; deposit it to LEZ, fee about %2, capped at %3 base units%4.")
                                    .arg(d.amountLepta).arg(d.depositFee).arg(d.depositCap)
                                    .arg(d.pricesLive ? qsTr(" (gas %1/%2)").arg(d.ep).arg(d.sp) : qsTr(" (default gas 1/7)"))
                        Accessible.name: text
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: d.phase === 1 && d.planReady
                        spacing: Theme.spacing.small
                        LogosSwitch {
                            id: confirmSwitch
                            objectName: "lezConfirmSwitch"
                            checked: false
                            Accessible.name: qsTr("I checked the LEZ account and amount")
                        }
                        LogosText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("I checked the LEZ account and amount. A deposit cannot be undone from here.")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: d.phase === 1
                        LogosButton {
                            objectName: "lezEditButton"
                            text: qsTr("Edit")
                            Accessible.name: text
                            onClicked: d.reset()
                        }
                        Item { Layout.fillWidth: true }
                        LogosButton {
                            objectName: "lezConfirmButton"
                            text: qsTr("Confirm and bridge")
                            Accessible.name: text
                            enabled: root.nodeRunning && d.planReady && confirmSwitch.checked
                            onClicked: d.confirm()
                        }
                    }

                    LogosText {
                        objectName: "lezStatusText"
                        Layout.fillWidth: true
                        visible: d.status.length > 0
                        text: d.status
                        wrapMode: Text.WordWrap
                        Accessible.name: text
                    }
                    LogosSpinner {
                        visible: d.phase === 2
                        running: d.phase === 2
                    }
                    HashRow {
                        visible: d.splitTx.length > 0
                        label: qsTr("Split transfer")
                        value: d.splitTx
                        onCopyRequested: root.copyToClipboard(d.splitTx)
                    }
                    HashRow {
                        visible: d.depositTx.length > 0
                        label: qsTr("LEZ deposit")
                        value: d.depositTx
                        onCopyRequested: root.copyToClipboard(d.depositTx)
                    }
                    LogosText {
                        objectName: "lezDepositTxText"
                        visible: d.depositTx.length > 0
                        text: qsTr("Deposit tx: %1").arg(d.depositTx)
                        Layout.fillWidth: true
                        wrapMode: Text.WrapAnywhere
                        font.pixelSize: Theme.typography.secondaryText
                        Accessible.name: text
                    }
                    LogosButton {
                        visible: d.phase === 3
                        text: qsTr("New bridge")
                        onClicked: d.reset()
                    }
                }
            }

            LogosText {
                objectName: "lezErrorText"
                Layout.fillWidth: true
                visible: d.phase === 4
                text: d.error
                color: Theme.palette.error
                wrapMode: Text.WrapAnywhere
                Accessible.name: text
            }
            HashRow {
                visible: d.phase === 4 && d.splitTx.length > 0
                label: qsTr("Split transfer")
                value: d.splitTx
                onCopyRequested: root.copyToClipboard(d.splitTx)
            }
        }
    }

    component FieldLabel: LogosText {
        Layout.fillWidth: true
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
    }
}
