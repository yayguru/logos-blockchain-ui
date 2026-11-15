# Logos Blockchain UI on Windows (Basecamp)

This guide installs the **unofficial** Windows build of the Logos Blockchain node and UI from scratch.
It works on any Windows 10/11 x64 PC, needs no admin rights, and runs the node inside Logos Basecamp.

> Community builds published by `yayguru` as GitHub prereleases. They are not official Logos releases.

## 1. What you need

| Item | Version | Where |
|---|---|---|
| Logos Basecamp | **0.4.0-rc.2** (Qt 6.11, mingw x64) | Basecamp release page (`basecamp-setup.exe`). It installs per user to `%LOCALAPPDATA%\Programs\LogosBasecamp`. |
| Blockchain module | `blockchain_module-0.3.4-windows-x86_64.lgx` (latest `v0.3.4-windows.N`) | https://github.com/yayguru/logos-blockchain-module/releases |
| Blockchain UI | `blockchain_ui-0.3.5-windows-x86_64.lgx` (latest `v0.3.5-windows.N`) | https://github.com/yayguru/logos-blockchain-ui/releases |

Check each download against the `SHA256SUMS` file in the release:

```powershell
Get-FileHash .\blockchain_ui-0.3.5-windows-x86_64.lgx -Algorithm SHA256
```

Free disk space: about 3 GB for the chain state, plus RAM for a node that uses about 1 to 1.3 GB.

## 2. Install the packages

1. Put each `.lgx` in its **own new folder**, for example `C:\Users\<you>\lgx\ui-w8\`.
   Older packages use the same file name, so this stops the file dialog from picking an old copy.
2. Open Basecamp, then go to **Package Manager → Install Local Package**.
3. Install the module first, then the UI.

### Trust and signer note

The packages are signed with the `yayguru` key:
`did:jwk:eyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6InRpMUIwVG5nODRHTU5wTThCOXNsZmZUSmdJWVJMWHlsNVppOFBiQ2daMW8ifQ`.

Basecamp shows *"signed by a publisher you don't trust yet"*. Click **Install** (or **Reinstall**).
You do **not** need to click **Trust**. Trusting a key makes Basecamp accept future packages from that publisher
without asking, so only do it if you have decided to trust that publisher.

If Windows Firewall asks about `logos_host.exe`, you can press Cancel. Outgoing peer connections still work.

## 3. Existing node vs new node

Open the **Blockchain** app in Basecamp. On first start it asks for a config.

* **Existing config:** you already ran a node, for example `C:\LogosMiner\data\user_config.yaml`.
  Choose *Use existing config* and point it at that `user_config.yaml`.
  The keystore (`keystore.yaml`) and `state\` next to it are reused, so there is no new sync and no new keys.
  Relative `state.base_folder` paths are resolved against the config folder.
* **New node:** choose *Start a new node*. It generates keys and a config in a folder you choose,
  then syncs from genesis, which takes a while.
  Only do this for a fresh install. If you click it on a machine that already has a node,
  you get a second identity and a second chain copy.

Then press **Start Node**. The header shows *Starting → Online / Following* once the node has synced with the network.
Settings → *Config* shows which config is in use.

## 4. Mining

* Open the **Mining** tab, or press **Fund** in the header.
  Fund arms PoW mining with the thread count from your config (`max_threads`).
* *Auto-claim* claims leader rewards automatically. The **Rewards** tab lists claims.
* Stopping the node stops mining. Starting the node again does not re-arm mining by itself
  unless *Resume after restart* is on (see section 6).

## 5. Wallet

Use the **Wallet** tab. Every action shows a review screen with the exact amount in base units
and the estimated fee. Nothing is sent until you tick the confirmation box and press Confirm.

| Section | What it does | Notes |
|---|---|---|
| Accounts | Lists the keys in your keystore and their balances | Read only |
| Transfer | Sends tokens to a 64-hex wallet address | Fee about 2,300 base units |
| LEZ Bridge | Deposits tokens to a LEZ (base58) account through the bridge channel | Fee about 4,200 base units. The credit shows on LEZ after the bridge processes it, which can take a while. |
| Channel Deposit | Locks one of your notes into a channel | Advanced |
| Inscribe | Writes a short text (≤ about 1 KB) into your own inscription channel | Fee about 3,900 for 42 bytes. The channel key is `inscribe_key.json` in the node data folder. |
| Channel Withdraw | Releases notes deposited in **your** channel back to normal spendable notes | Needs that channel's key file (default `inscribe_key.json`), the channel id and the note ids. Press *Estimate fee* first. Fee about 3,900 for one note. |
| SDP | Service Declaration Protocol: status, declarations, snapshot, plus declaration/activity/withdrawal forms | **A declaration locks a stake note of at least 1 token (1,000,000,000 base units) and registers you as a Blend provider.** If the declaration uses the node's own Blend keys, the node switches to Blend *core* mode. It must then be reachable from the internet on the declared UDP/QUIC locator, which needs port forwarding and a firewall rule. It also does proof and cover-traffic work. Do not declare from a PC behind NAT. Activity needs a real Blend activity proof. Withdrawal unlocks the stake one epoch after the withdrawal takes effect. There is no slashing. Mining does not need SDP. |

1 token = 1,000,000,000 base units ("lepta").

### LEZ deposit tracker and inscription history (windows.9+)

* **LEZ Bridge → Deposit tracker** follows every bridge deposit through four steps:
  *Sent → In an L1 block → Final on L1 → Credited on LEZ*.
  It shows how many slots are left until the L1 block is final (LIB),
  and it watches the LEZ account balance through the public LEZ RPC (`testnet.lez.logos.co`).
  New deposits are added automatically.
  To follow an older deposit, enter its tx hash, amount, LEZ account and (optionally) the slot and the previous balance.
  The list is kept in `blockchain_ui_lez_tracker.ini` and survives restarts. It only reads data and never sends anything.
* If the channel field holds anything other than the LEZ bridge channel,
  the bridge screen now says *"To channel …"* instead of LEZ. Nothing credits a LEZ account in that case.
  Only the holder of that channel's key can withdraw the note again.
* **Inscribe → Inscription history** shows what your channel has written on chain, newest first.
  *Latest* jumps to the channel tip. *Scan older* walks back 400 blocks at a time. It reads from your own node only.

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

## 6. Updating the UI or module (read this)

* **Installing or reinstalling the UI package stops the running node.** Basecamp unloads the old UI,
  and the UI backend stops the node when it is torn down. The `logos_host` process stays alive.
* Since UI `v0.3.5-windows.8` the UI has **Resume after restart** (Settings, on by default).
  It remembers that the node was running, which config it used, and whether mining was on,
  in `blockchain_ui_resume.ini` in Basecamp's config folder.
  When the UI loads again it starts the node with the **same existing config** and re-arms mining once the node is synced.
  It never creates a new node. It waits about 10 s first. It does nothing if the config changed,
  if anything already answers on `127.0.0.1:8080`, or if a resume was tried in the last 2 minutes.
  If you press **Stop Node** yourself, nothing is resumed.
* Turn the switch off if you want the node to stay stopped after an update.
* Updating the **module** package replaces `logos_blockchain.dll` while it is in use.
  Stop the node first, use Module Inspector → Unload, install, then Load and Start Node.
* Your config, keystore and chain state live in your node folder, for example `C:\LogosMiner\data`.
  Package installs never touch them. Back up `keystore.yaml` and `inscribe_key.json`, and never share them.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| Install dialog picks an old file | Put the new `.lgx` in a new empty folder |
| Node starts a fresh sync | Settings → Config must point at your existing `user_config.yaml` |
| Stuck on *Stop Node* after a reinstall | Click once more and the button reconciles to *Start Node* |
| `os error 1314` (symlink) in logs | Use the windows.2+ module, which disables the `.latest` symlink for non-admin users |
| Memory slowly grows | Use module `v0.3.4-windows.2` or later (memory-leak fix) |
