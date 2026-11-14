import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Wallet section: Accounts, Transfer, LEZ Bridge, Channel Deposit, Inscribe, Withdraw, SDP.
RowLayout {
    id: root

    property var accountsModel: null
    property var accountRows: []
    property bool nodeRunning: false
    // Why the node cannot answer, or empty when it can. Passed down rather
    // than re-derived: "start the node" is wrong advice for a node that is
    // already running and merely catching up.
    property string nodeOffReason: ""
    // A LogosNotice.Severity for the banner above.
    property int nodeOffSeverity: LogosNotice.Info
    // The LEZ channel a deposit can be pre-filled with, or empty when this
    // build carries none.
    property string lezChannelId: ""
    property string nodeDataDir: ""

    // ---- Requests out (the host orchestrates these) ----
    signal refreshAccountsRequested()
    signal transferRequested(string fromKeyHex, string toKeyHex, string amount)
    // Gas prices for a fee preview; answered with setGasPrices(target, ...).
    signal gasPricesRequested(string target)
    signal lezNotesRequested(string addressHex)
    signal lezSplitRequested(string fromKeyHex, string amountTokens)
    signal lezDepositRequested(string channelIdHex, var inputNoteIdHexes,
                               string metadataBase58, string changePublicKeyHex,
                               var fundingPublicKeyHexes, string maxTxFeeTokens)
    signal getNotesRequested(string addressHex, string optionalTipHex)
    signal submitRequested(string channelIdHex, var inputNoteIdHexes,
                           string metadataBase58, string changePublicKeyHex,
                           var fundingPublicKeyHexes, string maxTxFee,
                           string optionalTipHex)
    signal inscribeEstimateRequested(string requestJson)
    signal inscribeSubmitRequested(string requestJson)
    signal withdrawEstimateRequested(string requestJson)
    signal withdrawSubmitRequested(string requestJson)
    signal channelKeygenRequested(string keyPath)
    signal channelIdentRequested(string keyPath)
    signal sdpStatusRequested(string kind, string serviceType)
    signal sdpPreviewRequested(string kind, string requestJson)
    signal sdpSubmitRequested(string kind, string requestJson)
    signal copyToClipboard(string text)

    // ---- Results back in ----
    function setTransferHash(hash) { transferView.setTransferHash(hash) }
    function setTransferError(message) { transferView.setTransferError(message) }
    function setGasPrices(target, success, value) {
        if (target === "lez") lezBridgeView.setGasPrices(success, value)
        else transferView.setGasPrices(success, value)
    }
    function setLezNotes(success, value) { lezBridgeView.setNotes(success, value) }
    function setLezSplitResult(success, value) { lezBridgeView.setSplitResult(success, value) }
    function setLezDepositResult(success, value) { lezBridgeView.setDepositResult(success, value) }
    function setNotes(value) { channelDepositView.setNotes(value) }
    function setNotesError(message) { channelDepositView.setNotesError(message) }
    function setSubmitResult(success, value) {
        channelDepositView.setSubmitResult(success, value)
    }
    function setInscribePreview(success, value) { inscribeView.setPreview(success, value) }
    function setChannelIdent(success, value) {
        inscribeView.setIdent(success, value)
        withdrawView.setIdent(success, value)
    }
    function setInscribeResult(success, value) { inscribeView.setSubmitResult(success, value) }
    function setWithdrawPreview(success, value) { withdrawView.setPreview(success, value) }
    function setWithdrawResult(success, value) { withdrawView.setSubmitResult(success, value) }
    function setSdpStatus(success, value) { sdpView.setStatus(success, value) }
    function setSdpPreview(success, value) { sdpView.setPreview(success, value) }
    function setSdpResult(success, value) { sdpView.setSubmitResult(success, value) }

    spacing: Theme.spacing.large

    SectionNav {
        objectName: "walletNav"
        // Index-for-index with walletStack's children below.
        sections: [
            // No needsNode: every section states why it cannot answer
            // rather than being unreachable, same as the tabs above.
            { label: qsTr("Accounts"), icon: "" },
            { label: qsTr("Transfer"), icon: "" },
            { label: qsTr("LEZ Bridge"), icon: "" },
            { label: qsTr("Channel Deposit"), icon: "" },
            { label: qsTr("Inscribe"), icon: "" },
            { label: qsTr("Channel Withdraw"), icon: "" },
            { label: qsTr("SDP"), icon: "" }
        ]
        nodeRunning: root.nodeRunning
        currentIndex: walletStack.currentIndex
        onSectionActivated: (index) => walletStack.currentIndex = index
    }

    LogosFrame {
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: StackLayout {
            id: walletStack

            AccountsView {
                id: accountsView
                nodeOffSeverity: root.nodeOffSeverity
                nodeOffReason: root.nodeOffReason
                accountsModel: root.accountsModel
                onRefreshAccountsRequested: root.refreshAccountsRequested()
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            TransferView {
                id: transferView
                nodeOffSeverity: root.nodeOffSeverity
                nodeRunning: root.nodeRunning
                nodeOffReason: root.nodeOffReason
                accountRows: root.accountRows
                onTransferRequested: (fromKeyHex, toKeyHex, amount) =>
                    root.transferRequested(fromKeyHex, toKeyHex, amount)
                onGasPricesRequested: root.gasPricesRequested("transfer")
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            LezBridgeView {
                id: lezBridgeView
                nodeOffSeverity: root.nodeOffSeverity
                nodeOffReason: root.nodeOffReason
                accountRows: root.accountRows
                nodeRunning: root.nodeRunning
                lezChannelId: root.lezChannelId
                onNotesRequested: (addressHex) => root.lezNotesRequested(addressHex)
                onGasPricesRequested: root.gasPricesRequested("lez")
                onSplitRequested: (fromKeyHex, amountTokens) =>
                    root.lezSplitRequested(fromKeyHex, amountTokens)
                onDepositRequested: (channelIdHex, inputNoteIdHexes, metadataBase58,
                                     changePublicKeyHex, fundingPublicKeyHexes, maxTxFeeTokens) =>
                    root.lezDepositRequested(channelIdHex, inputNoteIdHexes, metadataBase58,
                                             changePublicKeyHex, fundingPublicKeyHexes, maxTxFeeTokens)
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            ChannelDepositView {
                id: channelDepositView
                nodeOffSeverity: root.nodeOffSeverity
                nodeOffReason: root.nodeOffReason
                accountRows: root.accountRows
                nodeRunning: root.nodeRunning
                lezChannelId: root.lezChannelId
                onGetNotesRequested: (addressHex, optionalTipHex) =>
                    root.getNotesRequested(addressHex, optionalTipHex)
                onSubmitRequested: (channelIdHex, inputNoteIdHexes, metadataBase58,
                                    changePublicKeyHex, fundingPublicKeyHexes,
                                    maxTxFee, optionalTipHex) =>
                    root.submitRequested(channelIdHex, inputNoteIdHexes, metadataBase58,
                                         changePublicKeyHex, fundingPublicKeyHexes,
                                         maxTxFee, optionalTipHex)
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            InscribeView {
                id: inscribeView
                nodeOffSeverity: root.nodeOffSeverity
                nodeOffReason: root.nodeOffReason
                accountRows: root.accountRows
                nodeRunning: root.nodeRunning
                nodeDataDir: root.nodeDataDir
                onEstimateRequested: (requestJson) => root.inscribeEstimateRequested(requestJson)
                onSubmitRequested: (requestJson) => root.inscribeSubmitRequested(requestJson)
                onKeygenRequested: (keyPath) => root.channelKeygenRequested(keyPath)
                onIdentRequested: (keyPath) => root.channelIdentRequested(keyPath)
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            ChannelWithdrawView {
                id: withdrawView
                nodeOffSeverity: root.nodeOffSeverity
                nodeOffReason: root.nodeOffReason
                accountRows: root.accountRows
                nodeRunning: root.nodeRunning
                nodeDataDir: root.nodeDataDir
                onEstimateRequested: (requestJson) => root.withdrawEstimateRequested(requestJson)
                onSubmitRequested: (requestJson) => root.withdrawSubmitRequested(requestJson)
                onIdentRequested: (keyPath) => root.channelIdentRequested(keyPath)
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            SdpView {
                id: sdpView
                nodeOffSeverity: root.nodeOffSeverity
                nodeOffReason: root.nodeOffReason
                nodeRunning: root.nodeRunning
                onStatusRequested: (kind, serviceType) => root.sdpStatusRequested(kind, serviceType)
                onPreviewRequested: (kind, requestJson) => root.sdpPreviewRequested(kind, requestJson)
                onSubmitRequested: (kind, requestJson) => root.sdpSubmitRequested(kind, requestJson)
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }
        }
    }
}
