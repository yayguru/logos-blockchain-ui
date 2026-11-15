import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "ChainRead.js" as ChainRead

// Read-only viewer of a channel's inscriptions. It walks back from the chain
// tip through the blockchain module (get_block), 100 blocks per click, and
// lists this channel's inscriptions newest first. Nothing is signed or sent.
LogosFrame {
    id: root
    objectName: "inscriptionHistory"

    property string channelId: ""
    // { info(cb), block(id, cb) } from BlockchainView.
    property var chain: null
    property bool nodeRunning: false
    property int scanBlocks: 100

    signal copyToClipboard(string text)

    function scan() { d.scan() }
    readonly property int count: items.count
    readonly property string statusText: d.status
    readonly property bool busy: d.busy
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
        property string nextId: ""
        property int scanned: 0
        property string seen: "|"

        function cid() {
            return String(root.channelId || "").trim().replace(/^0x/i, "").toLowerCase()
        }
        function valid() { return /^[0-9a-f]{64}$/.test(cid()) }

        function reset() {
            items.clear()
            seen = "|"
            oldestSlot = -1
            nextId = ""
            scanned = 0
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
                        var dec = ChainRead.hexToText(op.payload.inscription)
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

        function scan() {
            if (!valid()) { status = qsTr("Enter or load a 64-character channel id first."); return }
            if (!root.chain) { status = qsTr("Not connected to the blockchain module."); return }
            if (nextId === "done") { status = qsTr("Reached the start of the node's chain."); return }
            busy = true
            status = qsTr("Reading %1 blocks…").arg(root.scanBlocks)
            var start = function(fromId) {
                ChainRead.walkBack(root.chain, fromId, root.scanBlocks, -1, function(b) {
                    addFrom([b])
                    nextId = String(b.header.parent_block || "")
                    return false
                }, function(ok, info, n) {
                    busy = false
                    scanned += n
                    if (!ok) { status = qsTr("Stopped after %1 blocks: %2").arg(n).arg(String(info)); return }
                    if (!nextId.length) nextId = "done"
                    status = qsTr("Read %1 blocks back to slot %2; %3 inscription(s) from this channel.")
                                 .arg(scanned).arg(String(oldestSlot)).arg(items.count)
                })
            }
            if (nextId.length) { start(nextId); return }
            root.chain.info(function(ok, v) {
                var inf = ok ? ChainRead.parseInfo(v) : null
                if (!inf || !inf.tip.length) { busy = false; status = qsTr("Could not read the chain tip."); return }
                start(inf.tip)
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
                objectName: "inscriptionScanButton"
                text: d.scanned > 0 ? qsTr("Scan older") : qsTr("Scan recent")
                Accessible.name: text
                enabled: root.nodeRunning && !d.busy && root.chain !== null
                onClicked: d.scan()
            }
        }
        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Read from your node only. Shows what this channel has written on chain, newest first; each click reads %1 more blocks.").arg(root.scanBlocks)
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
                    Accessible.name: qsTr("Inscription at slot %1: %2").arg(String(row.slot)).arg(row.text)
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
                    label: qsTr("Slot %1").arg(String(row.slot))
                    value: row.tx
                    onCopyRequested: (t) => root.copyToClipboard(t)
                }
            }
        }
    }
}
