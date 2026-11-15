import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import Logos.Theme
import Logos.Controls

import "../controls"
import "infoContent.js" as InfoContent
import "OnboardingPaths.js" as OnboardingPaths

// Node settings, one card per concern.
ColumnLayout {
    id: root

    // --- Public API ---
    property string userConfig: ""
    property string deploymentConfig: ""
    property bool useGeneratedConfig: false
    // The chooser is not reachable while the node is up: changing config under
    // a running node would leave the two disagreeing.
    property bool canChange: true
    property bool nodeRunning: false

    // A config was repointed and the node has not been started since. Changing
    // a path takes effect immediately but does nothing visible until the node
    // runs, so without this the user acts and is told nothing.
    property bool configChangedSinceStart: false
    // Where the node keeps db/, state/ and logs/. Empty when no config is set
    // or the node has not run yet.
    property string nodeDataDir: ""
    // The keystore, or empty when there is none for this config yet.
    property string nodeKeystorePath: ""
    property bool keysBackedUp: false
    // Why the last backup failed, or empty. Successes are announced by the
    // host as a toast rather than kept here.
    property string backupError: ""
    onBackupErrorChanged: backupResultNotice.shown = root.backupError.length > 0
    // Full path of the last verified copy (keystore or LEZ key), or empty.
    property string backupSavedPath: ""
    property bool backupBusy: false

    signal backupKeystoreRequested(string destinationPath)
    // ---- windows.13 ----
    // The config's folder (holds keystore.yaml and user_config.yaml).
    property string configDir: ""
    property bool resetBusy: false
    property string resetMessage: ""
    property bool resetOk: false
    signal resetDatabaseRequested()
    // Built-in LEZ account file, if any.
    property bool lezAccountExists: false
    property string lezAccountPath: ""
    property bool lezBackedUp: false
    signal backupLezAccountRequested(string destinationPath)
    signal userConfigSelected(string path)
    signal deploymentConfigSelected(string path)

    spacing: Theme.spacing.large

    signal startNewNodeRequested()

    // Auto-resume after a Basecamp/UI restart or update (yayguru Windows build).
    property bool autoResume: true
    signal autoResumeToggled(bool on)

    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: RowLayout {
            spacing: Theme.spacing.medium
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.tiny
                LogosText {
                    Accessible.name: text
                    text: qsTr("Resume after restart")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }
                LogosText {
                    Accessible.name: text
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                    text: root.autoResume
                          ? qsTr("On: updating or reinstalling this app does not stop the node — it keeps running and mining. If Basecamp restarts or the blockchain module is reinstalled, the node starts again with the same config and mining resumes once synced. Stop Node and Stop Mining are always respected.")
                          : qsTr("Off: closing or updating this app stops the node, and it stays stopped until you press Start Node.")
                }
            }
            LogosSwitch {
                objectName: "autoResumeSwitch"
                checked: root.autoResume
                Accessible.name: qsTr("Resume node and mining after restart")
                onToggled: root.autoResumeToggled(checked)
            }
        }
    }


    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.bottomMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                LogosText {
                    Accessible.name: text
                    text: qsTr("Node")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                LogosInfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    title: qsTr("Node config")
                    dialogContentItem: InfoSections { info: InfoContent.nodeConfig }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosText {
                    Accessible.name: text
                    text: qsTr("User Config")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                // Copies the full path, not the elided display string.
                LogosCopyButton {
                    visible: root.userConfig.length > 0
                    value: root.userConfig
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosTextField {
                    id: userConfigField
                    objectName: "settingsUserConfigField"
                    Layout.fillWidth: true
                    enabled: root.canChange
                    placeholderText: qsTr("No file selected")
                    text: root.userConfig
                }

                Connections {
                    target: userConfigField.textInput
                    function onEditingFinished() {
                        root.userConfigSelected(userConfigField.text.trim())
                    }
                }

                LogosButton {
                    objectName: "settingsBrowseUserConfigButton"
                    enabled: root.canChange
                    text: qsTr("Browse")
                    onClicked: userConfigFileDialog.open()
                }
            }

            LogosText {
                Accessible.name: text
                Layout.fillWidth: true
                visible: root.useGeneratedConfig
                text: qsTr("Generated by this app.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            RowLayout {
                Layout.topMargin: Theme.spacing.small
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosText {
                    Accessible.name: text
                    text: qsTr("Deployment Config")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                LogosCopyButton {
                    visible: root.deploymentConfig.length > 0
                    value: root.deploymentConfig
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosTextField {
                    id: deploymentField
                    objectName: "settingsDeploymentConfigField"
                    Layout.fillWidth: true
                    enabled: root.canChange
                    placeholderText: qsTr("Built-in default")
                    text: root.deploymentConfig
                }

                Connections {
                    target: deploymentField.textInput
                    function onEditingFinished() {
                        root.deploymentConfigSelected(deploymentField.text.trim())
                    }
                }

                LogosButton {
                    objectName: "settingsBrowseDeploymentButton"
                    enabled: root.canChange
                    text: qsTr("Browse")
                    onClicked: deploymentConfigFileDialog.open()
                }
            }

            // The fallback is silent otherwise, and it is not harmless: an
            // uninscribed built-in deployment is what produces a genesis far in
            // the future and a chain id the node cannot report.
            LogosText {
                Accessible.name: text
                Layout.fillWidth: true
                visible: root.deploymentConfig.length === 0
                wrapMode: Text.WordWrap
                text: qsTr("Using the deployment built into this build.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosNotice {
                objectName: "configChangedNotice"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                shown: root.configChangedSinceStart && !root.nodeRunning
                severity: LogosNotice.Info
                message: qsTr("Config changed. Start the node to use it.")
            }

            RowLayout {
                Layout.topMargin: Theme.spacing.medium
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing.small

                LogosButton {
                    objectName: "startNewNodeButton"
                    enabled: root.canChange
                    text: qsTr("Start a new node")
                    onClicked: root.startNewNodeRequested()
                }
            }
        }
    }

    // ---- Back up your keys ----
    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                LogosText {
                    Accessible.name: text
                    text: qsTr("Back up your keys")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }

                LogosBadge {
                    objectName: "keysBackedUpBadge"
                    visible: root.keysBackedUp
                    text: qsTr("Done")
                    color: Theme.palette.success
                }

                Item { Layout.fillWidth: true }
            }

            LogosText {
                Accessible.name: text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Your keystore holds the keys to your accounts. It is the one file "
                           + "nothing else can replace — lose it and the rewards those accounts "
                           + "hold are gone with it. Save a copy somewhere safe, away from this "
                           + "machine, and you can recover the accounts even if everything here "
                           + "is lost.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            HashRow {
                Layout.fillHeight: false
                visible: root.nodeKeystorePath.length > 0
                label: qsTr("Keystore")
                labelWidth: 72
                value: root.nodeKeystorePath
            }

            LogosText {
                Accessible.name: text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.nodeKeystorePath.length === 0
                text: qsTr("No keystore found yet — it appears once a config is set and the "
                           + "node has run at least once.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosText {
                Accessible.name: text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.nodeKeystorePath.length > 0
                text: qsTr("One click saves a verified copy named keystore-backup-<date>.yaml to "
                           + "Documents\\LogosBackups. Or choose a folder — a USB stick or a "
                           + "cloud-synced folder is best. Then keep that file safe.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                spacing: Theme.spacing.small
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "backupKeystoreFolderButton"
                    Accessible.name: text
                    enabled: root.nodeKeystorePath.length > 0 && !root.backupBusy
                    text: qsTr("Choose folder…")
                    onClicked: { keystoreFolderDialog.target = "keystore"; keystoreFolderDialog.open() }
                }
                LogosButton {
                    objectName: "backupKeystoreButton"
                    Accessible.name: text
                    variant: LogosButton.Variant.Primary
                    enabled: root.nodeKeystorePath.length > 0 && !root.backupBusy
                    text: qsTr("Save backup to Documents")
                    onClicked: root.backupKeystoreRequested("")
                }
            }

            LogosText {
                objectName: "backupSavedPathText"
                Accessible.name: text
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                visible: root.backupSavedPath.length > 0
                text: qsTr("Saved and verified (same size and SHA-256 as the original): %1")
                      .arg(root.backupSavedPath)
                color: Theme.palette.success
                font.pixelSize: Theme.typography.secondaryText
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.lezAccountExists
                spacing: Theme.spacing.small
                LogosText {
                    Accessible.name: text
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.lezBackedUp
                          ? qsTr("LEZ account key (lez_account.json) — backed up.")
                          : qsTr("Your built-in LEZ account has its own key, lez_account.json, beside the keystore. Back it up too.")
                    font.pixelSize: Theme.typography.secondaryText
                    color: root.lezBackedUp ? Theme.palette.textSecondary : Theme.palette.warning
                }
                LogosButton {
                    objectName: "backupLezAccountFolderButton"
                    Accessible.name: text
                    enabled: !root.backupBusy
                    text: qsTr("Choose folder…")
                    onClicked: { keystoreFolderDialog.target = "lez"; keystoreFolderDialog.open() }
                }
                LogosButton {
                    objectName: "backupLezAccountButton"
                    Accessible.name: text
                    enabled: !root.backupBusy
                    text: qsTr("Save LEZ key to Documents")
                    onClicked: root.backupLezAccountRequested("")
                }
            }

            LogosNotice {
                id: backupResultNotice
                Layout.fillWidth: true
                objectName: "backupResultNotice"
                shown: false
                severity: LogosNotice.Error
                title: qsTr("Backup failed")
                message: root.backupError
                closable: true
                onDismissed: root.backupError = ""
                actions: [
                    LogosCopyButton { value: root.backupError }
                ]
            }
        }
    }

    // ---- Destructive ----
    // Deletes the chain database only. The path shown is the db folder itself,
    // never the config folder that also holds the keys.
    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: Theme.palette.error
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            LogosText {
                Accessible.name: text
                Layout.bottomMargin: Theme.spacing.small
                text: qsTr("Reset the database")
                color: Theme.palette.text
                font.pixelSize: Theme.typography.panelTitleText
                font.weight: Theme.typography.weightMedium
            }

            LogosText {
                Accessible.name: text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("If the node is stuck or will not start, its chain database may be at fault. "
                           + "Resetting deletes only the database folder below; the node then re-syncs "
                           + "the chain from its peers, which can take hours.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosNotice {
                Layout.fillWidth: true
                objectName: "resetKeysWarning"
                shown: true
                severity: LogosNotice.Warning
                title: qsTr("Back up keystore.yaml first")
                message: qsTr("Your keys live in keystore.yaml in the config folder%1. Save a copy with "
                              + "\"Download keystore.yaml\" above before any reset. Never delete the config "
                              + "folder itself — only the database folder shown here.")
                         .arg(root.configDir.length ? " (" + root.configDir + ")" : "")
            }

            HashRow {
                Layout.fillHeight: false
                visible: root.nodeDataDir.length > 0
                label: qsTr("Database")
                labelWidth: 72
                value: root.nodeDataDir
            }

            LogosText {
                Accessible.name: text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.nodeDataDir.length === 0
                text: qsTr("No chain database found for this config yet — it appears once the node has run.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                spacing: Theme.spacing.small
                LogosSwitch {
                    id: resetConfirm
                    objectName: "resetConfirmSwitch"
                    enabled: root.nodeDataDir.length > 0 && !root.nodeRunning
                }
                LogosText {
                    Accessible.name: text
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.nodeRunning
                          ? qsTr("Stop the node to reset its database.")
                          : qsTr("I have backed up keystore.yaml. Delete the chain database (keys and config are kept).")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                LogosButton {
                    objectName: "resetDatabaseButton"
                    text: root.resetBusy ? qsTr("Resetting…") : qsTr("Reset database")
                    enabled: resetConfirm.checked && !root.nodeRunning && !root.resetBusy
                             && root.nodeDataDir.length > 0
                    onClicked: {
                        resetConfirm.checked = false
                        root.resetDatabaseRequested()
                    }
                }
            }

            LogosText {
                Accessible.name: text
                objectName: "resetResultText"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.resetMessage.length > 0
                text: root.resetMessage
                font.pixelSize: Theme.typography.secondaryText
                color: root.resetOk ? Theme.palette.success : Theme.palette.error
            }
        }
    }


    // A folder, not a file name: the name is ours (keystore-backup-<date>.yaml),
    // so there is nothing for the user to type. selectedFolder is a URL
    // (file:///C:/...); the backend turns it into a local path.
    FolderDialog {
        id: keystoreFolderDialog
        property string target: "keystore"
        title: target === "lez" ? qsTr("Choose a folder for the LEZ key backup")
                                : qsTr("Choose a folder for the keystore backup")
        modality: Qt.NonModal
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: {
            const folder = String(selectedFolder)
            if (target === "lez")
                root.backupLezAccountRequested(folder)
            else
                root.backupKeystoreRequested(folder)
        }
    }


    FileDialog {
        id: userConfigFileDialog
        modality: Qt.NonModal
        title: qsTr("Select your user config")
        nameFilters: [qsTr("YAML files (*.yaml *.yml)"), qsTr("All files (*)")]
        currentFolder: OnboardingPaths.toFolderUrl(root.userConfig)
                       || StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: root.userConfigSelected(OnboardingPaths.toLocalPath(selectedFile))
    }

    FileDialog {
        id: deploymentConfigFileDialog
        modality: Qt.NonModal
        title: qsTr("Select your deployment config")
        nameFilters: [qsTr("YAML files (*.yaml *.yml)"), qsTr("All files (*)")]
        currentFolder: OnboardingPaths.toFolderUrl(root.deploymentConfig)
                       || StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: root.deploymentConfigSelected(OnboardingPaths.toLocalPath(selectedFile))
    }
}
