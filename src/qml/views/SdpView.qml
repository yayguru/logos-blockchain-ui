import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

ColumnLayout {
    id: root

    property bool nodeRunning: false
    property string nodeOffReason: ""
    property int nodeOffSeverity: LogosNotice.Info

    signal statusRequested(string kind, string serviceType)
    signal previewRequested(string kind, string requestJson)
    signal submitRequested(string kind, string requestJson)
    signal copyToClipboard(string text)

    function setStatus(success, text) {
        d.pending = false
        d.statusOk = success
        d.statusText = text
    }
    function setPreview(success, text) {
        d.pending = false
        d.previewOk = success
        d.previewText = text
        d.txHash = ""
    }
    function setSubmitResult(success, text) {
        d.pending = false
        d.previewOk = success
        d.previewText = text
        if (success) {
            try {
                var o = JSON.parse(text)
                d.txHash = o.tx_hash || (o.result && (o.result.tx_hash || o.result.hash)) || ""
                if (!d.txHash.length)
                    d.txHash = text
            } catch (e) { d.txHash = text }
        }
    }

    spacing: Theme.spacing.large

    QtObject {
        id: d
        property int tab: 0
        property bool pending: false
        property bool statusOk: false
        property string statusText: ""
        property bool previewOk: false
        property string previewText: ""
        property string txHash: ""

        function wrapDry(body, dry) {
            var parsed
            try { parsed = JSON.parse(body) } catch (e) { parsed = body }
            return JSON.stringify({ dry_run: !!dry, body: parsed })
        }
        function withdrawalBody(dry) {
            return JSON.stringify({ dry_run: !!dry, declaration_id: declarationIdField.text.trim() })
        }
    }

    NodeOffNotice { reason: root.nodeOffReason; reasonSeverity: root.nodeOffSeverity }

    LogosText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.palette.textSecondary
        text: qsTr("Service Declaration Protocol. Status reads are free. Posts are validated first; nothing is sent until you confirm.")
    }

    RowLayout {
        LogosButton { text: qsTr("Status"); checked: d.tab === 0; checkable: true; onClicked: d.tab = 0 }
        LogosButton { text: qsTr("Declaration"); checked: d.tab === 1; checkable: true; onClicked: d.tab = 1 }
        LogosButton { text: qsTr("Activity"); checked: d.tab === 2; checkable: true; onClicked: d.tab = 2 }
        LogosButton { text: qsTr("Withdrawal"); checked: d.tab === 3; checkable: true; onClicked: d.tab = 3 }
    }

    // Status
    ColumnLayout {
        visible: d.tab === 0
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        RowLayout {
            LogosButton {
                text: qsTr("Current declarations")
                enabled: !d.pending && root.nodeRunning
                onClicked: { d.pending = true; root.statusRequested("declarations", "") }
            }
            LogosButton {
                text: qsTr("Snapshot")
                enabled: !d.pending && root.nodeRunning
                onClicked: { d.pending = true; root.statusRequested("snapshot", "") }
            }
        }
        RowLayout {
            LogosTextField {
                id: serviceTypeField
                Layout.fillWidth: true
                placeholderText: qsTr("Optional service type for finalized declarations")
            }
            LogosButton {
                text: qsTr("Finalized")
                enabled: !d.pending && root.nodeRunning
                onClicked: { d.pending = true; root.statusRequested("finalized", serviceTypeField.text.trim()) }
            }
        }
        JsonBlock { json: d.statusText; Layout.fillWidth: true; Layout.preferredHeight: 240 }
    }

    // Declaration / activity JSON
    ColumnLayout {
        visible: d.tab === 1 || d.tab === 2
        Layout.fillWidth: true
        LogosText {
            text: d.tab === 1 ? qsTr("Declaration JSON (same schema as POST /sdp/declaration)")
                              : qsTr("Activity metadata JSON (same schema as POST /sdp/activity)")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        LogosTextArea {
            id: bodyArea
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            wrapMode: TextEdit.Wrap
        }
        RowLayout {
            LogosButton {
                text: qsTr("Validate (dry-run)")
                enabled: !d.pending && root.nodeRunning && bodyArea.text.trim().length
                onClicked: {
                    d.pending = true
                    root.previewRequested(d.tab === 1 ? "declaration" : "activity",
                                          d.wrapDry(bodyArea.text, true))
                }
            }
            LogosButton {
                text: qsTr("Confirm and send")
                enabled: !d.pending && root.nodeRunning && confirmBox.checked && bodyArea.text.trim().length
                onClicked: {
                    d.pending = true
                    root.submitRequested(d.tab === 1 ? "declaration" : "activity",
                                         d.wrapDry(bodyArea.text, false))
                }
            }
        }
    }

    ColumnLayout {
        visible: d.tab === 3
        Layout.fillWidth: true
        LogosText { text: qsTr("Declaration id to withdraw"); color: Theme.palette.textPrimary }
        LogosTextField { id: declarationIdField; Layout.fillWidth: true; placeholderText: "64 hex characters" }
        RowLayout {
            LogosButton {
                text: qsTr("Validate (dry-run)")
                enabled: !d.pending && root.nodeRunning && declarationIdField.text.trim().length
                onClicked: { d.pending = true; root.previewRequested("withdrawal", d.withdrawalBody(true)) }
            }
            LogosButton {
                text: qsTr("Confirm and send")
                enabled: !d.pending && root.nodeRunning && confirmBox.checked && declarationIdField.text.trim().length
                onClicked: { d.pending = true; root.submitRequested("withdrawal", d.withdrawalBody(false)) }
            }
        }
    }

    RowLayout {
        visible: d.tab !== 0
        LogosSwitch { id: confirmBox; checked: false }
        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("I understand this submits an SDP transaction to the network.")
        }
    }

    HashRow {
        visible: d.txHash.length > 0
        label: qsTr("Transaction")
        value: d.txHash
        onCopyRequested: function(text) { root.copyToClipboard(text) }
    }

    LogosText {
        visible: d.previewText.length > 0 && d.tab !== 0
        text: d.previewText
        color: d.previewOk ? Theme.palette.textSecondary : Theme.palette.danger
        wrapMode: Text.WrapAnywhere
        Layout.fillWidth: true
    }
}
