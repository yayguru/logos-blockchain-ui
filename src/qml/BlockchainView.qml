import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtCore

import Logos.Theme
import Logos.Controls
// BlockchainStatus enum (NotStarted/Starting/Running/Stopping/Stopped/Error)
// declared in BlockchainBackend.rep — registered with QML by the replica
// factory plugin.
import Logos.BlockchainBackend 1.0

import "controls"
import "dialogs"
import "views"
import "Units.js" as Units
import "WalletTools.js" as WalletTools

Rectangle {
    id: root

    readonly property var backend: logos.module("blockchain_ui")
    // `ready` can't be a binding on logos.isViewModuleReady(): that's a
    // Q_INVOKABLE method, not a Q_PROPERTY, so the binding wouldn't refresh
    // when the replica transitions to Valid. Drive it from the bridge's
    // viewModuleReadyChanged signal instead.
    property bool ready: false

    // Never-connected and lost-the-connection look identical in `status`, but
    // one is a fresh launch and the other is a node whose status is now stale.
    property bool everReady: false
    onReadyChanged: if (root.ready) { root.everReady = true; resume.syncModuleAutostart(); _d.refreshLez(); _d.loadPowConfig() }

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "blockchain_ui") {
                root.ready = isReady && root.backend !== null
                if (root.ready) {
                    root.refreshPeerId()
                    _d.captureConfigBaseline()
                }
            }
        }
    }

    Component.onCompleted: {
        // Cover the case where the replica is already Valid by the time
        // we attach the Connections handler.
        root.ready = root.backend !== null && logos.isViewModuleReady("blockchain_ui")
        if (root.ready) {
            root.refreshPeerId()
            _d.captureConfigBaseline()
        }
        if (root.needsSetup)
            root.openSetup()
    }

    // Graceful shutdown: if the window is closed while the node is running,
    // veto the close, stop the node, then close once it has stopped.
    property bool quitting: false

    function _nodeBusy() {
        return root.backend
            && (root.backend.status === BlockchainBackend.Running
                || root.backend.status === BlockchainBackend.Starting
                || root.backend.status === BlockchainBackend.Stopping)
    }

    Connections {
        target: root.Window.window
        enabled: root.Window.window !== null
        ignoreUnknownSignals: true
        function onClosing(close) {
            if (!root.quitting && root._nodeBusy()) {
                root.quitting = true
                close.accepted = false
                root.backend.stopBlockchain()
            }
        }
    }

    Connections {
        target: root.backend
        enabled: root.quitting && root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.quitting && !root._nodeBusy() && root.Window.window)
                root.Window.window.close()
        }
    }

    // Models live on the C++ backend and are auto-remoted by ui-host as
    // "<module>/<propertyName>". QML acquires them via logos.model(...).
    readonly property var accountsModel: logos.model("blockchain_ui", "accounts")
    readonly property var blockModel: logos.model("blockchain_ui", "blocks")
    readonly property var claimsModel: logos.model("blockchain_ui", "claims")
    readonly property var miningClaimsModel: logos.model("blockchain_ui", "miningClaims")

    // Clipboard must be handled here in the UI-host (GUI) process. The backend
    // .rep source runs in a separate, non-GUI ViewModuleHost subprocess where
    // QGuiApplication::clipboard() segfaults (process exits with code 11), so
    // we copy from QML via a hidden TextEdit instead of calling the backend.
    function copyText(text) {
        clipboardHelper.text = text || ""
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        clipboardHelper.deselect()
        clipboardHelper.text = ""
    }

    TextEdit {
        id: clipboardHelper
        visible: false
    }

    LogosToast {
        id: keystoreBackupToast
        z: 1
        width: Math.min(560, root.width - 2 * Theme.spacing.xxlarge)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.large
        severity: LogosNotice.Success
    }

    LogosToast {
        id: stopFailedToast
        z: 1
        width: Math.min(560, root.width - 2 * Theme.spacing.xxlarge)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.large
        duration: 12000
    }

    ConfigUpgradeDialog {
        id: configUpgradeDialog
        objectName: "configUpgradeDialog"

        configState: root.backend ? root.backend.configState
                                  : BlockchainBackend.ConfigUnknown
        hasKeystore: !!root.backend && root.backend.nodeKeystorePath.length > 0
        refusalReason: root.backend ? root.backend.lastErrorMessage : ""

        // Setup opens underneath, and the config stays Stale until a new one is
        // chosen, so the dialog has to step aside itself.
        onStartFreshRequested: {
            configUpgradeDialog.dismiss()
            root.openSetup()
        }
    }

    // Self libp2p peer id, derived from the selected user config (no running
    // node required). Refreshed when ready and whenever the config changes.
    property string peerId: ""

    // Whether the app has a config to run a node from. Everything about which
    // screen shows follows from this rather than from a flag set once at
    // startup: same state, same screen, every time.
    readonly property bool hasConfig: root.ready && !!root.backend
        && root.backend.userConfig.length > 0

    // Setup is open. Held on the backend rather than here: this view is
    // destroyed and rebuilt when the shell switches away from the app, and a
    // QML property would come back false, dropping anyone mid-setup onto the
    // dashboard.
    readonly property bool setupOpen: !!root.backend && root.backend.setupInProgress
    // newNode false = configure the node we already have; true = create a second
    // one, which the backend places in a fresh directory of its own choosing.
    function openSetup(newNode) {
        if (!root.backend)
            return
        _d.setupNewNode = newNode === true
        root.backend.setupInProgress = true
    }
    function closeSetup() { if (root.backend) root.backend.setupInProgress = false }

    // A node with no config cannot do anything else, so setup opens itself.
    // Re-armed rather than one-shot: if the config ever goes away, this is true
    // again and setup comes back, instead of leaving the user on a node screen
    // that can only fail.
    readonly property bool needsSetup: root.ready && !!root.backend && !root.hasConfig
    onNeedsSetupChanged: if (root.needsSetup) root.openSetup()

    // Every route into setup lands here — first run, and Settings' Change
    // config. The flow resets itself and reloads what its later steps read;
    // this view no longer knows what those are.
    onSetupOpenChanged: if (root.setupOpen) onboardingFlow.begin()

    function refreshPeerId() {
        if (!root.backend || !root.backend.userConfig) {
            root.peerId = ""
            return
        }
        logos.watch(
            root.backend.getPeerId(),
            function(result) { root.peerId = result.success ? result.value : "" },
            function(error) { root.peerId = "" }
        )
    }

    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onUserConfigChanged() { root.refreshPeerId() }
        function onStopFailed(reason) {
            if (root.quitting && root.Window.window) {
                root.Window.window.close()
                return
            }
            stopFailedToast.show(qsTr("Couldn't stop the node"), reason)
        }
        // Ticks per block the node processes, including while it catches up.
        // The count itself is meaningless; the change is the proof of life.
        function onProcessedBlockCountChanged() { monitor.nodeProvedAlive() }

        function onStatusChanged() {
            if (!root.backend)
                return
            if (root.backend.status === BlockchainBackend.Stopped
                    || root.backend.status === BlockchainBackend.Error)
                configUpgradeDialog.rearm()
            if (root.backend.status === BlockchainBackend.Running)
                _d.captureConfigBaseline()
        }
    }

    // ---- Auto-resume (yayguru Windows build) ----
    // Reinstalling or updating this UI destroys BlockchainBackend, and its
    // destructor stops the node (teardown must not leave an orphan node behind
    // a closed app). Without this the node stays stopped after every update
    // until someone presses Start Node. So the user's INTENT is persisted here:
    // "the node should be running" (set when it reaches Running, cleared only by
    // the user's own Stop Node) and "mining should be on" (set when mining
    // starts, cleared only by Stop Mining). A fresh view that finds the node
    // idle while the intent says otherwise starts it again with the SAME
    // existing config and re-arms mining once synced. It never creates a config
    // or opens setup, runs at most once per view and once per two minutes, and
    // stays put if anything already answers on the node API, so it cannot start
    // a second node. Not a watchdog: it acts only when the UI is (re)loaded.
    Settings {
        id: resumeStore
        location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation) + "/blockchain_ui_resume.ini"
        category: "AutoResume"
        property bool enabled: true
        property bool nodeWanted: false
        property bool miningWanted: false
        property string configPath: ""
        property double lastAttemptMs: 0
    }

    QtObject {
        id: resume
        objectName: "autoResume"
        property bool nodeAttempted: false
        property bool miningAttempted: false
        property int idleTicks: 0
        property string note: ""
        // A status line, not a log: it goes away a minute after it last changed.
        onNoteChanged: if (note.length) noteClear.restart()
        property Timer noteClear: Timer { interval: 60000; onTriggered: resume.note = "" }
        readonly property bool statusIdle: !!root.backend
            && (root.backend.status === BlockchainBackend.NotStarted
                || root.backend.status === BlockchainBackend.Stopped)

        // Hands the same switch to the module (windows.11+), which then keeps
        // the node across UI reinstalls and restarts it when it is loaded.
        function syncModuleAutostart() {
            if (!root.backend || typeof root.backend.setNodeAutostart !== "function")
                return
            logos.watch(root.backend.setNodeAutostart(resumeStore.enabled),
                function(result) { if (!result.success) console.warn("autostart_set:", result.error) },
                function(error) { console.warn("autostart_set:", error) })
        }

        function tick() {
            if (nodeAttempted || !root.ready || !root.backend)
                return
            if (!resumeStore.enabled || !resumeStore.nodeWanted)
                return
            if (root.setupOpen || !root.hasConfig || root.quitting)
                return
            // Only the config the node last ran with. A changed or newly
            // generated config is the user's business, not ours.
            if (resumeStore.configPath.length === 0
                    || root.backend.userConfig !== resumeStore.configPath)
                return
            if (root.backend.configState === BlockchainBackend.ConfigStale
                    || root.backend.configState === BlockchainBackend.ConfigUnreadable)
                return
            // A fresh replica can read NotStarted before it has asked the module;
            // insist on idle for three ticks in a row (~9 s) before acting.
            if (!statusIdle) { idleTicks = 0; return }
            idleTicks += 1
            if (idleTicks < 3)
                return
            if (Date.now() - resumeStore.lastAttemptMs < 120000)
                return
            nodeAttempted = true
            // No probe of 127.0.0.1:8080 here: Basecamp's sandbox blocks network
            // access from ui_qml. The backend adopts a node the module kept
            // running (status Running, so this never gets here), and the
            // module's start() is a no-op for the config it already runs.
            resumeStore.lastAttemptMs = Date.now()
            resume.note = qsTr("Resuming the node after the app or UI was restarted…")
            root.backend.startBlockchain()
        }

        function tickMining() {
            if (miningAttempted || !root.backend)
                return
            if (!resumeStore.enabled || !resumeStore.miningWanted)
                return
            if (!root.nodeRunning || !monitor.synced || root.backend.miningActive)
                return
            miningAttempted = true
            logos.watch(root.backend.powStartMining(),
                function(result) {
                    resume.note = result.success ? (resume.nodeAttempted ? qsTr("Node and mining resumed.") : qsTr("Mining resumed."))
                                                 : qsTr("Could not resume mining: %1").arg(_d.errorText(result.error))
                },
                function(error) { resume.note = qsTr("Could not resume mining: %1").arg(_d.errorText(error)) })
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.ready && !resume.nodeAttempted && resumeStore.enabled && resumeStore.nodeWanted
        onTriggered: resume.tick()
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.nodeRunning && !resume.miningAttempted && resumeStore.enabled && resumeStore.miningWanted
        onTriggered: resume.tickMining()
    }
    Connections {
        target: resumeStore
        function onEnabledChanged() { resume.syncModuleAutostart() }
    }
    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.backend && _d.restartPending
                    && root.backend.status === BlockchainBackend.Stopped) {
                root.backend.startBlockchain()
            }
            if (root.backend && root.backend.status === BlockchainBackend.Running) {
                if (_d.restartPending) {
                    _d.restartPending = false
                    _d.threadsMessage = qsTr("Node restarted with the new thread count; mining resumes once synced.")
                    resume.miningAttempted = false
                }
                _d.loadPowConfig()
                _d.refreshLez()
                resumeStore.nodeWanted = true
                resumeStore.configPath = root.backend.userConfig
                if (resume.note.indexOf("Resuming") === 0)
                    resume.note = resumeStore.miningWanted ? qsTr("Node resumed; mining resumes once synced.") : qsTr("Node resumed.")
            }
        }
        function onMiningActiveChanged() {
            if (root.backend && root.backend.miningActive)
                resumeStore.miningWanted = true
        }
        function onUserConfigChanged() { _d.loadPowConfig(); _d.refreshLez() }
        function onNodeKeystorePathChanged() { _d.refreshLez() }
    }

    // Read-only chain access for the wallet's tracker and inscription history.
    // Goes through the module API: Basecamp blocks network access for ui_qml
    // plugins, so these views cannot use the node's HTTP API directly.
    QtObject {
        id: chainReader
        function call(make, cb) {
            if (!root.backend) { cb(false, qsTr("Not connected to the blockchain module.")); return }
            try {
                logos.watch(make(), function(r) {
                    if (r && r.success) cb(true, r.value)
                    else cb(false, r && r.error ? String(r.error) : qsTr("No answer."))
                }, function(e) { cb(false, String(e)) })
            } catch (e) { cb(false, String(e.message || e)) }
        }
        function info(cb) { call(function() { return root.backend.getCryptarchiaInfo() }, cb) }
        function block(id, cb) { call(function() { return root.backend.getBlock(id) }, cb) }
        // LEZ balances through the backend (windows.11+): C++ may use the
        // network, ui_qml may not. Absent on older backends.
        readonly property bool lezAvailable: !!(root.backend && typeof root.backend.lezGetAccountBalance === "function")
        function lezBalance(account, cb) { call(function() { return root.backend.lezGetAccountBalance(account) }, cb) }
        // File size + image type (windows.13); ui_qml cannot stat files.
        readonly property bool inspectAvailable: !!(root.backend && typeof root.backend.inspectFile === "function")
        function inspectFile(path, cb) { call(function() { return root.backend.inspectFile(path) }, cb) }
    }

    // Node status. Owns its own timers, backoff, sync debounce and progress
    // tracking; see controls/NodeStatusMonitor.qml. Sits outside any layout
    // because it is an Item with no visual presence.
    NodeStatusMonitor {
        id: monitor
        backend: root.backend
        running: root.nodeRunning
    }

    // Folder of the user config: keystore.yaml, inscribe_key.json and
    // lez_account.json live here. Not the chain database folder.
    readonly property string configFolder: {
        var p = root.backend && root.backend.userConfig ? String(root.backend.userConfig) : ""
        if (p.indexOf("file:///") === 0) p = p.substring(8)
        var i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"))
        return i > 0 ? p.substring(0, i) : ""
    }

    readonly property bool nodeRunning:
        root.ready && root.backend
        && root.backend.status === BlockchainBackend.Running

    // Why the node cannot answer right now, or empty when it can. One string,
    // computed where the status actually lives, so a view does not have to
    // infer "start the node" from a single boolean and be wrong about it — a
    // node that is bootstrapping IS running, and one whose module died needs
    // the app restarted, not the node started.
    readonly property string nodeOffReason: {
        if (!root.ready || !root.backend)
            return qsTr("Connecting to the node service…")
        if (!root.moduleReachable)
            return qsTr("The node service stopped responding. Restart the app.")
        if (root.backend.configState === BlockchainBackend.ConfigStale)
            return qsTr("This config is from an older release, so the node can't start with it.")
        if (root.backend.configState === BlockchainBackend.ConfigUnreadable)
            return qsTr("This config can't be read, so the node can't start.")
        switch (root.backend.status) {
        case BlockchainBackend.Running:
            return monitor.synced ? "" : qsTr("The node is still catching up.")
        case BlockchainBackend.Starting:
            return qsTr("The node is starting…")
        case BlockchainBackend.Stopping:
            return qsTr("The node is stopping…")
        case BlockchainBackend.Error:
            return qsTr("The node stopped unexpectedly. Start it again from the Node tab.")
        default:
            return qsTr("Start the node from the Node tab.")
        }
    }

    // Error only when something is wrong and the user must act; Info for the
    // transient and the expected. A node that has not been started yet is not
    // a warning — it is Tuesday.
    readonly property int nodeOffSeverity: {
        if (!root.moduleReachable)
            return LogosNotice.Error
        if (root.backend && root.backend.configState === BlockchainBackend.ConfigStale)
            return LogosNotice.Info
        if (root.backend && root.backend.configState === BlockchainBackend.ConfigUnreadable)
            return LogosNotice.Error
        if (root.backend && root.backend.status === BlockchainBackend.Error)
            return LogosNotice.Error
        return LogosNotice.Info
    }

    readonly property bool moduleReachable:
        !root.backend || root.backend.nodeModuleReachable === undefined
        || root.backend.nodeModuleReachable


    // The backend polls and derives; this only says whether anyone is looking,
    // which is the one half of it the backend cannot know. Section 4 is Mining,
    // the only place the claimable counts are shown — keep this in step with
    // the tab bar.
    Binding {
        target: root.backend
        property: "claimablePollActive"
        value: root.nodeRunning && _d.currentPage === 1 && opPage.sectionIndex === 4
        when: root.backend !== null
        restoreMode: Binding.RestoreNone
    }

    // Wallet's claimable ("pending") vouchers. Refreshed shortly after incoming
    // blocks, and once when the node starts running.
    property string claimableVouchersJson: ""
    // Set by an incoming block, cleared by the refresh it schedules.
    property bool _vouchersDirty: false

    function refreshClaimableVouchers() {
        if (!root.backend || root.backend.status !== BlockchainBackend.Running)
            return
        if (!monitor.modeOnline)
            return
        root._vouchersDirty = false
        logos.watch(
            root.backend.getClaimableVouchers(),
            function(result) { if (result.success) root.claimableVouchersJson = result.value },
            function(error) { /* keep last known list on transient errors */ }
        )
    }

    // Incoming blocks arrive as row insertions on the remoted block model. A
    // new block is proof the node is alive, so it also collapses any status-poll
    // backoff instead of making the user wait the interval out.
    Connections {
        target: root.blockModel
        enabled: root.blockModel !== null
        ignoreUnknownSignals: true
        function onRowsInserted() {
            monitor.nodeProvedAlive()
            root._vouchersDirty = true
            leaderRewardsView.blockArrived()
        }
    }

    // Coalesced, NOT called per row. A catching-up node inserts hundreds of rows
    // a second, and each refresh is a blocking call into the same module — so
    // doing it per block buries the module's event loop under the very calls
    // that are meant to observe it, and the status poll queues behind them until
    // it times out and the node reads as dead. The count only has to be right
    // shortly after a burst, never during one.
    Timer {
        interval: 2000
        repeat: true
        running: root.voucherGateOpen
        onTriggered: if (root._vouchersDirty) root.refreshClaimableVouchers()
    }

    readonly property bool voucherGateOpen: root.nodeRunning && monitor.modeOnline
    onVoucherGateOpenChanged: if (root.voucherGateOpen) root.refreshClaimableVouchers()

    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.backend.status !== BlockchainBackend.Running)
                root.claimableVouchersJson = ""
        }
    }

    QtObject {
        id: _d

        // Last failure from the Fund button, shown on the dashboard's Mining
        // Rewards card — the header has nowhere to put a message.
        property string miningError: ""

        property bool claimBusy: false
        property bool claimSuccess: false
        property string claimMessage: ""

        // Whether the open wizard run is creating a second node rather than
        // configuring the current one.
        property bool setupNewNode: false

        // What the node is running, or would be if started right now. Captured
        // when the app settles and again whenever the node reaches Running.
        property string baselineUserConfig: ""
        property string baselineDeploymentConfig: ""

        function captureConfigBaseline() {
            if (!root.backend)
                return
            _d.baselineUserConfig = root.backend.userConfig
            _d.baselineDeploymentConfig = root.backend.deploymentConfig
        }

        readonly property bool configChangedSinceStart:
            !!root.backend
            && (root.backend.userConfig !== _d.baselineUserConfig
                || root.backend.deploymentConfig !== _d.baselineDeploymentConfig)

        // For one-shot results (a failed claim, an explorer lookup) that have no
        // surrounding state to frame them. Deliberately not used for the status
        // poll: its message lands in the hero's sub-line under a headline that
        // already gives the verdict, and a replaying node answers that call with
        // a diagnosed *progress* message which "Error: " would contradict.
        // Plain-language first, the node's own words after "Details" (see
        // WalletTools.humanError), amounts in this locale's format.
        function errorText(message) {
            return qsTr("Error: %1").arg(WalletTools.humanError(message, function(l) { return Units.format(l) }))
        }

        // Page 0 is setup, page 1 is the node. Derived, never assigned — see
        // root.setupOpen for the two events that move it.
        readonly property int currentPage: root.setupOpen ? 0 : 1

        // Runtime override on the node's own default — nothing is written to the
        // config, so this is undone by a node restart rather than by editing the
        // targets back in.
        function setAutoClaim(enabled) {
            if (!root.backend)
                return
            _d.claimMessage = ""
            logos.watch(
                enabled ? root.backend.powStartAutoClaim() : root.backend.powStopAutoClaim(),
                function(result) {
                    if (!result.success) {
                        _d.claimSuccess = false
                        _d.claimMessage = enabled
                            ? qsTr("Could not turn auto-claim on: %1").arg(_d.errorText(result.error))
                            : qsTr("Could not turn auto-claim off: %1").arg(_d.errorText(result.error))
                    }
                },
                function(error) {
                    _d.claimSuccess = false
                    _d.claimMessage = _d.errorText(error)
                }
            )
        }

        // ---- Mining control (windows.13) ----
        function startMining() {
            if (!root.backend)
                return
            _d.miningError = ""
            resumeStore.miningWanted = true
            logos.watch(root.backend.powStartMining(),
                function(result) { if (!result.success) _d.miningError = _d.errorText(result.error) },
                function(error) { _d.miningError = _d.errorText(error) })
        }
        function stopMining() {
            if (!root.backend)
                return
            _d.miningError = ""
            // The user's own choice: auto-resume must not turn it back on.
            resumeStore.miningWanted = false
            logos.watch(root.backend.powStopMining(),
                function(result) { if (!result.success) _d.miningError = _d.errorText(result.error) },
                function(error) { _d.miningError = _d.errorText(error) })
        }

        property string currentThreads: ""
        property bool threadsBusy: false
        property bool threadsOk: false
        property string threadsMessage: ""
        property bool restartOffered: false
        property bool restartPending: false

        function loadPowConfig() {
            if (!root.backend || !root.backend.userConfig)
                return
            logos.watch(root.backend.getPowConfig(root.backend.userConfig),
                function(result) {
                    if (!result.success)
                        return
                    try {
                        var o = typeof result.value === "string" ? JSON.parse(result.value) : result.value
                        var mt = o ? o.max_threads : undefined
                        if (mt === null || mt === undefined || mt === "" || mt === "null")
                            _d.currentThreads = (o && o.max_tickets_per_block !== undefined && String(o.max_tickets_per_block).length) ? "auto" : "1"
                        else
                            _d.currentThreads = String(mt)
                    } catch (e) {}
                },
                function(error) {})
        }

        // threads: "" = one per CPU, else a count. Live on module windows.5+,
        // written to the config either way.
        function applyThreads(threads) {
            if (!root.backend)
                return
            _d.threadsBusy = true
            _d.threadsMessage = ""
            _d.restartOffered = false
            var label = threads === "" ? qsTr("all cores") : qsTr("%n thread(s)", "", parseInt(threads))
            var wasMining = opPage.miningActive || resumeStore.miningWanted
            var persistOnly = function(liveError) {
                var cfg = {}
                cfg.max_threads = threads === "" ? null : parseInt(threads)
                logos.watch(root.backend.powConfigure(root.backend.userConfig, JSON.stringify(cfg)),
                    function(r) {
                        _d.threadsBusy = false
                        _d.threadsOk = r.success
                        if (!r.success) {
                            _d.threadsMessage = qsTr("Could not save: %1").arg(_d.errorText(r.error))
                            return
                        }
                        _d.currentThreads = threads === "" ? "auto" : threads
                        if (root.nodeRunning) {
                            _d.threadsMessage = qsTr("Saved %1 to the config. This node module cannot change threads live, so it takes effect when the node restarts (mining is switched back on automatically).").arg(label)
                            _d.restartOffered = true
                        } else {
                            _d.threadsMessage = qsTr("Saved %1. Used when the node starts.").arg(label)
                        }
                    },
                    function(e) { _d.threadsBusy = false; _d.threadsOk = false; _d.threadsMessage = _d.errorText(e) })
            }
            if (!root.nodeRunning || typeof root.backend.powSetMaxThreads !== "function") {
                persistOnly("")
                return
            }
            logos.watch(root.backend.powSetMaxThreads(threads),
                function(result) {
                    if (!result.success) {
                        var err = String(result.error || "")
                        // A module without the method (windows.4 and older).
                        if (/not running/i.test(err)) {
                            _d.threadsBusy = false; _d.threadsOk = false
                            _d.threadsMessage = _d.errorText(err)
                            return
                        }
                        persistOnly(err)
                        return
                    }
                    var v = {}
                    try { v = typeof result.value === "string" ? JSON.parse(result.value) : (result.value || {}) } catch (e) {}
                    _d.threadsBusy = false
                    _d.threadsOk = true
                    _d.currentThreads = threads === "" ? "auto" : threads
                    _d.threadsMessage = v.persisted === false
                        ? qsTr("Now mining with %1 (live). Could not save it to the config: %2").arg(label).arg(String(v.persist_error || ""))
                        : qsTr("Now mining with %1 — applied live and saved to the config.").arg(label)
                    // Re-arm: a no-op when mining is already on.
                    if (wasMining)
                        logos.watch(root.backend.powStartMining(), function(r) {}, function(e) {})
                },
                function(error) { persistOnly(String(error)) })
        }

        // ---- Settings: database reset (windows.13) ----
        property bool resetBusy: false
        property string resetMessage: ""
        property bool resetOk: false
        function resetDatabase() {
            if (!root.backend || typeof root.backend.resetDatabase !== "function")
                return
            _d.resetBusy = true
            _d.resetMessage = ""
            logos.watch(root.backend.resetDatabase(),
                function(r) {
                    _d.resetBusy = false
                    _d.resetOk = r.success
                    if (r.success) {
                        var v = r.value || {}
                        _d.resetMessage = qsTr("Deleted %1 (%2 MB). Keys and config were not touched. Start the node to re-sync.")
                            .arg(String(v.deleted || "")).arg(Math.round(Number(v.freedMb || 0)))
                            + (v.leftover ? " " + qsTr("Could not remove the emptied folder %1; delete it by hand.").arg(String(v.leftover)) : "")
                    } else {
                        _d.resetMessage = String(r.error || "")
                    }
                },
                function(e) { _d.resetBusy = false; _d.resetOk = false; _d.resetMessage = String(e) })
        }

        // ---- Built-in LEZ account (windows.13) ----
        property var lez: ({ exists: false })
        property string lezError: ""
        property string lezBalance: ""
        property bool lezBusy: false
        readonly property bool lezSupported: !!root.backend && typeof root.backend.lezAccount === "function"
        function refreshLez() {
            if (!_d.lezSupported)
                return
            logos.watch(root.backend.lezAccount(),
                function(r) {
                    if (r.success) { _d.lez = r.value || ({ exists: false }); _d.lezError = "" }
                    else { _d.lez = ({ exists: false }); _d.lezError = String(r.error || "") }
                    _d.refreshLezBalance()
                },
                function(e) { _d.lezError = String(e) })
        }
        function refreshLezBalance() {
            if (!_d.lez || !_d.lez.exists || !chainReader.lezAvailable) { _d.lezBalance = ""; return }
            chainReader.lezBalance(_d.lez.account_id, function(ok, v) { _d.lezBalance = ok ? String(v) : "" })
        }
        function createLez() {
            if (!_d.lezSupported)
                return
            _d.lezBusy = true
            logos.watch(root.backend.lezCreateAccount(),
                function(r) {
                    _d.lezBusy = false
                    if (r.success) { _d.lez = r.value || ({ exists: false }); _d.lezError = ""; _d.refreshLezBalance() }
                    else _d.lezError = String(r.error || "")
                },
                function(e) { _d.lezBusy = false; _d.lezError = String(e) })
        }
        function backupLez(dest) {
            logos.watch(root.backend.backupLezAccount(dest),
                function(r) {
                    if (r.success) { keystoreBackupToast.show(qsTr("LEZ account key saved"), r.value); _d.refreshLez() }
                    else _d.lezError = String(r.error || "")
                },
                function(e) { _d.lezError = String(e) })
        }

        // Stop and start the same node with the same config, keeping the
        // user's intent so mining comes back once synced.
        function restartNode() {
            if (!root.backend || !root.nodeRunning)
                return
            _d.restartOffered = false
            _d.restartPending = true
            _d.threadsOk = true
            _d.threadsMessage = qsTr("Restarting the node…")
            root.backend.stopBlockchain()
        }

        // An empty address lets the node pay whichever target is furthest below
        // its threshold, which is the same choice auto-claim makes.
        function claimPowRewards(addressHex) {
            if (!root.backend)
                return
            _d.claimBusy = true
            _d.claimSuccess = false
            _d.claimMessage = ""
            logos.watch(
                root.backend.powClaim(addressHex),
                function(result) {
                    _d.claimBusy = false
                    _d.claimSuccess = result.success
                    _d.claimMessage = result.success
                        ? qsTr("Claim submitted: %1").arg(result.value)
                        : qsTr("Claim failed: %1").arg(_d.errorText(result.error))
                },
                function(error) {
                    _d.claimBusy = false
                    _d.claimSuccess = false
                    _d.claimMessage = qsTr("Claim failed: %1").arg(_d.errorText(error))
                }
            )
        }

    }

    color: Theme.palette.background

    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.ready
        spacing: Theme.spacing.medium
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Connecting to blockchain backend...")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosSpinner { Layout.alignment: Qt.AlignHCenter; running: !root.ready }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: _d.currentPage
        visible: root.ready

        OnboardingFlow {
            id: onboardingFlow
            objectName: "onboardingFlow"
            backend: root.backend
            canExit: root.hasConfig && _d.setupNewNode
            newNode: _d.setupNewNode

            onKeystoreSaved: function(path) {
                keystoreBackupToast.show(qsTr("Keystore saved"), path)
            }
            onExitRequested: root.closeSetup()
            onFinished: function(startNode) {
                root.closeSetup()
                if (startNode && root.backend
                        && root.backend.status !== BlockchainBackend.Running) {
                    root.backend.startBlockchain()
                }
            }
        }

        // Page 2: the node itself — a persistent header (identity, the Fund
        // mining toggle and the start/stop control) over a tab bar, one tab per
        // section.
        Item {
        ColumnLayout {
            id: opPage
            anchors.fill: parent
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.medium

            // Selected section. The tab bar and the StackLayout's children are
            // index-for-index: 0 Dashboard · 1 Explorer · 2 Rewards ·
            // 3 Mining · 4 Wallet · 5 Settings.
            // Reorder one and you must reorder the other.
            //
            // The tab bar owns the selection. Binding its currentIndex to a
            // property here instead would break the moment the user clicked a
            // tab — TabBar assigns currentIndex itself, which destroys the
            // binding and leaves programmatic navigation with nothing to drive.
            readonly property int sectionIndex: sectionTabs.currentIndex

            readonly property bool nodeRunning: root.backend
                ? root.backend.status === BlockchainBackend.Running
                : false

            readonly property string chainId: root.backend && root.backend.chainId
                ? root.backend.chainId
                : ""
            readonly property bool miningActive: root.backend ? root.backend.miningActive : false

            // Sections 2-4 (Rewards, Mining, Wallet) need a running node; if it
            // stops while one is open, fall back to Dashboard so the user isn't
            // stranded on a disabled section. Dashboard, Explorer and Settings
            // stay reachable throughout — the Explorer's block table keeps the
            // blocks this session already saw.
            onNodeRunningChanged: {
                // Whichever way this went, the message belonged to the previous
                // run of the node and no longer describes anything.
                _d.miningError = ""
                // No tab is gated on the node any more: every view states why
                // it cannot answer instead of being unreachable. So a stopping
                // node no longer moves the user off the tab they chose.
            }

            // A node module whose process is gone leaves status frozen at Error,
            // and the only honest offer there is Start: it re-probes, and either
            // the module came back and starts, or it says so again. Stop is the
            // one thing that cannot help, and offering it under a message that
            // reads "start it again" is how the two ended up disagreeing.
            readonly property bool canStart: root.backend
                && !!root.backend.userConfig
                && (root.backend.status === BlockchainBackend.NotStarted
                    || root.backend.status === BlockchainBackend.Stopped
                    || (root.backend.status === BlockchainBackend.Error
                        && !root.moduleReachable))
            // Starting is included deliberately: the start RPC outlives replay
            // and IBD, so a node can sit in Starting for many minutes. Without
            // this there is no way to abort a sync short of killing the app.
            // The backend already permits it (stopBlockchain guards on
            // Running/Starting/Error).
            readonly property bool canStop: root.backend
                && root.moduleReachable
                && (root.backend.status === BlockchainBackend.Running
                    || root.backend.status === BlockchainBackend.Starting
                    || root.backend.status === BlockchainBackend.Error)
            // The one genuinely transient state: the stop is already in flight,
            // so there is nothing to offer until it lands.
            readonly property bool stopping: root.backend
                && root.backend.status === BlockchainBackend.Stopping

            // A stop can legitimately take a while; with a fixed label and a
            // disabled button, slow is indistinguishable from frozen.
            property int stoppingSeconds: 0
            onStoppingChanged: opPage.stoppingSeconds = 0
            Timer {
                interval: 1000
                repeat: true
                running: opPage.stopping
                onTriggered: opPage.stoppingSeconds += 1
            }

            // ---- Header: identity + mining and node controls ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium

                // The Logos mark, not a node glyph. The asset is a 48:66 lambda,
                // so a 30x30 box renders it 22x30 — LogosIcon preserves aspect.
                LogosIcon {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    source: Qt.resolvedUrl("icons/logos.svg")
                    color: Theme.palette.text
                }

                LogosText {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Blockchain Node")
                    color: Theme.palette.text
                    // 28 sits between panelTitleText (24) and titleText (30);
                    // no token matches, and the design measures at 28.
                    font.pixelSize: 28
                    font.weight: Theme.typography.weightBold
                }

                Item { Layout.fillWidth: true }

                // Mining pays PoW rewards into the leader's funding key, which
                // is what PoS stakes from — so this is how a fresh node funds
                // itself. Secondary next to the node control: starting the node
                // is still the primary action on this header.
                // Two explicit buttons rather than one toggle: Start is offered
                // only when it can work (node up and caught up), Stop whenever
                // mining is on, so the CPU can always be given back.
                LogosButton {
                    id: fundMiningButton
                    objectName: "fundMiningButton"
                    text: qsTr("Start Mining")
                    visible: !opPage.miningActive
                    enabled: opPage.nodeRunning && monitor.synced
                    LogosToolTip {
                        text: opPage.nodeRunning && !monitor.synced
                              ? qsTr("Available once the node has caught up")
                              : qsTr("Mining runs until you stop it")
                        placement: LogosToolTip.Placement.Bottom
                        visible: fundMiningButton.hovered
                    }
                    onClicked: _d.startMining()
                }
                LogosButton {
                    id: stopMiningButton
                    objectName: "stopMiningHeaderButton"
                    text: qsTr("Stop Mining")
                    visible: opPage.miningActive
                    enabled: opPage.nodeRunning
                    onClicked: _d.stopMining()
                }

                LogosButton {
                    objectName: "nodeRunButton"
                    variant: LogosButton.Variant.Primary
                    text: opPage.stopping
                          ? (opPage.stoppingSeconds > 0
                             ? qsTr("Stopping… %1s").arg(opPage.stoppingSeconds)
                             : qsTr("Stopping…"))
                          : opPage.canStop ? qsTr("Stop Node")
                          : qsTr("Start Node")
                    enabled: !opPage.stopping && (opPage.canStop || opPage.canStart)
                    onClicked: {
                        if (!root.backend)
                            return
                        if (opPage.canStop) {
                            // Stopped on purpose: do not bring it back on the next load.
                            resumeStore.nodeWanted = false
                            resumeStore.miningWanted = false
                            resume.note = ""
                            root.backend.stopBlockchain()
                            return
                        }
                        if (root.backend.configState === BlockchainBackend.ConfigStale
                                || root.backend.configState === BlockchainBackend.ConfigUnreadable) {
                            configUpgradeDialog.rearm()
                            return
                        }
                        root.backend.startBlockchain()
                    }
                }
            }

            LogosText {
                objectName: "autoResumeNote"
                Layout.fillWidth: true
                visible: resume.note.length > 0
                text: resume.note
                Accessible.name: text
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                wrapMode: Text.WordWrap
            }

            LogosTabBar {
                id: sectionTabs
                objectName: "sectionTabs"
                Layout.fillWidth: true

                // Index-for-index with operationStack's children below.
                LogosTabButton {
                    objectName: "tabNode"
                    text: qsTr("Node")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTabButton {
                    objectName: "tabRewards"
                    text: qsTr("Rewards")
                    font.pixelSize: Theme.typography.secondaryText
                }
                // Ungated: the lookup itself needs a node, but the block table
                // under it does not, and the view says so in place.
                LogosTabButton {
                    objectName: "tabExplorer"
                    text: qsTr("Explorer")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTabButton {
                    objectName: "tabWallet"
                    text: qsTr("Wallet")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTabButton {
                    objectName: "tabMining"
                    text: qsTr("Mining")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTabButton {
                    objectName: "tabSettings"
                    text: qsTr("Settings")
                    font.pixelSize: Theme.typography.secondaryText
                }
            }

            StackLayout {
                id: operationStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: opPage.sectionIndex

                // ---- Section 0: Node ----
                NodeDashboardView {
                    status: root.backend ? root.backend.status : -1
                    connected: root.ready && root.backend !== null
                    moduleReachable: root.moduleReachable
                    everConnected: root.everReady
                    statusMessage: monitor.error
                                   || (root.backend ? root.backend.lastErrorMessage : "")
                    nodeRecovering: !!root.backend && root.backend.nodeRecovering
                    infoJson: monitor.infoJson
                    timeInfoJson: monitor.timeInfoJson
                    vouchersJson: root.claimableVouchersJson
                    stakeTotal: root.backend ? root.backend.stakeTotal : ""
                    stakeNoteCount: root.backend ? root.backend.stakeNoteCount : 0
                    earnedTotal: root.backend ? root.backend.earnedTotal : ""
                    earnedClaimCount: root.backend ? root.backend.earnedClaimCount : 0
                    claimsCountingSince: root.backend ? root.backend.claimsCountingSince : ""
                    earnedClaimsSubmitted: root.backend ? root.backend.earnedClaimsSubmitted : 0
                    earnedClaimsPending: root.backend ? root.backend.earnedClaimsPending : 0
                    walletFunded: !!root.backend && root.backend.walletFunded
                    stakeAddresses: root.backend ? root.backend.stakeAddresses : []
                    peerId: root.peerId
                    peerCount: root.backend ? root.backend.peerCount : -1
                    connectionCount: root.backend ? root.backend.connectionCount : -1
                    nodeCpuPercent: root.backend ? root.backend.nodeCpuPercent : -1
                    nodeMemoryMb: root.backend ? root.backend.nodeMemoryMb : -1
                    cpuCount: root.backend ? root.backend.cpuCount : 1
                    nodeDiskUsedMb: root.backend ? root.backend.nodeDiskUsedMb : -1
                    nodeDiskFreeMb: root.backend ? root.backend.nodeDiskFreeMb : -1
                    blendRole: root.backend ? root.backend.blendRole
                                            : BlockchainBackend.Unknown
                    synced: monitor.synced
                    hasBeenOnline: monitor.hasBeenOnline
                    statusStale: monitor.stale
                    statusNextPollSeconds: monitor.nextPollSeconds
                    statusSilentSeconds: monitor.silentSeconds
                    syncStalled: monitor.stalled
                    blockStreamEnded: monitor.streamEnded
                    genesisPending: monitor.genesisPending
                    genesisUnixMs: monitor.genesisUnixMs
                    uptimeSeconds: (root.backend && root.backend.uptimeSeconds !== undefined)
                                   ? root.backend.uptimeSeconds : 0
                    miningActive: opPage.miningActive
                    miningError: _d.miningError
                    powRewardsClaimed: root.backend ? root.backend.powRewardsClaimed : 0
                    powRewardsLepta: root.backend ? root.backend.powRewardsLepta : ""
                    powClaimsSubmitted: root.backend ? root.backend.powClaimsSubmitted : 0
                    powClaimsPending: root.backend ? root.backend.powClaimsPending : 0
                    claimableTickets: root.backend ? root.backend.claimableTickets : 0
                    powActive: root.backend ? root.backend.powActive : false
                    keystorePresent: !!root.backend && root.backend.nodeKeystorePath.length > 0
                    keysBackedUp: !!root.backend && root.backend.keysBackedUp
                }

                // ---- Section 1: Rewards ----
                LeaderRewardsView {
                    id: leaderRewardsView
                    nodeOffSeverity: root.nodeOffSeverity
                    vouchersJson: root.claimableVouchersJson
                    submittedCount: root.backend ? root.backend.earnedClaimsSubmitted : 0
                    pendingCount: root.backend ? root.backend.earnedClaimsPending : 0
                    claimsModel: root.claimsModel
                    nodeOffReason: root.nodeOffReason
                    timeInfoJson: monitor.timeInfoJson

                    onClaimLeaderRewardsRequested: function() {
                        if (!root.backend) {
                            leaderRewardsView.setLeaderClaimError(qsTr("Backend not connected."))
                            return
                        }
                        logos.watch(
                            root.backend.claimLeaderRewards(),
                            function(result) {
                                if (result.success) {
                                    leaderRewardsView.setLeaderClaimResult(result.value, true)
                                } else {
                                    leaderRewardsView.setLeaderClaimError(result.error)
                                }
                                root.refreshClaimableVouchers()
                            },
                            function(error) {
                                leaderRewardsView.setLeaderClaimError(error)
                            }
                        )
                    }
                    onCopyToClipboard: (text) => {
                        root.copyText(text)
                    }
                    onHistoryPendingOnlyChanged: function(pendingOnly) {
                        if (root.backend)
                            root.backend.setClaimHistoryFilter(pendingOnly ? 1 : 0)
                    }
                    // Section 2 is the Explorer — keep in step with the tab bar.
                    onOpenInExplorerRequested: function(id) {
                        if (!id || id.length === 0)
                            return
                        sectionTabs.currentIndex = 2
                        explorerView.searchFor(id)
                    }
                }

                // ---- Section 2: Explorer (lookup + the blocks this node saw) ----
                ExplorerView {
                    id: explorerView
                    nodeOffSeverity: root.nodeOffSeverity
                    nodeOffReason: root.nodeOffReason
                    nodeRunning: opPage.nodeRunning
                    nodeReportedState: monitor.infoJson.length > 0
                    blockModel: root.blockModel

                    onSearchRequested: function(id) {
                        const fail = function(why) { explorerView.setError(id, why) }
                        if (!root.backend) {
                            fail(qsTr("Not connected to the blockchain module."))
                            return
                        }

                        function step(call, onValue) {
                            try {
                                logos.watch(call(), onValue,
                                            function(e) { fail(_d.errorText(e)) })
                            } catch (e) {
                                fail(qsTr("Lookup failed: %1").arg(e.message || e))
                            }
                        }

                        step(function() { return root.backend.findTransactionInBlocks(id) },
                             function(local) {
                            if (local.success) {
                                explorerView.setTransactionResult(
                                    id, local.value, local.slot, local.blockId)
                                return
                            }
                            step(function() { return root.backend.getBlock(id) },
                                 function(blockResult) {
                                if (blockResult.success) {
                                    explorerView.setBlockResult(id, blockResult.value)
                                    return
                                }
                                step(function() { return root.backend.getTransaction(id) },
                                     function(txResult) {
                                    if (txResult.success)
                                        explorerView.setTransactionResult(id, txResult.value)
                                    else
                                        explorerView.setNotFound(id)
                                })
                            })
                        })
                    }
                    onCopyToClipboard: (text) => root.copyText(text)
                }

                // ---- Section 3: Wallet ----
                WalletView {
                    id: walletView
                    nodeOffSeverity: root.nodeOffSeverity
                    nodeOffReason: root.nodeOffReason
                    accountsModel: root.accountsModel
                    accountRows: root.backend ? root.backend.accountRows : []
                    nodeRunning: opPage.nodeRunning
                    lezChannelId: root.backend ? root.backend.lezChannelId : ""
                    // The key folder (config folder), not the chain db.
                    nodeDataDir: root.configFolder
                    chain: chainReader
                    lezSupported: _d.lezSupported
                    lezAccount: _d.lez
                    lezBalance: _d.lezBalance
                    lezError: _d.lezError
                    lezBusy: _d.lezBusy
                    onLezCreateRequested: _d.createLez()
                    onLezRefreshRequested: _d.refreshLez()

                    onRefreshAccountsRequested: if (root.backend) root.backend.refreshAccounts()

                    onTransferRequested: function(fromKeyHex, toKeyHex, amount) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.transferFunds(fromKeyHex, toKeyHex, amount),
                            function(result) {
                                if (result.success) {
                                    walletView.setTransferHash(result.value)
                                } else {
                                    walletView.setTransferError(_d.errorText(result.error))
                                }
                            },
                            function(error) { walletView.setTransferError(_d.errorText(error)) }
                        )
                    }

                    onGasPricesRequested: function(target) {
                        if (!root.backend) return
                        logos.watch(root.backend.getGasPrices(),
                            function(result) {
                                if (result.success) walletView.setGasPrices(target, true, result.value)
                                else walletView.setGasPrices(target, false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setGasPrices(target, false, _d.errorText(error)) })
                    }
                    onLezNotesRequested: function(addressHex) {
                        if (!root.backend) return
                        logos.watch(root.backend.getNotes(addressHex, ""),
                            function(result) {
                                if (result.success) walletView.setLezNotes(true, result.value)
                                else walletView.setLezNotes(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setLezNotes(false, _d.errorText(error)) })
                    }
                    onLezSplitRequested: function(fromKeyHex, amountTokens) {
                        if (!root.backend) return
                        // A transfer to the same account: its output is the exact note.
                        logos.watch(root.backend.transferFunds(fromKeyHex, fromKeyHex, amountTokens),
                            function(result) {
                                if (result.success) walletView.setLezSplitResult(true, result.value)
                                else walletView.setLezSplitResult(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setLezSplitResult(false, _d.errorText(error)) })
                    }
                    onLezDepositRequested: function(channelIdHex, inputNoteIdHexes, metadataBase58, changePublicKeyHex, fundingPublicKeyHexes, maxTxFeeTokens) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.channelDepositWithNotes(
                                channelIdHex, inputNoteIdHexes, metadataBase58,
                                changePublicKeyHex, fundingPublicKeyHexes, maxTxFeeTokens, ""),
                            function(result) {
                                if (result.success) walletView.setLezDepositResult(true, result.value)
                                else walletView.setLezDepositResult(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setLezDepositResult(false, _d.errorText(error)) })
                    }

                    onGetNotesRequested: function(addressHex, optionalTipHex) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.getNotes(addressHex, optionalTipHex),
                            function(result) {
                                if (result.success)
                                    walletView.setNotes(result.value)
                                else
                                    walletView.setNotesError(_d.errorText(result.error))
                            },
                            function(error) { walletView.setNotesError(_d.errorText(error)) }
                        )
                    }
                    onSubmitRequested: function(channelIdHex, inputNoteIdHexes, metadataBase58, changePublicKeyHex, fundingPublicKeyHexes, maxTxFee, optionalTipHex) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.channelDepositWithNotes(
                                channelIdHex, inputNoteIdHexes, metadataBase58,
                                changePublicKeyHex, fundingPublicKeyHexes, maxTxFee, optionalTipHex),
                            function(result) {
                                if (result.success)
                                    walletView.setSubmitResult(true, result.value)
                                else
                                    walletView.setSubmitResult(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setSubmitResult(false, _d.errorText(error)) }
                        )
                    }


                    onInscribeEstimateRequested: function(requestJson) {
                        if (!root.backend) return
                        logos.watch(root.backend.channelInscribe(requestJson),
                            function(result) {
                                if (result.success) walletView.setInscribePreview(true, result.value)
                                else walletView.setInscribePreview(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setInscribePreview(false, _d.errorText(error)) })
                    }
                    onInscribeSubmitRequested: function(requestJson) {
                        if (!root.backend) return
                        logos.watch(root.backend.channelInscribe(requestJson),
                            function(result) {
                                if (result.success) walletView.setInscribeResult(true, result.value)
                                else walletView.setInscribeResult(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setInscribeResult(false, _d.errorText(error)) })
                    }
                    onWithdrawEstimateRequested: function(requestJson) {
                        if (!root.backend) return
                        logos.watch(root.backend.channelWithdraw(requestJson),
                            function(result) {
                                if (result.success) walletView.setWithdrawPreview(true, result.value)
                                else walletView.setWithdrawPreview(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setWithdrawPreview(false, _d.errorText(error)) })
                    }
                    onWithdrawSubmitRequested: function(requestJson) {
                        if (!root.backend) return
                        logos.watch(root.backend.channelWithdraw(requestJson),
                            function(result) {
                                if (result.success) walletView.setWithdrawResult(true, result.value)
                                else walletView.setWithdrawResult(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setWithdrawResult(false, _d.errorText(error)) })
                    }
                    onChannelKeygenRequested: function(keyPath) {
                        if (!root.backend) return
                        logos.watch(root.backend.channelKeygen(keyPath),
                            function(result) {
                                if (result.success) walletView.setChannelIdent(true, result.value)
                                else walletView.setChannelIdent(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setChannelIdent(false, _d.errorText(error)) })
                    }
                    onChannelIdentRequested: function(keyPath) {
                        if (!root.backend) return
                        logos.watch(root.backend.channelKeyIdent(keyPath),
                            function(result) {
                                if (result.success) walletView.setChannelIdent(true, result.value)
                                else walletView.setChannelIdent(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setChannelIdent(false, _d.errorText(error)) })
                    }
                    onSdpStatusRequested: function(kind, serviceType) {
                        if (!root.backend) return
                        var call = kind === "snapshot" ? root.backend.sdpGetSnapshot()
                                 : kind === "finalized" ? root.backend.sdpGetFinalizedDeclarations(serviceType)
                                 : root.backend.sdpGetDeclarations()
                        logos.watch(call,
                            function(result) {
                                if (result.success) walletView.setSdpStatus(true, result.value)
                                else walletView.setSdpStatus(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setSdpStatus(false, _d.errorText(error)) })
                    }
                    onSdpPreviewRequested: function(kind, requestJson) {
                        if (!root.backend) return
                        var call = kind === "activity" ? root.backend.sdpPostActivity(requestJson)
                                 : kind === "withdrawal" ? root.backend.sdpPostWithdrawal(requestJson)
                                 : root.backend.sdpPostDeclaration(requestJson)
                        logos.watch(call,
                            function(result) {
                                if (result.success) walletView.setSdpPreview(true, result.value)
                                else walletView.setSdpPreview(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setSdpPreview(false, _d.errorText(error)) })
                    }
                    onSdpSubmitRequested: function(kind, requestJson) {
                        if (!root.backend) return
                        var call = kind === "activity" ? root.backend.sdpPostActivity(requestJson)
                                 : kind === "withdrawal" ? root.backend.sdpPostWithdrawal(requestJson)
                                 : root.backend.sdpPostDeclaration(requestJson)
                        logos.watch(call,
                            function(result) {
                                if (result.success) walletView.setSdpResult(true, result.value)
                                else walletView.setSdpResult(false, _d.errorText(result.error))
                            },
                            function(error) { walletView.setSdpResult(false, _d.errorText(error)) })
                    }

                    onCopyToClipboard: (text) => root.copyText(text)
                }

                // ---- Section 4: Mining (PoW tickets and claiming) ----
                MiningView {
                    id: miningView
                    nodeOffSeverity: root.nodeOffSeverity
                    nodeRunning: opPage.nodeRunning
                    submittedCount: root.backend ? root.backend.powClaimsSubmitted : 0
                    pendingCount: root.backend ? root.backend.powClaimsPending : 0
                    powRewardsLepta: root.backend ? root.backend.powRewardsLepta : ""
                    claimsModel: root.miningClaimsModel
                    nodeOffReason: root.nodeOffReason
                    timeInfoJson: monitor.timeInfoJson
                    accounts: root.backend ? root.backend.accountRows : []

                    claimableTickets: root.backend ? root.backend.claimableTickets : 0
                    soonestExpirySlots: root.backend ? root.backend.soonestExpirySlots : -1
                    soonestExpiryCount: root.backend ? root.backend.soonestExpiryCount : 0
                    claimableLoaded: root.backend ? root.backend.claimableLoaded : false
                    claimableError: root.backend ? root.backend.claimableError : ""

                    miningActive: opPage.miningActive
                    chainOnline: monitor.modeOnline
                    powStatusKnown: root.backend ? root.backend.powStatusKnown : false
                    powRewardsEnabled: root.backend ? root.backend.powRewardsEnabled : false
                    autoClaimArmed: root.backend ? root.backend.autoClaimArmed : false
                    autoClaimSelfDisarmed: root.backend ? root.backend.autoClaimSelfDisarmed : false
                    autoClaimTick: root.backend ? root.backend.autoClaimTick : 0
                    autoClaimTickUnit: root.backend ? root.backend.autoClaimTickUnit : ""
                    claimTargets: root.backend ? root.backend.powClaimTargets : []

                    claimBusy: _d.claimBusy
                    claimSuccess: _d.claimSuccess
                    claimMessage: _d.claimMessage

                    synced: monitor.synced
                    cpuCount: root.backend ? root.backend.cpuCount : 1
                    currentThreads: _d.currentThreads
                    threadsBusy: _d.threadsBusy
                    threadsOk: _d.threadsOk
                    threadsMessage: _d.threadsMessage
                    restartOffered: _d.restartOffered
                    miningError: _d.miningError
                    onStartMiningRequested: _d.startMining()
                    onStopMiningRequested: _d.stopMining()
                    onApplyThreadsRequested: function(threads) { _d.applyThreads(threads) }
                    onRestartNodeRequested: _d.restartNode()
                    Component.onCompleted: _d.loadPowConfig()

                    onClaimRequested: function(addressHex) { _d.claimPowRewards(addressHex) }
                    onAutoClaimToggled: function(enabled) { _d.setAutoClaim(enabled) }
                    onHistoryPendingOnlyChanged: function(pendingOnly) {
                        if (root.backend)
                            root.backend.setMiningHistoryFilter(pendingOnly ? 1 : 0)
                    }
                    onOpenInExplorerRequested: function(id) {
                        if (!id || id.length === 0)
                            return
                        sectionTabs.currentIndex = 2
                        explorerView.searchFor(id)
                    }
                }

                // ---- Section 5: Settings ----
                // Wrapped rather than made scrollable internally: three cards do
                // not fit a short window, and the Destructive card is last —
                // a page that cut off at the bottom would hide exactly what the
                // user came for when the node is wedged.
                LogosScrollView {
                    id: settingsScroll

                    NodeSettingsView {
                        id: nodeSettingsView
                        objectName: "nodeSettingsView"
                        width: settingsScroll.availableWidth
                        userConfig: root.backend ? root.backend.userConfig : ""
                        deploymentConfig: root.backend ? root.backend.deploymentConfig : ""
                        useGeneratedConfig: root.backend ? root.backend.useGeneratedConfig : false
                        canChange: !opPage.canStop
                        nodeRunning: root.nodeRunning
                        nodeDataDir: root.backend ? root.backend.nodeDataDir : ""
                        nodeKeystorePath: root.backend ? root.backend.nodeKeystorePath : ""
                        onBackupKeystoreRequested: function(destinationPath) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.backupKeystore(destinationPath),
                            function(result) {
                                if (result.success) {
                                    nodeSettingsView.backupError = ""
                                    keystoreBackupToast.show(
                                        qsTr("Keystore saved"), result.value)
                                } else {
                                    nodeSettingsView.backupError = _d.errorText(result.error)
                                }
                            },
                            function(error) {
                                nodeSettingsView.backupError = _d.errorText(error)
                            }
                        )
                    }
                    keysBackedUp:!!root.backend && root.backend.keysBackedUp
                    configChangedSinceStart: _d.configChangedSinceStart
                    onUserConfigSelected: function(path) {
                        if (!root.backend || path.length === 0)
                            return
                        root.backend.userConfig = path
                        root.backend.useGeneratedConfig = false
                    }
                    onDeploymentConfigSelected: function(path) {
                        if (!root.backend)
                            return
                        root.backend.deploymentConfig = path
                    }
                    configDir: root.configFolder
                    resetBusy: _d.resetBusy
                    resetMessage: _d.resetMessage
                    resetOk: _d.resetOk
                    onResetDatabaseRequested: _d.resetDatabase()
                    lezAccountExists: !!_d.lez && _d.lez.exists === true
                    lezAccountPath: (_d.lez && _d.lez.path) ? _d.lez.path : ""
                    lezBackedUp: !!_d.lez && _d.lez.backed_up === true
                    onBackupLezAccountRequested: function(dest) { _d.backupLez(dest) }
                    onStartNewNodeRequested: root.openSetup(true)
                    autoResume: resumeStore.enabled
                    onAutoResumeToggled: function(on) { resumeStore.enabled = on }
                    }
                }
            }

            // ---- Footer: which chain everything above belongs to ----------
            RowLayout {
                id: chainFooter

                Layout.fillWidth: true
                spacing: Theme.spacing.tiny
                visible: opPage.chainId.length > 0

                LogosText {
                    objectName: "chainIdFooter"
                    Layout.maximumWidth: root.width * 0.6
                    text: qsTr("Chain ID: %1").arg(opPage.chainId)
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideRight
                }

                LogosCopyButton {
                    value: opPage.chainId
                    size: 16
                }

                Item { Layout.fillWidth: true }
            }
        }
        }
    }

}
