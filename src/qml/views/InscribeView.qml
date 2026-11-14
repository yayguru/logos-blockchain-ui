import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs

import Logos.Theme
import Logos.Controls

import "../controls"

// Inscribe: fee preview first, submit only after an explicit confirm.
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
    signal keygenRequested(string keyPath)
    signal identRequested(string keyPath)
    signal copyToClipboard(string text)

    function setPreview(success, text) {
        d.pending = false
        d.previewOk = success
        d.previewText = text
        d.txHash = ""
        if (success)
            d.parsePreview(text)
    }
    function setIdent(success, text) {
        d.pending = false
        if (!success) {
            d.previewOk = false
            d.previewText = text
            return
        }
        try {
            var o = JSON.parse(text)
            if (o.channel_id)
                channelIdField.text = o.channel_id
            if (o.signer)
                d.signer = o.signer
        } catch (e) {
            d.previewOk = false
            d.previewText = text
        }
    }
    function setSubmitResult(success, text) {
        d.pending = false
        d.previewOk = success
        d.previewText = text
        if (success) {
            try {
                var o = JSON.parse(text)
                d.txHash = o.tx_hash || text
            } catch (e) {
                d.txHash = text
            }
        }
    }

    spacing: Theme.spacing.large

    QtObject {
        id: d
        property bool pending: false
        property bool previewOk: false
        property string previewText: ""
        property string estimatedFee: ""
        property string signer: ""
        property string txHash: ""
        property int mode: 0 // 0 text, 1 file

        function parsePreview(text) {
            try {
                var o = JSON.parse(text)
                estimatedFee = o.estimated_fee ? String(o.estimated_fee) : ""
                if (o.channel_id)
                    channelIdField.text = o.channel_id
                if (o.signer)
                    signer = o.signer
            } catch (e) {
                estimatedFee = ""
            }
        }

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

        function buildRequest(dry) {
            var req = {
                dry_run: !!dry,
                channel_key_path: defaultKeyPath(),
                funding_public_key: fundingKey(),
                priority_fee_percent: 12
            }
            var cid = channelIdField.text.trim()
            if (cid.length)
                req.channel_id = cid
            var parent = parentField.text.trim()
            if (parent.length)
                req.parent_msg_id = parent
            if (d.mode === 1) {
                req.payload_path = filePathField.text.trim()
            } else {
                var utf8 = unescape(encodeURIComponent(textArea.text))
                var hex = ""
                for (var i = 0; i < utf8.length; ++i)
                    hex += ("0" + utf8.charCodeAt(i).toString(16)).slice(-2)
                req.payload_hex = hex
            }
            return JSON.stringify(req)
        }

        function validForPreview() {
            if (!defaultKeyPath().length)
                return qsTr("Choose or generate a channel key file first.")
            if (d.mode === 1 && !filePathField.text.trim().length)
                return qsTr("Choose a file to inscribe.")
            if (d.mode === 0 && !textArea.text.trim().length)
                return qsTr("Type some text to inscribe.")
            if (!fundingKey().length)
                return qsTr("Select a funding account for the fee.")
            return ""
        }
    }

    NodeOffNotice {
        reason: root.nodeOffReason
        reasonSeverity: root.nodeOffSeverity
    }

    LogosScrollView {
        id: inscribeScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: inscribeScroll.availableWidth
            spacing: Theme.spacing.large


            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("An inscription is public and permanent. You will see the fee first; nothing is sent until you confirm.")
                color: Theme.palette.textSecondary
            }

            LogosText { text: qsTr("Channel key file"); color: Theme.palette.text }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosTextField {
                    id: keyPathField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Path to inscribe_key.json")
                }
                LogosButton {
                    text: qsTr("Generate")
                    enabled: !d.pending
                    onClicked: {
                        var path = d.defaultKeyPath()
                        if (!path.length)
                            return
                        keyPathField.text = path
                        d.pending = true
                        root.keygenRequested(path)
                    }
                }
                LogosButton {
                    text: qsTr("Load id")
                    enabled: !d.pending && d.defaultKeyPath().length
                    onClicked: {
                        d.pending = true
                        root.identRequested(d.defaultKeyPath())
                    }
                }
            }

            LogosText { text: qsTr("Channel id (optional; default is LXM1 of the channel key)"); color: Theme.palette.text }
            LogosTextField {
                id: channelIdField
                Layout.fillWidth: true
                placeholderText: "64 hex characters"
            }

            LogosText { text: qsTr("Parent message id (optional; default is the channel tip or root)"); color: Theme.palette.text }
            LogosTextField {
                id: parentField
                Layout.fillWidth: true
                placeholderText: "64 hex characters"
            }

            RowLayout {
                LogosButton {
                    text: qsTr("Text")
                    variant: d.mode === 0 ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
                    onClicked: d.mode = 0
                }
                LogosButton {
                    text: qsTr("File")
                    variant: d.mode === 1 ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
                    onClicked: d.mode = 1
                }
            }

            LogosTextArea {
                id: textArea
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                visible: d.mode === 0
                placeholderText: qsTr("Text to write on-chain")
                wrapMode: TextEdit.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: d.mode === 1
                LogosTextField {
                    id: filePathField
                    Layout.fillWidth: true
                    placeholderText: qsTr("File to inscribe")
                    readOnly: true
                }
                LogosButton {
                    text: qsTr("Browse")
                    onClicked: fileDialog.open()
                }
            }

            FileDialog {
                id: fileDialog
                title: qsTr("Select a file to inscribe")
                fileMode: FileDialog.OpenFile
                onAccepted: {
                    var u = selectedFile.toString()
                    if (u.indexOf("file://") === 0)
                        u = u.substring(7)
                    // Windows file:///C:/...
                    if (u.indexOf("/") === 0 && u.length > 2 && u[2] === ":")
                        u = u.substring(1)
                    filePathField.text = u
                }
            }

            LogosText { text: qsTr("Fee paid from"); color: Theme.palette.text }
            LogosComboBox {
                id: fundingCombo
                Layout.fillWidth: true
                implicitHeight: 40
                // Use the published accountRows list (address/label), not a freshly
                // allocated string array. Rebuilding a string model on every
                // accountRows publish (balance refresh) resets currentIndex to -1,
                // so Estimate thought no funding account was selected and never
                // called the module.
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
                        if (err.length) {
                            d.previewOk = false
                            d.previewText = err
                            return
                        }
                        d.pending = true
                        d.estimatedFee = ""
                        d.txHash = ""
                        root.estimateRequested(d.buildRequest(true))
                    }
                }
                LogosButton {
                    text: qsTr("Confirm and send")
                    enabled: !d.pending && root.nodeRunning && d.estimatedFee.length > 0 && confirmBox.checked
                    onClicked: {
                        d.pending = true
                        root.submitRequested(d.buildRequest(false))
                    }
                }
            }

            RowLayout {
                visible: d.estimatedFee.length > 0
                spacing: Theme.spacing.small
                LogosSwitch { id: confirmBox; checked: false }
                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("I understand this is public, permanent, and costs about %1 base units.").arg(d.estimatedFee)
                }
            }

            LogosText {
                visible: d.estimatedFee.length > 0
                text: qsTr("Estimated fee: %1 base units (includes 12% priority). Nothing has been sent.").arg(d.estimatedFee)
                color: Theme.palette.text
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Accessible.name: text
            }

            HashRow {
                visible: d.txHash.length > 0
                label: qsTr("Transaction")
                value: d.txHash
                onCopyRequested: root.copyToClipboard(d.txHash)
            }

            LogosText {
                visible: d.previewText.length > 0 && d.txHash.length === 0
                text: d.previewText
                color: d.previewOk ? Theme.palette.textSecondary : Theme.palette.error
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
                Accessible.name: text
            }

        }
    }
}
