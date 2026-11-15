import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "NodeHttp.js" as NodeHttp

// Read-only viewer of a channel's inscriptions, straight from the local
// node's HTTP API. "Latest" jumps to the channel tip slot; "Scan" walks back
// through recent blocks. Nothing is signed or sent.
LogosFrame {
    id: root
    objectName: "inscriptionHistory"

    property string channelId: ""
    property string apiBase: "http://127.0.0.1:8080"
    property bool nodeRunning: false
    property int scanBlocks: 400

    signal copyToClipboard(string text)

    function latest() { d.loadLatest() }
    function scan() { d.scan(d.oldestSlot > 0) }
    readonly property int count: items.count
    readonly property string statusText: d.status
    function itemText(i) { var r = items.get(i); return r ? (r.slot + " " + r.tx.slice(0, 8) + " " + r.text) : "" }

    Layout.fillWidth: true
    padding: Theme.spacing.medium
    backgroundColor: Theme.palette.surfaceRecessed
    borderColor: "transparent"
    radius: Theme.spacing.radiusMedium

    ListModel { id: items }

    QtObject {
        id: d
        property bool busy: false
        property string status: ""
        property int oldestSlot: -1
        property int tipSlot: -1
        property string seen: "|"

        function cid() {
            return String(root.channelId || "").trim().replace(/^0x/i, "").toLowerCase()
        }
        function valid() { return /^[0-9a-f]{64}$/.test(cid()) }

        function reset() {
            items.clear()
            seen = "|"
            oldestSlot = -1
            status = ""
        }

        function addFrom(blocks) {
            var c = cid()
            var found = 0
            for (var i = 0; i < blocks.length; ++i) {
                var b = blocks[i]
                var slot = Number(b.header && b.header.slot)
                if (oldestSlot < 0 || slot < oldestSlot) oldestSlot = slot
                var txs = b.transactions || []
                for (var t = 0; t < txs.length; ++t) {
                    var mt = txs[t].mantle_tx || {}
                    var ops = mt.ops || []
                    for (var o = 0; o < ops.length; ++o) {
                        var op = ops[o]
                        if (!op || op.opcode !== 17 || !op.payload) continue
                        if (String(op.payload.channel_id).toLowerCase() !== c) continue
                        var key = mt.hash + ":" + o
                        if (seen.indexOf("|" + key + "|") >= 0) continue
                        seen += key + "|"
                        var dec = NodeHttp.hexToText(op.payload.inscription)
                        var row = {
                            slot: slot,
                            tx: String(mt.hash || ""),
                            text: dec.printable ? dec.text : "",
                            size: dec.size,
                            hex: String(op.payload.inscription || "").slice(0, 96)
                        }
                        // Newest first.
                        var at = items.count
                        for (var k = 0; k < items.count; ++k) {
                            if (items.get(k).slot < slot) { at = k; break }
                        }
                        items.insert(at, row)
                        found++
                    }
                }
            }
            return found
        }

        function loadLatest() {
            if (!valid()) { status = qsTr("Enter or load a 64-character channel id first."); return }
            busy = true
            status = qsTr("Reading the channel tip…")
            NodeHttp.getJson(root.apiBase + "/channel/" + cid(), 20000, function(ok, o) {
                if (!ok) { busy = false; status = qsTr("This channel is not known to the node yet (%1).").arg(o); return }
                tipSlot = Number(o.tip_slot || -1)
                if (tipSlot < 0) { busy = false; status = qsTr("The channel has no inscription yet."); return }
                NodeHttp.getBlocks(root.apiBase, "slot_from=" + tipSlot + "&slot_to=" + tipSlot + "&blocks_limit=5",
                    function(ok2, blocks) {
                        busy = false
                        if (!ok2) { status = qsTr("Could not read slot %1: %2").arg(tipSlot).arg(blocks); return }
                        var n = addFrom(blocks)
                        status = n ? qsTr("Latest inscription is at slot %1.").arg(tipSlot)
                                   : qsTr("The tip is at slot %1, but that block is not on this node's chain view.").arg(tipSlot)
                    })
            })
        }

        function scan(older) {
            if (!valid()) { status = qsTr("Enter or load a 64-character channel id first."); return }
            busy = true
            var q = "descending=true&blocks_limit=" + root.scanBlocks
            if (older && oldestSlot > 0) q += "&slot_to=" + (oldestSlot - 1)
            status = older ? qsTr("Scanning %1 older blocks…").arg(root.scanBlocks)
                           : qsTr("Scanning the last %1 blocks…").arg(root.scanBlocks)
            NodeHttp.getBlocks(root.apiBase, q, function(ok, blocks) {
                busy = false
                if (!ok) { status = qsTr("Scan failed: %1").arg(blocks); return }
                var n = addFrom(blocks)
                status = qsTr("Scanned %1 blocks back to slot %2; %3 new inscription(s), %4 shown.")
                             .arg(blocks.length).arg(oldestSlot).arg(n).arg(items.count)
            })
        }
    }

    onChannelIdChanged: d.reset()

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            LogosText {
                text: qsTr("Inscription history")
                font.weight: Theme.typography.weightMedium
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "inscriptionLatestButton"
                text: qsTr("Latest")
                Accessible.name: text
                enabled: root.nodeRunning && !d.busy
                onClicked: d.loadLatest()
            }
            LogosButton {
                objectName: "inscriptionScanButton"
                text: items.count || d.oldestSlot > 0 ? qsTr("Scan older") : qsTr("Scan recent")
                Accessible.name: text
                enabled: root.nodeRunning && !d.busy
                onClicked: d.scan(d.oldestSlot > 0)
            }
        }
        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Read from your node only. Shows what this channel has written on chain, newest first.")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        LogosText {
            objectName: "inscriptionHistoryStatus"
            Layout.fillWidth: true
            visible: d.status.length > 0
            text: d.status
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            Accessible.name: text
        }
        Repeater {
            model: items
            delegate: ColumnLayout {
                id: row
                required property int slot
                required property string tx
                required property string text
                required property int size
                required property string hex
                Layout.fillWidth: true
                spacing: Theme.spacing.tiny
                LogosText {
                    Layout.fillWidth: true
                    visible: row.text.length > 0
                    wrapMode: Text.WrapAnywhere
                    text: row.text
                    Accessible.name: qsTr("Inscription at slot %1: %2").arg(row.slot).arg(row.text)
                }
                LogosText {
                    Layout.fillWidth: true
                    visible: row.text.length === 0
                    wrapMode: Text.WrapAnywhere
                    text: qsTr("(%1 bytes, not text) %2…").arg(row.size).arg(row.hex)
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                HashRow {
                    label: qsTr("Slot %1").arg(row.slot)
                    value: row.tx
                    onCopyRequested: (t) => root.copyToClipboard(t)
                }
            }
        }
    }
}
