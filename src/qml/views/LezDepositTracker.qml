import QtQuick
import QtQuick.Layouts
import QtCore

import Logos.Theme
import Logos.Controls

import "../controls"
import "NodeHttp.js" as NodeHttp

// Follows bridge deposits from "sent" to "credited on LEZ":
//   sent → in an L1 block → final on L1 (LIB passed it) → credited on LEZ.
// Read-only: the local node answers the L1 part, the public LEZ JSON-RPC
// answers the balance. The list survives restarts and UI reinstalls.
LogosFrame {
    id: root
    objectName: "lezDepositTracker"

    property string apiBase: "http://127.0.0.1:8080"
    property string lezRpcUrl: "https://testnet.lez.logos.co/"
    property string lezChannelId: ""
    property bool nodeRunning: false

    signal copyToClipboard(string text)

    Layout.fillWidth: true
    padding: Theme.spacing.medium
    backgroundColor: Theme.palette.surfaceRecessed
    borderColor: "transparent"
    radius: Theme.spacing.radiusMedium

    Settings {
        id: store
        location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation) + "/blockchain_ui_lez_tracker.ini"
        category: "LezTracker"
        property string entriesJson: "[]"
    }

    ListModel { id: rows }

    function refresh() { d.refresh() }
    readonly property int count: rows.count
    readonly property string statusText: d.status
    function lineAt(i) { var r = rows.get(i); return r ? ("stage=" + r.stage + " " + r.line) : "" }
    function track(tx, amount, account, slot, baseline) {
        d.add({ tx: tx, amount: String(amount), recipient: account, channel: root.lezChannelId.toLowerCase(),
                sentMs: Date.now(), sentSlot: -1, inclSlot: slot, baseline: baseline, balance: -1,
                credited: false, creditedMs: 0, note: "" })
    }

    // Called by the bridge view when a deposit was accepted by the node.
    function addSent(tx, amountLepta, recipient, channelId) {
        NodeHttp.getJson(root.apiBase + "/cryptarchia/info", 10000, function(ok, o) {
            var slot = ok && o.cryptarchia_info ? Number(o.cryptarchia_info.slot) : -1
            d.add({ tx: String(tx), amount: String(amountLepta), recipient: String(recipient || ""),
                    channel: String(channelId || "").toLowerCase(), sentMs: Date.now(), sentSlot: slot,
                    inclSlot: -1, baseline: -1, balance: -1, credited: false, creditedMs: 0, note: "" })
        })
    }

    QtObject {
        id: d
        property var entries: []
        property bool busy: false
        property int lib: -1
        property int tip: -1
        property string status: ""

        function load() {
            try { entries = JSON.parse(store.entriesJson) || [] } catch (e) { entries = [] }
            sync()
        }
        function save() {
            store.entriesJson = JSON.stringify(entries)
            sync()
        }
        function add(e) {
            for (var i = 0; i < entries.length; ++i)
                if (entries[i].tx === e.tx) return
            var copy = entries.slice()
            copy.unshift(e)
            entries = copy.slice(0, 20)
            save()
            refresh()
        }
        function remove(tx) {
            entries = entries.filter(function(e) { return e.tx !== tx })
            save()
        }
        function isLez(e) {
            return e.recipient.length > 0
                   && (!root.lezChannelId.length || e.channel === root.lezChannelId.toLowerCase() || e.channel === "")
        }
        function stage(e) {
            if (e.credited) return 3
            if (e.inclSlot >= 0 && lib >= e.inclSlot) return 2
            if (e.inclSlot >= 0) return 1
            return 0
        }
        function text(e) {
            var s = stage(e)
            if (s === 3)
                return qsTr("Credited on LEZ. Balance %1 (+%2 base units since tracking began).")
                       .arg(e.balance).arg(e.balance - e.baseline)
            if (s === 2)
                return isLez(e)
                       ? qsTr("Final on L1: LIB passed slot %1. Waiting for LEZ to credit the account%2.")
                             .arg(e.inclSlot).arg(e.balance >= 0 ? qsTr(" (balance now %1)").arg(e.balance) : "")
                       : qsTr("Final on L1: LIB passed slot %1. The deposit sits in channel %2.")
                             .arg(e.inclSlot).arg(e.channel.slice(0, 8) + "…")
            if (s === 1) {
                var left = lib >= 0 ? e.inclSlot - lib : -1
                return left >= 0
                       ? qsTr("In an L1 block at slot %1. Waiting for finality: LIB is at slot %2, about %3 slots (≈%4 h) to go.")
                             .arg(e.inclSlot).arg(lib).arg(left).arg((left / 3600).toFixed(1))
                       : qsTr("In an L1 block at slot %1. Waiting for finality.").arg(e.inclSlot)
            }
            if (e.note.length) return e.note
            return qsTr("Sent. Waiting for it to appear in an L1 block…")
        }
        function sync() {
            rows.clear()
            for (var i = 0; i < entries.length; ++i) {
                var e = entries[i]
                rows.append({ tx: e.tx, amount: e.amount, recipient: e.recipient,
                              stage: stage(e), line: text(e) })
            }
        }

        // One refresh walks every entry in turn; every call is a read.
        function refresh() {
            if (busy || !entries.length) return
            busy = true
            status = qsTr("Checking…")
            NodeHttp.getJson(root.apiBase + "/cryptarchia/info", 10000, function(ok, o) {
                if (ok && o.cryptarchia_info) {
                    lib = Number(o.cryptarchia_info.lib_slot)
                    tip = Number(o.cryptarchia_info.slot)
                }
                step(0)
            })
        }
        function step(i) {
            if (i >= entries.length) {
                busy = false
                status = qsTr("Checked %1. LIB slot %2, tip slot %3.")
                             .arg(new Date().toLocaleTimeString(Qt.locale(), Locale.ShortFormat)).arg(lib).arg(tip)
                save()
                return
            }
            var e = entries[i]
            if (e.credited) { step(i + 1); return }
            findInclusion(e, function() { checkLez(e, function() { step(i + 1) }) })
        }
        function findInclusion(e, next) {
            if (e.inclSlot >= 0 || e.sentSlot < 0 || tip < 0) { next(); return }
            var from = Math.max(0, e.sentSlot - 30)
            var to = Math.min(tip, e.sentSlot + 1800)
            NodeHttp.getBlocks(root.apiBase, "slot_from=" + from + "&slot_to=" + to + "&blocks_limit=300",
                function(ok, blocks) {
                    if (ok) {
                        for (var b = 0; b < blocks.length && e.inclSlot < 0; ++b) {
                            var txs = blocks[b].transactions || []
                            for (var t = 0; t < txs.length; ++t) {
                                if ((txs[t].mantle_tx || {}).hash === e.tx) {
                                    e.inclSlot = Number(blocks[b].header.slot)
                                    e.note = ""
                                    break
                                }
                            }
                        }
                        if (e.inclSlot < 0 && tip > e.sentSlot + 1800)
                            e.note = qsTr("Not found in the 30 minutes after sending. It may have been dropped; check the tx hash in Explorer.")
                    }
                    next()
                })
        }
        function checkLez(e, next) {
            if (!isLez(e)) { next(); return }
            NodeHttp.rpc(root.lezRpcUrl, "getAccountBalance", [e.recipient], function(ok, bal) {
                if (ok) {
                    var v = Number(bal)
                    if (e.baseline < 0) e.baseline = v
                    e.balance = v
                    if (v - e.baseline >= Number(e.amount)) {
                        e.credited = true
                        e.creditedMs = Date.now()
                    }
                } else {
                    e.note = e.inclSlot < 0 ? qsTr("LEZ RPC: %1").arg(bal) : e.note
                }
                next()
            })
        }
    }

    Component.onCompleted: d.load()

    Timer {
        interval: 120000
        repeat: true
        running: root.visible && root.nodeRunning && d.entries.length > 0
        triggeredOnStart: true
        onTriggered: d.refresh()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            LogosText {
                text: qsTr("Deposit tracker")
                font.weight: Theme.typography.weightMedium
            }
            Item { Layout.fillWidth: true }
            LogosButton {
                objectName: "lezTrackerRefresh"
                text: qsTr("Refresh")
                Accessible.name: text
                enabled: root.nodeRunning && !d.busy && d.entries.length > 0
                onClicked: d.refresh()
            }
        }
        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Each deposit goes: sent → in an L1 block → final on L1 → credited on LEZ. Finality currently lags many hours. Checked every 2 minutes while this page is open; reads only.")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        LogosText {
            objectName: "lezTrackerStatus"
            Layout.fillWidth: true
            visible: d.status.length > 0
            text: d.status
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textTertiary
            Accessible.name: text
        }
        LogosText {
            visible: rows.count === 0
            text: qsTr("No deposits tracked yet. New bridge deposits are added automatically.")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textTertiary
        }

        Repeater {
            model: rows
            delegate: ColumnLayout {
                id: row
                required property string tx
                required property string amount
                required property string recipient
                required property int stage
                required property string line
                Layout.fillWidth: true
                spacing: Theme.spacing.tiny

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.tiny
                    Repeater {
                        model: [qsTr("Sent"), qsTr("In block"), qsTr("Final"), qsTr("Credited")]
                        delegate: LogosText {
                            required property int index
                            required property string modelData
                            text: (index <= row.stage ? "● " : "○ ") + modelData + (index < 3 ? "  ›" : "")
                            font.pixelSize: Theme.typography.secondaryText
                            color: index <= row.stage ? Theme.palette.success : Theme.palette.textTertiary
                        }
                    }
                    Item { Layout.fillWidth: true }
                    LogosButton {
                        text: qsTr("Forget")
                        onClicked: d.remove(row.tx)
                    }
                }
                LogosText {
                    objectName: "lezTrackerLine"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: row.line
                    Accessible.name: text
                }
                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    visible: row.recipient.length > 0
                    text: qsTr("%1 base units → %2").arg(row.amount).arg(row.recipient)
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                HashRow {
                    label: qsTr("Deposit tx")
                    value: row.tx
                }
            }
        }

        // Track a deposit made earlier (or from another tool).
        LogosText {
            text: qsTr("Track an earlier deposit")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Theme.spacing.small
            rowSpacing: Theme.spacing.tiny
            LogosTextField { id: tTx; objectName: "lezTrackTx"; Layout.fillWidth: true; Layout.columnSpan: 2; placeholderText: qsTr("Deposit tx hash (64 hex)") }
            LogosTextField { id: tAmt; objectName: "lezTrackAmount"; Layout.fillWidth: true; placeholderText: qsTr("Amount in base units") }
            LogosTextField { id: tAcc; objectName: "lezTrackAccount"; Layout.fillWidth: true; placeholderText: qsTr("LEZ account (base58)") }
            LogosTextField { id: tSlot; objectName: "lezTrackSlot"; Layout.fillWidth: true; placeholderText: qsTr("L1 slot of the block (optional)") }
            LogosTextField { id: tBase; objectName: "lezTrackBaseline"; Layout.fillWidth: true; placeholderText: qsTr("LEZ balance before (optional)") }
        }
        LogosButton {
            objectName: "lezTrackAdd"
            text: qsTr("Track")
            Accessible.name: text
            enabled: /^[0-9a-fA-F]{64}$/.test(tTx.text.trim()) && /^[0-9]+$/.test(tAmt.text.trim())
                     && /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(tAcc.text.trim())
                     && (tSlot.text.trim() === "" || /^[0-9]+$/.test(tSlot.text.trim()))
                     && (tBase.text.trim() === "" || /^[0-9]+$/.test(tBase.text.trim()))
            onClicked: {
                var s = tSlot.text.trim()
                d.add({ tx: tTx.text.trim().toLowerCase(), amount: tAmt.text.trim(), recipient: tAcc.text.trim(),
                        channel: root.lezChannelId.toLowerCase(), sentMs: Date.now(),
                        sentSlot: -1, inclSlot: s.length ? Number(s) : -1,
                        baseline: tBase.text.trim().length ? Number(tBase.text.trim()) : -1,
                        balance: -1, credited: false, creditedMs: 0, note: s.length ? "" : qsTr("Slot unknown; only the LEZ credit is checked.") })
                tTx.text = ""; tAmt.text = ""; tSlot.text = ""; tBase.text = ""
            }
        }
    }
}
