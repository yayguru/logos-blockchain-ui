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
// On L1 this is a ChannelDeposit into the LEZ channel (0101…01 on the testnet).
// LEZ 0.4 metadata names the recipient by public key: borsh DepositMetadata
// = 0x01 0x00 || pk (34 bytes), built and checked by the backend
// (lezDepositRecipient). The 0.3 form (bare account id) is skipped by a 0.4
// sequencer and would leave the notes locked in the channel. A deposit consumes whole notes,
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
    property var chain: null
    signal splitRequested(string fromKeyHex, string amountTokens)
    signal depositRequested(string channelIdHex, var inputNoteIdHexes,
                            string metadataBase58, string changePublicKeyHex,
                            var fundingPublicKeyHexes, string maxTxFeeTokens)
    signal copyToClipboard(string text)

    // Built-in LEZ account: the default recipient (windows.13).
    property bool lezSupported: false
    property var lezAccount: ({ exists: false })
    property string lezBalance: ""
    property string lezError: ""
    property bool lezBusy: false
    signal lezCreateRequested()
    signal lezRefreshRequested()
    readonly property string ownLezAccount: (lezAccount && lezAccount.exists === true) ? String(lezAccount.account_id) : ""
    // Fill the recipient with our own account unless the user typed another.
    onOwnLezAccountChanged: {
        if (ownLezAccount.length && recipientField.text.trim().length === 0)
            recipientField.text = ownLezAccount
    }

    Component.onCompleted: d.loadNet()
    onChainChanged: d.loadNet()

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
        d.status = d.toLez
                   ? qsTr("Deposit submitted. LEZ 0.4 credits it in a LEZ block pinned on this deposit, usually minutes after it lands in an L1 block; at the latest once the L1 block is final. Follow it in the tracker below.")
                   : qsTr("Deposit submitted to channel %1. This is not the LEZ bridge channel, so no LEZ account will be credited; the note now sits in that channel.").arg(d.channelId)
        if (d.toLez && !d.v04)
            d.status = qsTr("Deposit submitted. This LEZ (0.3, the current public testnet) credits it only once the L1 block is final (LIB), which can take many hours. Follow it in the tracker below.")
        tracker.addSent(d.depositTx, d.amountLepta, d.toLez ? d.recipient : "", d.channelId)
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
        property string recipient: ""      // LEZ account id (base58), for the tracker
        property string recipientHex: ""   // LEZ public key (hex)
        property string metadataBase58: "" // 0x01 0x00 || pk
        // Live check of the recipient field (async, through the backend).
        property string checkedText: ""
        property var checked: null         // { public_key, account_id, metadata_base58, lez_version } or null
        property string checkError: ""
        // LEZ network behind the RPC (windows.15): { rpc_url, default_rpc_url, lez_version, rpc_channel_id }.
        property var net: null
        property string netError: ""
        readonly property bool v04: !!net && net.lez_version === "0.4"
        function loadNet() {
            if (!root.chain || typeof root.chain.lezNetwork !== "function") return
            root.chain.lezNetwork(function(ok, v) {
                if (ok) { net = v; netError = ""; rpcField.text = (v.rpc_url !== v.default_rpc_url) ? v.rpc_url : "" }
                else { net = null; netError = String(v) }
                checkedText = "\u0000"; checkRecipient()
            })
        }
        function setRpc(url) {
            if (!root.chain || typeof root.chain.lezSetRpcUrl !== "function") return
            net = null
            root.chain.lezSetRpcUrl(url, function(ok, v) {
                if (ok) { net = v; netError = "" } else netError = String(v)
                checkedText = "\u0000"; checkRecipient()
            })
        }
        function checkRecipient() {
            var t = recipientField.text.trim()
            if (t === checkedText) return
            checkedText = t
            checked = null
            checkError = ""
            if (!t.length) return
            if (!root.chain || !root.chain.lezRecipientAvailable) {
                checkError = qsTr("This backend cannot build LEZ 0.4 deposits.")
                return
            }
            root.chain.lezRecipient(t, function(ok, v) {
                if (t !== recipientField.text.trim()) return
                if (ok) { checked = v; checkError = "" }
                else { checked = null; checkError = String(v) }
            })
        }
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

        // The chosen channel is the LEZ bridge channel (or no LEZ channel is
        // configured, so we cannot tell). Any other channel is just a deposit
        // into that channel; nothing credits a LEZ account then.
        readonly property bool toLez: !root.lezChannelId.length
                                      || channelId === root.lezChannelId.replace(/^0x/i, "").toLowerCase()
        readonly property string dest: toLez ? qsTr("LEZ") : qsTr("channel %1…").arg(channelId.slice(0, 8))
        readonly property bool planReady: phase === 1 && !notesPending && !pricesPending
        readonly property bool needsSplit: exactNoteId.length === 0

        function channel() {
            var c = channelField.text.trim()
            return c.length ? c : root.lezChannelId
        }

        function formError() {
            if (!String(fromCombo.currentValue || "").length)
                return qsTr("Choose the account to send from.")
            if (recipientField.text.trim().length === 0)
                return qsTr("Enter the LEZ recipient.")
            if (checkError.length)
                return checkError
            if (!checked || checkedText !== recipientField.text.trim())
                return qsTr("Checking the recipient…")
            if (!/^(0x)?[0-9a-fA-F]{64}$/.test(channel()))
                return qsTr("The LEZ channel id must be 64 hex characters.")
            var pa = Units.parseAmount(amountField.text)
            if (pa.error.length)
                return qsTr(pa.error)
            var lepta = pa.lepta
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
            recipient = String(checked.account_id)
            recipientHex = String(checked.public_key)
            metadataBase58 = String(checked.metadata_base58)
            channelId = channel().replace(/^0x/i, "").toLowerCase()
            var pa = Units.parseAmount(amountField.text)
            amountTokens = pa.canonical
            amountLepta = pa.lepta
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
            root.depositRequested(channelId, [exactNoteId], metadataBase58, fromKey,
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
                text: qsTr("Bridge tokens to a LEZ public account. You see the plan and fees first; nothing is sent until you confirm. The deposit format follows the LEZ version the RPC below runs (0.3 or 0.4).")
                color: Theme.palette.textSecondary
            }

            LezAccountCard {
                supported: root.lezSupported
                account: root.lezAccount
                balance: root.lezBalance
                error: root.lezError
                busy: root.lezBusy
                showUseButton: root.ownLezAccount.length > 0 && recipientField.text.trim() !== root.ownLezAccount
                onCreateRequested: root.lezCreateRequested()
                onRefreshRequested: root.lezRefreshRequested()
                onUseRequested: function(accountId) { recipientField.text = accountId }
                onCopyToClipboard: (text) => root.copyToClipboard(text)
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

            LogosText {
                objectName: "lezNetworkLine"
                Accessible.name: text
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                font.pixelSize: Theme.typography.secondaryText
                color: d.netError.length ? Theme.palette.error : Theme.palette.textSecondary
                text: d.netError.length
                      ? qsTr("LEZ RPC: %1").arg(d.netError)
                      : (d.net ? qsTr("LEZ %1 at %2 (channel %3…). %4")
                                   .arg(d.net.lez_version).arg(d.net.rpc_url).arg(String(d.net.rpc_channel_id).slice(0, 8))
                                   .arg(d.v04 ? qsTr("Deposits name the recipient by public key and are credited minutes after the L1 block.")
                                              : qsTr("Deposits name the recipient by account id and are credited after L1 finality (hours)."))
                               : qsTr("Checking which LEZ version the RPC runs…"))
            }
            RowLayout {
                Layout.fillWidth: true
                LogosTextField {
                    id: rpcField
                    objectName: "lezRpcField"
                    Layout.fillWidth: true
                    placeholderText: qsTr("LEZ RPC (empty = built-in public testnet; http://127.0.0.1:<port> for a local sequencer)")
                    enabled: d.phase === 0 || d.phase === 4
                }
                LogosButton {
                    objectName: "lezRpcApply"
                    text: qsTr("Use")
                    enabled: d.phase === 0 || d.phase === 4
                    onClicked: d.setRpc(rpcField.text.trim())
                }
            }

            FieldLabel { text: d.v04 ? qsTr("LEZ recipient public key (64 hex), or your own LEZ account")
                                     : qsTr("LEZ recipient account (base58) or public key (64 hex)") }
            LogosTextField {
                id: recipientField
                objectName: "lezRecipientField"
                Layout.fillWidth: true
                placeholderText: d.v04 ? qsTr("pk from: wallet account get --keys -a Public/<account id>")
                                       : qsTr("e.g. 7JSTY… (44 characters)")
                enabled: d.phase === 0 || d.phase === 4
                Accessible.name: qsTr("LEZ recipient public key")
                onTextChanged: recipientCheck.restart()
            }
            Timer { id: recipientCheck; interval: 300; onTriggered: d.checkRecipient() }
            LogosText {
                objectName: "lezRecipientCheck"
                Layout.fillWidth: true
                visible: recipientField.text.trim().length > 0
                readonly property string err: d.checkError
                text: err.length ? err
                                 : (d.checked ? (String(d.checked.public_key).length
                                                 ? qsTr("LEZ account %1 (public key %2…), LEZ %3 metadata").arg(String(d.checked.account_id)).arg(String(d.checked.public_key).slice(0, 16)).arg(String(d.checked.lez_version))
                                                 : qsTr("LEZ account %1, LEZ %2 metadata").arg(String(d.checked.account_id)).arg(String(d.checked.lez_version)))
                                              : qsTr("Checking…"))
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
                placeholderText: qsTr("0.001 or 0,001")
                enabled: d.phase === 0 || d.phase === 4
                Accessible.name: qsTr("Amount")
            }
            LogosText {
                objectName: "lezAmountHint"
                readonly property var pa: Units.parseAmount(amountField.text)
                Layout.fillWidth: true
                visible: amountField.text.trim().length > 0
                text: pa.error.length ? qsTr(pa.error) : "= " + Units.format(pa.lepta)
                Accessible.name: text
                font.pixelSize: Theme.typography.secondaryText
                color: pa.error.length ? Theme.palette.error : Theme.palette.textSecondary
                wrapMode: Text.WordWrap
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
                        text: d.toLez ? (d.recipientHex.length ? qsTr("To LEZ account: %1 (public key %2)").arg(d.recipient).arg(d.recipientHex)
                                                               : qsTr("To LEZ account: %1").arg(d.recipient))
                                     : qsTr("To channel %1 (not the LEZ bridge; metadata %2)").arg(d.channelId).arg(d.metadataBase58)
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
                              ? qsTr("Plan: 2 transactions. (1) split off an exact %1 note (fee ≈ %2); (2) deposit it to %7 (fee ≈ %3, cap %4). Total fees ≈ %5%6.")
                                    .arg(Units.format(d.amountLepta)).arg(Units.format(String(d.splitFee))).arg(Units.format(String(d.depositFee))).arg(Units.format(String(d.depositCap)))
                                    .arg(Units.format(String(d.splitFee + d.depositFee)))
                                    .arg(d.pricesLive ? qsTr(" (gas %1/%2)").arg(d.ep).arg(d.sp) : qsTr(" (default gas 1/7)"))
                                    .arg(d.dest)
                              : qsTr("Plan: 1 transaction. A note of exactly %1 exists; deposit it to %5 (fee ≈ %2, cap %3)%4.")
                                    .arg(Units.format(d.amountLepta)).arg(Units.format(String(d.depositFee))).arg(Units.format(String(d.depositCap)))
                                    .arg(d.pricesLive ? qsTr(" (gas %1/%2)").arg(d.ep).arg(d.sp) : qsTr(" (default gas 1/7)"))
                                    .arg(d.dest)
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
                            text: d.toLez ? qsTr("I checked the LEZ account and amount. A deposit cannot be undone from here.")
                                          : qsTr("I checked the channel and amount. Only that channel's key holder can withdraw it.")
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
                        label: d.toLez ? qsTr("LEZ deposit") : qsTr("Deposit")
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

            LezDepositTracker {
                id: tracker
                lezChannelId: root.lezChannelId
                nodeRunning: root.nodeRunning
                chain: root.chain
            }
        }
    }

    component FieldLabel: LogosText {
        Layout.fillWidth: true
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
    }
}
