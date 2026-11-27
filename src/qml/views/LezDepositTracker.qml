import QtQuick
import QtQuick.Layouts
import QtCore

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units
import "ChainRead.js" as ChainRead

// Follows bridge deposits from "sent" to "credited on LEZ":
//   sent → in an L1 block → credited on LEZ (→ final on L1).
// LEZ 0.4 ("atomic deposits") mints a deposit it sees before L1 finality in a
// LEZ block pinned on the deposit's channel note, so the credit usually comes
// minutes after the L1 block; finality is only the latest it can come.
// Read-only: the local node answers the L1 part. When the backend offers
// lezGetAccountBalance (windows.11+), the public LEZ JSON-RPC answers the
// balance and "credited" is detected on its own; otherwise it is marked by hand.
// The list survives restarts and UI reinstalls.
LogosFrame {
    id: root
    objectName: "lezDepositTracker"

    // { info(cb), block(id, cb), lezAvailable, lezBalance(account, cb) } from BlockchainView.
    property var chain: null
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

    readonly property bool lezAuto: !!(root.chain && root.chain.lezAvailable)

    function trackSent(tx, amount, recipient, channelId, sentSlot) {
        d.add({ tx: String(tx), amount: String(amount), recipient: String(recipient || ""),
                channel: String(channelId || "").toLowerCase(), sentMs: Date.now(), sentSlot: sentSlot,
                inclSlot: -1, baseline: -1, balance: -1, credited: false, creditedMs: 0, note: "" })
    }

    // Called by the bridge view when a deposit was accepted by the node.
    function addSent(tx, amountLepta, recipient, channelId) {
        if (!root.chain) return
        root.chain.info(function(ok, v) {
            var inf = ok ? ChainRead.parseInfo(v) : null
            var slot = inf ? inf.slot : -1
            var e = { tx: String(tx), amount: String(amountLepta), recipient: String(recipient || ""),
                      channel: String(channelId || "").toLowerCase(), sentMs: Date.now(), sentSlot: slot,
                      inclSlot: -1, baseline: -1, balance: -1, credited: false, creditedMs: 0, note: "" }
            // The balance before the credit, read now, before the deposit is
            // even in an L1 block (LEZ cannot credit it earlier than that).
            if (root.lezAuto && d.isLez(e)) {
                root.chain.lezBalance(e.recipient, function(ok2, bal) {
                    if (ok2 && /^[0-9]+$/.test(String(bal).trim())) { e.baseline = Number(bal); e.balance = e.baseline }
                    d.add(e)
                })
            } else {
                d.add(e)
            }
        })
    }

    QtObject {
        id: d
        property var entries: []
        property bool busy: false
        property int lib: -1
        property int tip: -1
        property string tipId: ""
        property string status: ""
        property string lezError: ""

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
        function balanceText(e) {
            if (e.balance < 0) return ""
            return e.baseline >= 0
                   ? qsTr(" LEZ balance %1 (was %2 before the deposit).").arg(String(e.balance)).arg(String(e.baseline))
                   : qsTr(" LEZ balance %1.").arg(String(e.balance))
        }
        function text(e) {
            var s = stage(e)
            if (s === 3)
                return e.autoCredited
                       ? qsTr("Credited on LEZ: the balance went from %1 to %2.").arg(String(e.baseline)).arg(String(e.balance))
                       : qsTr("Marked as credited on LEZ.")
            if (s === 2)
                return isLez(e)
                       ? (root.lezAuto
                          ? qsTr("Final on L1: LIB passed slot %1, waiting for LEZ to credit it.").arg(String(e.inclSlot))
                            + balanceText(e)
                            + (e.baseline < 0 ? qsTr(" The balance before the deposit is unknown, so mark it yourself once it has arrived.") : "")
                          : qsTr("Final on L1: LIB passed slot %1. LEZ can credit it now. This build cannot read LEZ, so check the balance in a LEZ wallet and mark it here.")
                             .arg(String(e.inclSlot)))
                       : qsTr("Final on L1: LIB passed slot %1. The deposit sits in channel %2.")
                             .arg(String(e.inclSlot)).arg(e.channel.slice(0, 8) + "…")
            if (s === 1) {
                var left = lib >= 0 ? e.inclSlot - lib : -1
                var lezWait = isLez(e) ? qsTr(" Waiting for LEZ to credit it (LEZ 0.4: minutes; LEZ 0.3: after L1 finality).") : ""
                return left >= 0
                       ? qsTr("In an L1 block at slot %1.").arg(String(e.inclSlot)) + lezWait
                         + qsTr(" L1 finality: LIB is at slot %1, about %2 slots (≈%3 h) to go.")
                             .arg(String(lib)).arg(String(left)).arg((left / 3600).toFixed(1))
                       : qsTr("In an L1 block at slot %1.").arg(String(e.inclSlot)) + lezWait
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

        function markCredited(tx) {
            for (var i = 0; i < entries.length; ++i)
                if (entries[i].tx === tx) { entries[i].credited = true; entries[i].creditedMs = Date.now() }
            save()
        }

        // One refresh walks every entry in turn; every call is a read.
        function refresh() {
            if (busy || !entries.length || !root.chain) return
            busy = true
            status = qsTr("Checking…")
            root.chain.info(function(ok, v) {
                var inf = ok ? ChainRead.parseInfo(v) : null
                if (inf) { lib = inf.lib_slot; tip = inf.slot; tipId = inf.tip }
                step(0)
            })
        }
        function step(i) {
            if (i >= entries.length) {
                busy = false
                status = lib >= 0
                         ? qsTr("Checked %1. LIB slot %2, tip slot %3.")
                               .arg(new Date().toLocaleTimeString(Qt.locale(), Locale.ShortFormat)).arg(String(lib)).arg(String(tip))
                           + (lezError.length ? qsTr(" LEZ RPC: %1").arg(lezError) : "")
                         : qsTr("Could not read the chain state from the node.")
                save()
                return
            }
            var e = entries[i]
            if (e.credited) { step(i + 1); return }
            findInclusion(e, function() { checkLez(e, function() { step(i + 1) }) })
        }
        // The LEZ side, through the backend (the QML sandbox has no network).
        // Credited once the balance has grown by at least the deposit.
        function checkLez(e, next) {
            if (!root.lezAuto || !isLez(e)) { next(); return }
            root.chain.lezBalance(e.recipient, function(ok, bal) {
                var v = ok && /^[0-9]+$/.test(String(bal).trim()) ? Number(bal) : -1
                if (v < 0) { lezError = ok ? qsTr("unexpected answer") : String(bal); next(); return }
                lezError = ""
                e.balance = v
                // Before the L1 block nothing can have been credited yet, so
                // only that reading is a fair "before" (LEZ 0.4 may credit
                // right after inclusion, long before finality).
                if (e.baseline < 0 && stage(e) < 1) e.baseline = v
                if (e.baseline >= 0 && v >= e.baseline + Number(e.amount)) {
                    e.credited = true
                    e.autoCredited = true
                    e.creditedMs = Date.now()
                }
                next()
            })
        }
        // A deposit sent from here: walk back from the tip (at most 300 blocks)
        // to the slot it was sent at, looking for its hash.
        function findInclusion(e, next) {
            if (e.inclSlot >= 0 || e.sentSlot < 0 || !tipId.length) { next(); return }
            ChainRead.walkBack(root.chain, tipId, 300, Math.max(0, e.sentSlot - 30), function(b) {
                var txs = b.transactions || []
                for (var t = 0; t < txs.length; ++t) {
                    if ((txs[t].mantle_tx || {}).hash === e.tx) {
                        e.inclSlot = Number(b.header.slot)
                        e.note = ""
                        return true
                    }
                }
                return false
            }, function() {
                if (e.inclSlot < 0 && tip > e.sentSlot + 1800)
                    e.note = qsTr("Not found in the 30 minutes after sending. It may have been dropped; check the tx hash in Explorer.")
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
            text: root.lezAuto
                  ? qsTr("Each deposit goes: sent → in an L1 block → credited on LEZ. LEZ 0.4 credits a deposit minutes after its L1 block; LEZ 0.3 (the public testnet as of Nov 2026) only after L1 finality, which can take hours. Checked every 2 minutes while this page is open; reads only: L1 through your node, LEZ balances through the public LEZ RPC.")
                  : qsTr("Each deposit goes: sent → in an L1 block → credited on LEZ (minutes later with LEZ 0.4, after L1 finality with LEZ 0.3). Checked every 2 minutes while this page is open; reads only, through your node.")
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
                        visible: row.stage >= 1 && row.stage < 3 && row.recipient.length > 0
                        text: qsTr("Mark credited")
                        onClicked: d.markCredited(row.tx)
                    }
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
                    text: qsTr("%1 → %2").arg(Units.format(String(row.amount)) || row.amount).arg(row.recipient)
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
            LogosTextField { id: tSlot; objectName: "lezTrackSlot"; Layout.fillWidth: true; Layout.columnSpan: root.lezAuto ? 1 : 2; placeholderText: qsTr("L1 slot of the block (Explorer shows it)") }
            LogosTextField { id: tBase; objectName: "lezTrackBaseline"; visible: root.lezAuto; Layout.fillWidth: true; placeholderText: qsTr("LEZ balance before (optional)") }
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
                        baseline: root.lezAuto && tBase.text.trim().length ? Number(tBase.text.trim()) : -1,
                        balance: -1, credited: false, creditedMs: 0, note: s.length ? "" : qsTr("Slot unknown. Enter the L1 slot to follow finality.") })
                tTx.text = ""; tAmt.text = ""; tSlot.text = ""; tBase.text = ""
            }
        }
    }
}
