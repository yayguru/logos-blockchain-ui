import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

ColumnLayout {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: true

    property var accountRows: []
    onAccountRowsChanged: {
        if (accountRows && accountRows.length > 0 && fundingCombo.currentIndex < 0)
            fundingCombo.currentIndex = 0
    }
    property bool nodeRunning: false
    property string nodeOffReason: ""
    property int nodeOffSeverity: LogosNotice.Info
    property string nodeDataDir: ""

    signal estimateRequested(string requestJson)
    signal submitRequested(string requestJson)
    signal identRequested(string keyPath)
    signal copyToClipboard(string text)

    function setPreview(success, text) {
        d.pending = false
        d.previewOk = success
        d.previewText = text
        d.txHash = ""
        if (success) {
            try {
                var o = JSON.parse(text)
                d.estimatedFee = o.estimated_fee ? String(o.estimated_fee) : ""
                if (o.channel_id)
                    channelIdField.text = o.channel_id
            } catch (e) { d.estimatedFee = "" }
        }
    }
    function setIdent(success, text) {
        d.pending = false
        if (!success) { d.previewOk = false; d.previewText = text; return }
        try {
            var o = JSON.parse(text)
            if (o.channel_id)
                channelIdField.text = o.channel_id
        } catch (e) { d.previewText = text }
    }
    function setSubmitResult(success, text) {
        d.pending = false
        d.previewOk = success
        d.previewText = text
        if (success) {
            try { var o = JSON.parse(text); d.txHash = o.tx_hash || text } catch (e) { d.txHash = text }
        }
    }

    spacing: Theme.spacing.large

    QtObject {
        id: d
        property bool pending: false
        property bool previewOk: false
        property string previewText: ""
        property string estimatedFee: ""
        property string txHash: ""

        function fundingKey() {
            var v = fundingCombo.currentValue
            if (v && String(v).length)
                return String(v)
            var i = fundingCombo.currentIndex
            if (i >= 0 && i < root.accountRows.length)
                return String(root.accountRows[i].address || "")
            return ""
        }
        function defaultKeyPath() {
            if (keyPathField.text.trim().length)
                return keyPathField.text.trim()
            if (root.nodeDataDir && root.nodeDataDir.length)
                return root.nodeDataDir + "/inscribe_key.json"
            return ""
        }
        function noteIds() {
            var raw = notesArea.text.split(/\s+/)
            var out = []
            for (var i = 0; i < raw.length; ++i) {
                var s = raw[i].trim()
                if (s.length)
                    out.push(s)
            }
            return out
        }
        function buildRequest(dry) {
            return JSON.stringify({
                dry_run: !!dry,
                channel_key_path: defaultKeyPath(),
                channel_id: channelIdField.text.trim(),
                input_note_ids: noteIds(),
                funding_public_key: fundingKey(),
                priority_fee_percent: 12
            })
        }
        function validForPreview() {
            if (!defaultKeyPath().length)
                return qsTr("Choose the channel key file that is accredited on this channel.")
            if (!noteIds().length)
                return qsTr("Enter at least one 64-character note id to release from the channel.")
            if (!fundingKey().length)
                return qsTr("Select a funding account for the fee.")
            return ""
        }
    }

    NodeOffNotice { reason: root.nodeOffReason; reasonSeverity: root.nodeOffSeverity }

    LogosScrollView {
        id: withdrawScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: withdrawScroll.availableWidth
            spacing: Theme.spacing.large


            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                text: qsTr("A channel withdraw releases deposited notes back to regular spendable notes. You will see the fee first; nothing is sent until you confirm.")
            }

            LogosText { text: qsTr("Channel key file"); color: Theme.palette.text }
            RowLayout {
                Layout.fillWidth: true
                LogosTextField { id: keyPathField; Layout.fillWidth: true; placeholderText: qsTr("Path to the channel key") }
                LogosButton {
                    text: qsTr("Load id")
                    enabled: !d.pending && d.defaultKeyPath().length
                    onClicked: { d.pending = true; root.identRequested(d.defaultKeyPath()) }
                }
            }

            LogosText { text: qsTr("Channel id"); color: Theme.palette.text }
            LogosTextField { id: channelIdField; Layout.fillWidth: true; placeholderText: "64 hex characters" }

            LogosText { text: qsTr("Note ids to withdraw (one 64-character hex id per line)"); color: Theme.palette.text }
            LogosTextArea {
                id: notesArea
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                wrapMode: TextEdit.Wrap
            }

            LogosText { text: qsTr("Fee paid from"); color: Theme.palette.text }
                        LogosComboBox {
                id: fundingCombo
                Layout.fillWidth: true
                implicitHeight: 40
                model: root.accountRows
                textRole: "label"
                valueRole: "address"
                onModelChanged: {
                    if (count > 0 && currentIndex < 0)
                        currentIndex = 0
                }
            }

            RowLayout {
                LogosButton {
                    text: qsTr("Estimate fee")
                    enabled: !d.pending && root.nodeRunning
                    onClicked: {
                        var err = d.validForPreview()
                        if (err.length) { d.previewOk = false; d.previewText = err; return }
                        d.pending = true; d.estimatedFee = ""; d.txHash = ""
                        root.estimateRequested(d.buildRequest(true))
                    }
                }
                LogosButton {
                    text: qsTr("Confirm and send")
                    enabled: !d.pending && root.nodeRunning && d.estimatedFee.length > 0 && confirmBox.checked
                    onClicked: { d.pending = true; root.submitRequested(d.buildRequest(false)) }
                }
            }

            RowLayout {
                visible: d.estimatedFee.length > 0
                LogosSwitch { id: confirmBox; checked: false }
                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("I confirm withdrawing these notes and paying about %1 base units.").arg(d.estimatedFee)
                }
            }

            LogosText {
                visible: d.estimatedFee.length > 0
                text: qsTr("Estimated fee: %1 base units (includes 12% priority). Nothing has been sent.").arg(d.estimatedFee)
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            HashRow {
                visible: d.txHash.length > 0
                label: qsTr("Transaction")
                value: d.txHash
                onCopyRequested: function(text) { root.copyToClipboard(text) }
            }

            LogosText {
                visible: d.previewText.length > 0 && d.txHash.length === 0
                text: d.previewText
                color: d.previewOk ? Theme.palette.textSecondary : Theme.palette.error
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
            }
        }
    }
}
