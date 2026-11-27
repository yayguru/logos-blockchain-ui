# Logos Blockchain node on Windows (Basecamp) — user guide

**What it is:** an unofficial Windows build of the Logos Blockchain testnet node, packaged as two
plugins for **Logos Basecamp**. The node runs inside Basecamp: no WSL, no admin rights, no terminal.
You get the node, PoW mining, a wallet (transfer, LEZ bridge, inscriptions) and a block explorer.

> Unofficial builds, not official Logos releases.
> **Do not install the "blockchain" node from Basecamp's official catalog on Windows** — it has no
> Windows version and fails with *"Package does not contain variant for platform windows-x86_64"*.
> Always use the two files below.

## 1. Download (two files)

| What | File to download | Where |
|---|---|---|
| Node (module) | `blockchain_module-0.3.4-windows-x86_64.lgx` | newest `v0.3.4-windows.N` on [module releases](https://github.com/yayguru/logos-blockchain-module/releases) |
| App (UI) | `blockchain_ui-0.3.5-windows-x86_64.lgx` | newest `v0.3.5-windows.N` on [UI releases](https://github.com/yayguru/logos-blockchain-ui/releases) |

Each UI release says which module it needs. You also need **Logos Basecamp 0.4.0-rc.2** for Windows
(`basecamp-setup.exe`, installs per user to `%LOCALAPPDATA%\Programs\LogosBasecamp`).
Optional: check a download against the release's `SHA256SUMS`:

```powershell
Get-FileHash .\blockchain_ui-0.3.5-windows-x86_64.lgx -Algorithm SHA256
```

Needs about 3 GB of disk for the chain and about 1–1.3 GB of RAM while running.

**Shortcut:** `LogosBlockchain-installer-windows.zip` (on the newest UI release) does all of
section 2 for you — see [One-click installer](#one-click-installer).

## 2. Install in Basecamp (module first, then UI)

1. Put each `.lgx` in its **own new empty folder** (the file names never change between versions,
   so this stops the file dialog from picking an old copy).
2. Basecamp → **Package Manager → Install Local Package** → pick the **module** `.lgx` → **Install**.
3. Same again for the **UI** `.lgx`.
4. Basecamp warns *"signed by a publisher you don't trust yet"*. That is expected: the files are signed with
   the maintainer's own key (shown as "yayguru"), not by Logos. Press **Install** (or **Reinstall**). You do **not** need **Trust**.
5. If Windows Firewall asks about `logos_host.exe`, Cancel is fine; outgoing connections still work.

## 3. First start

Open **Blockchain** in Basecamp.

* **You already ran a node before (LogosMiner / CLI):** choose **Use an existing config** and pick your
  existing `user_config.yaml` (for example `C:\LogosMiner\data\user_config.yaml`). The `keystore.yaml`
  and `state\` next to it are reused: **same keys, same balance, no new sync.**
* **Brand-new user:** choose **Start a new node**. It creates new keys and a config in a folder you pick,
  then syncs the chain (takes a while). Never do this on a PC that already has a node — you would get a
  second identity and a second copy of the chain.

Press **Start Node**. The header goes *Starting → Bootstrapping → Online*. After a restart the node can
stay in *Bootstrapping* for up to an hour (the network's normal waiting period); that is not an error.

## 4. Back up your keys (do this first)

`keystore.yaml` is the only thing that cannot be replaced. Lose it and the coins on those keys are gone.

**Settings → Back up your keys → Save keystore backup.** The folder field is already filled with
`Documents\LogosBackups`, so one click is enough. The app writes `keystore-backup-YYYYMMDD.yaml` there,
reads it back and checks it is byte-identical to the original (size + SHA-256), then shows the full path
and a **Show in folder** button. You never type a file name.
To save somewhere else (a USB stick or a cloud-synced folder is best), open that folder in Explorer, click
the address bar, copy the path, paste it into the field and press **Save keystore backup** again.
The folder is created if it does not exist. The red *"Back up your keys"* banner on the Node tab disappears
after a verified backup.
If you created the built-in LEZ account, press **Save LEZ key backup** too (same folder, `lez-account-backup-YYYYMMDD.json`).
Never share these files with anyone.

## 5. Mining

* **Start mining / Stop mining** — header button or the **Mining** tab.
* **Threads:** Mining tab → −/+ → **Apply**. Applies to the running node immediately (module windows.5+)
  and is saved to `user_config.yaml`.
* Mining needs the node to be *Online*. Auto-claim collects mined PoW tickets for you; the Mining tab
  shows how many are ready.

## 6. Stake, in plain words

* There is **no separate staking wallet and nothing to "stake" by hand.** Your wallet's coins (notes)
  *are* your stake. Once a note has aged (about 3.5 hours after it arrived), the node automatically enters
  it in the leader lottery every slot.
* The **Node tab** bar shows this track: *Funded → Aged → Proposing → Earning (stake)*.
  * **Waiting for a slot** = your aged stake is in the lottery; nothing won right now. Normal. With a small
    stake (under ~1 token) wins are rare.
  * **Earning** shows only while the node holds an **unclaimed leader voucher** (it just won a slot).
    After the voucher is claimed it goes back to *Waiting for a slot*.
* This runs whether or not mining is on. **Mining** (PoW, uses CPU) and **stake** (uses aged coins, almost
  no CPU) are two separate ways to earn. The Node tab's *Ready to Claim* = leader vouchers;
  the Mining tab's *Ready to claim* = PoW tickets.

## 7. Updating to a new version

Your config, keystore and chain live in your node folder (e.g. `C:\LogosMiner\data`). Installing packages
never touches them — but **back up `keystore.yaml` first anyway** (section 4).

* **Only the UI changed** (the release says the module is unchanged): just **Reinstall** the UI `.lgx`.
  The node keeps running.
* **Module changed too:**
  1. **Stop Node**
  2. Package Manager → **Reinstall** the module `.lgx`
  3. **Reinstall** the UI `.lgx`
  4. **Start Node** (with *Use the existing config* — never *Start a new node*)

  About one minute offline; same keys and stake afterwards.
* *Resume after restart* (Settings, on by default) restarts the node and mining by itself when Basecamp
  loads again. Pressing **Stop Node** yourself turns that off until you start it again.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| "Package does not contain variant for platform windows-x86_64" | You installed from the official catalog. Use the `.lgx` files from the releases above instead. |
| Install dialog picks an old file | Put the new `.lgx` in a new empty folder |
| Node starts syncing from zero | Settings → Config must point at your existing `user_config.yaml` |
| Stuck on *Bootstrapping* after a restart | Wait up to 1 hour (normal waiting period) |
| Stuck on *Stop Node* after a reinstall | Click once more; it reconciles to *Start Node* |
| Keystore backup asks for a file name / Save stays greyed | Fixed in UI windows.14: Settings → **Save keystore backup** (no file dialog any more) |
| `os error 1314` in logs | Use module windows.2 or newer |
| Memory slowly grows | Use module windows.2 or newer (leak fix) |

## One-click installer

`Install-LogosBlockchain.cmd` (inside `LogosBlockchain-installer-windows.zip` on the UI release, source in `windows/`):
installs Basecamp 0.4.0-rc.2 if missing (pinned sha256), downloads both packages and checks their sha256,
puts them exactly where Basecamp's **Reinstall** would, backs up older copies to `<user dir>\backups\`,
adds a *Logos Blockchain* desktop shortcut and starts Basecamp. Close Basecamp first.
It never creates keys and never touches Basecamp's trusted-publisher list.
Options: `-UserDir <dir>`, `-ModuleLgx <file>` / `-UiLgx <file>`, `-DryRun`, `-NoLaunch`, `-NoShortcut`.

Signer key (both packages):
`did:jwk:eyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6InRpMUIwVG5nODRHTU5wTThCOXNsZmZUSmdJWVJMWHlsNVppOFBiQ2daMW8ifQ`

---

## Wallet reference

Use the **Wallet** tab. Every action shows a review screen with the exact amount in base units
and the estimated fee. Nothing is sent until you tick the confirmation box and press Confirm.

| Section | What it does | Notes |
|---|---|---|
| Accounts | Lists the keys in your keystore and their balances | Read only |
| Transfer | Sends tokens to a 64-hex wallet address | Fee about 2,300 base units |
| LEZ Bridge | Deposits tokens to a LEZ public account through the bridge channel | Fee about 4,200 base units. The page detects the LEZ version (0.3 or 0.4) first, see *LEZ 0.3 and 0.4* below. |
| Channel Deposit | Moves whole notes into a *channel* (an app's own lane on the chain, e.g. the LEZ bridge) | Advanced; most users never need it. The selected notes are used **in full**, and only the holder of that channel's key can withdraw them back. |
| Inscribe | Writes a short text, or an image (PNG/JPEG/GIF/WebP up to 512 KB, windows.13+), into your own inscription channel | Press *Estimate fee* first (about 3,900 base units for 42 bytes of text). The channel key is `inscribe_key.json` next to your config. |
| Channel Withdraw | Releases notes deposited in **your** channel back to normal spendable notes | Needs that channel's key file (default `inscribe_key.json`), the channel id and the note ids. Press *Estimate fee* first. Fee about 3,900 for one note. |
| SDP | Service Declaration Protocol: status, declarations, snapshot, plus declaration/activity/withdrawal forms | **A declaration locks a stake note of at least 1 token (1,000,000,000 base units) and registers you as a Blend provider.** If the declaration uses the node's own Blend keys, the node switches to Blend *core* mode. It must then be reachable from the internet on the declared UDP/QUIC locator, which needs port forwarding and a firewall rule. It also does proof and cover-traffic work. Do not declare from a PC behind NAT. Activity needs a real Blend activity proof. Withdrawal unlocks the stake one epoch after the withdrawal takes effect. There is no slashing. Mining does not need SDP. |

1 token = 1,000,000,000 base units ("lepta").

### Wallet accounts (windows.16+, needs module windows.6+)

- **Wallet › Accounts** is one scrolling page: balances in LGO, short address with copy, **Receive** (address + QR code) and **Rename** (display name only; keys are not touched).
- **+ New account** backs up `keystore.yaml`, `user_config.yaml` and `lez_account.json` to `Documents\LogosBackups` (verified), adds one new key through the module (`wallet_create_account`: never replaces an existing key, keeps every tracked key and auto-claim target, restores both files on any error), backs up the keystore again, then asks for a node restart so the node tracks the new account.
- Settings › **About** shows the UI build, the module it needs and the config in use.

### LEZ 0.3 and 0.4 (windows.15+)

LEZ 0.4 changed what a bridge deposit has to carry to name its recipient:

* **LEZ 0.3** (the public testnet `https://testnet.lez.logos.co/` as of Nov 2026) expects the recipient's 32-byte **account id**. Credit comes after the L1 block is final, which can take hours.
* **LEZ 0.4** (release candidates v0.4.0-rc*) expects `01 00` + the recipient's 32-byte **public key**. Credit usually comes minutes after the L1 block.

Each version ignores the other's format, and the tokens then stay locked in the channel.
So LEZ Bridge asks the LEZ RPC which version it runs before it builds a deposit, and shows the version, RPC and channel.
If it cannot tell, it builds no deposit. Your built-in LEZ account works with both versions.
On 0.4, someone else's account has to be entered as its public key: `wallet account get --keys -a Public/<account id>` prints it as `pk`.
The **LEZ RPC** field can point the page at another sequencer: https anywhere, or plain http to `localhost` / `127.0.0.1` only. Leave it empty for the public testnet.

### LEZ deposit tracker and inscription history (windows.10+)

Basecamp does not let UI plugins use the network (*"sandboxed ui_qml modules may not use the network"*).
So both features read the chain **through the blockchain module** (`getCryptarchiaInfo`, `getBlock`), not over HTTP.
In windows.9 they used HTTP and were blocked inside Basecamp; windows.10 fixes this.

* **LEZ Bridge → Deposit tracker** follows every bridge deposit through four steps:
  *Sent → In an L1 block → Final on L1 → Credited on LEZ*.
  It finds the block that holds the deposit by walking back from the tip (up to 300 blocks).
  It shows how many slots are left until that block is final (LIB).
  Since windows.11 the last step is automatic: the UI backend (C++, outside the QML sandbox) asks the LEZ RPC
  (`https://testnet.lez.logos.co/`, method `getAccountBalance`, HTTPS only, nothing else) for the account balance.
  It records the balance when you send, and marks the deposit *Credited* once the balance has grown by at least the amount
  (since windows.15 it no longer waits for L1 finality first, because LEZ 0.4 credits earlier). You can still press **Mark credited** yourself.
  New deposits are added automatically. To follow an older deposit, enter its tx hash, amount, LEZ account and the L1 slot.
  The list is kept in `blockchain_ui_lez_tracker.ini` and survives restarts. It only reads data and never sends anything.
* If the channel field holds anything other than the LEZ bridge channel,
  the bridge screen says *"To channel …"* instead of LEZ. Nothing credits a LEZ account in that case.
  Only the holder of that channel's key can withdraw the note again.
* **Inscribe → Inscription history** shows what your channel has written on chain, newest first.
  The channel id is filled from your default inscribe key when the screen opens.
  *Scan recent* reads the last 100 blocks; *Scan older* continues 100 blocks further back each time.
  It reads from your own node only.

### Decimal separator

Amount fields accept **both** `.` and `,` as the decimal mark (`0.5` = `0,5`). This matters on Russian, German and similar locales.
Do not use thousands separators: `1.234,5` is rejected as ambiguous.
You can enter at most 9 decimals. The field shows the exact base-unit value, and Review stays disabled until the amount is valid.

### Error messages

Errors are shown in plain words, with the raw node message after "Details:":
* *The node is not reachable right now* means you should Start Node and wait for Online.
* *Not enough funds* shows what is available in tokens and base units.
* *That address is not valid* means a wallet address is 64 hex characters and a LEZ account is base58.
* *The fee would be higher than the maximum you allowed* means you should raise Max fee or try later.

## Technical details: updates and auto-resume

* **Since UI windows.12 + module windows.4, reinstalling the UI keeps the node running** when *Resume after restart* is on.
  The new UI finds the running node and shows it as Running. (Basecamp also tears the UI down when you open another section,
  for example Package Manager; that no longer stops the node either.) When Basecamp quits, the module stops the node.
  With older packages, reinstalling the UI stopped the node.
* With *Resume after restart* on, the **module** also remembers the last config and whether mining was on
  (`autostart.json` in its module data folder). When Basecamp loads the module again it starts the node with that
  same config and turns mining back on once the node is Online. **Stop Node** clears this.
* Since UI `v0.3.5-windows.8` the UI has **Resume after restart** (Settings, on by default).
  It remembers that the node was running, which config it used, and whether mining was on,
  in `blockchain_ui_resume.ini` in Basecamp's config folder.
  When the UI loads again it starts the node with the **same existing config** and re-arms mining once the node is synced.
  It never creates a new node. It waits about 10 s first. It does nothing if the config changed,
  or if a resume was tried in the last 2 minutes. (It also checks whether something already answers on `127.0.0.1:8080`,
  but inside Basecamp that check is blocked by the sandbox, so it only helps outside Basecamp.
  A second node on the same ports would fail to bind rather than run twice.)
  If you press **Stop Node** yourself, nothing is resumed.
* Turn the switch off if you want the node to stay stopped after an update.
* Updating the **module** package replaces `logos_blockchain.dll`. Stop Node first; Reinstall then works
  without Module Inspector (tested with module windows.4 → windows.5).
* Your config, keystore and chain state live in your node folder, for example `C:\LogosMiner\data`.
  Package installs never touch them. Back up `keystore.yaml` and `inscribe_key.json`, and never share them.

