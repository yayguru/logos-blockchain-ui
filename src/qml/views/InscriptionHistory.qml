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
    // Bounds, so scanning months of a busy channel cannot grow memory without
    // limit: at most maxRows rows are kept (newest first; older ones drop off),
    // and only the newest maxImages keep their decoded picture (an image can be
    // up to 1.75 MiB on chain, ~2.4 MB as a data URL).
    property int maxRows: 500
    property int maxImages: 24

    signal copyToClipboard(string text)

    function scan() { d.scan() }
    readonly property int count: items.count
    readonly property string statusText: d.status
    readonly property bool busy: d.busy
    function itemText(i) { var r = items.get(i); return r ? (r.slot + " " + r.tx.slice(0, 8) + " " + (r.kind.length ? "[" + r.kind + " image " + r.size + " B" + (r.image.length ? ", shown" : "") + "]" : r.text)) : "" }

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

        // Images render from a cached copy the backend writes inside the plugin
        // folder (the only place the sandbox loads images from); the row shows
        // its type and size until the copy is ready.
        function loadPreview(key, hex) {
            if (!root.chain || !root.chain.imagePreviewAvailable) return
            root.chain.imagePreview(hex, function(ok, v) {
                if (!ok || !v || !v.url) return
                for (var k = 0; k < Math.min(items.count, root.maxImages); ++k) {
                    if (items.get(k).key === key) { items.setProperty(k, "image", String(v.url)); return }
                }
            })
        }

        function trim() {
            while (items.count > root.maxRows)
                items.remove(items.count - 1)
            for (var k = root.maxImages; k < items.count; ++k) {
                var r = items.get(k)
                if (r.image.length) {
                    items.setProperty(k, "image", "")
                    items.setProperty(k, "text", qsTr("[%1 image, %2 bytes; only the newest %3 images are shown]")
                                      .arg(String(r.kind).toUpperCase()).arg(r.size).arg(root.maxImages))
                }
            }
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
                        var kindNow = ChainRead.imageKind(op.payload.inscription)
                        var img = ""
                        var row = {
                            slot: slot,
                            tx: String(mt.hash || ""),
                            key: key,
                            image: img,
                            kind: kindNow,
                            text: (dec.printable && !kindNow.length) ? dec.text : "",
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
                        trim()
                        if (kindNow.length && at < root.maxImages)
                            loadPreview(key, String(op.payload.inscription || ""))
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
                required property string image
                required property string kind
                Layout.fillWidth: true
                spacing: Theme.spacing.tiny
                Image {
                    objectName: "inscriptionImage"
                    visible: row.image.length > 0
                    Layout.maximumWidth: Math.min(360, row.width)
                    Layout.preferredHeight: visible ? Math.min(240, Math.max(32, implicitHeight)) : 0
                    Layout.preferredWidth: visible ? Math.min(360, implicitWidth) : 0
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    sourceSize.width: 720
                    source: row.image
                    Accessible.name: qsTr("Image inscription at slot %1").arg(String(row.slot))
                }
                LogosText {
                    visible: row.kind.length > 0 && row.text.length === 0
                    text: qsTr("%1 image · %2 bytes").arg(row.kind.toUpperCase()).arg(row.size)
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                LogosText {
                    Layout.fillWidth: true
                    visible: row.text.length > 0
                    wrapMode: Text.WrapAnywhere
                    text: row.text
                    Accessible.name: qsTr("Inscription at slot %1: %2").arg(String(row.slot)).arg(row.text)
                }
                LogosText {
                    Layout.fillWidth: true
                    visible: row.text.length === 0 && row.kind.length === 0
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
