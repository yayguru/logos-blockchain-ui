// Pure helpers shared by the Transfer and LEZ Bridge forms. No QML types here,
// so the same file runs under node for the unit check in doctests/.
//
// Amounts are lepta decimal strings; nothing is converted to Number where a
// u64 could lose digits. Fees are small (< 2^53), so those are plain numbers.

// BN254 scalar field modulus, big-endian hex. A wallet key is 32 bytes
// little-endian and must be < this (the node's fr_from_bytes refuses others).
var FR_MODULUS_BE = "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

// "" when `text` is a usable 64-hex wallet key, otherwise why not.
function walletKeyError(text) {
    var s = String(text || "").trim()
    if (s.indexOf("0x") === 0 || s.indexOf("0X") === 0)
        s = s.substring(2)
    if (s.length === 0)
        return "Enter the recipient's wallet key."
    if (!/^[0-9a-fA-F]{64}$/.test(s))
        return "A wallet key is 64 hex characters (32 bytes)."
    s = s.toLowerCase()
    var be = ""
    for (var i = 62; i >= 0; i -= 2)
        be += s.substring(i, i + 2)
    if (be >= FR_MODULUS_BE)
        return "This is not a valid wallet key (outside the key field)."
    return ""
}

function normalizeWalletKey(text) {
    var s = String(text || "").trim()
    if (s.indexOf("0x") === 0 || s.indexOf("0X") === 0)
        s = s.substring(2)
    return s.toLowerCase()
}

var B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

// Base58 (Bitcoin alphabet) to a byte array, or null on a bad character.
// Byte-wise long multiplication, so no BigInt is needed.
function base58Decode(text) {
    var s = String(text || "").trim()
    if (s.length === 0)
        return null
    var bytes = []
    for (var i = 0; i < s.length; ++i) {
        var v = B58.indexOf(s[i])
        if (v < 0)
            return null
        var carry = v
        for (var j = 0; j < bytes.length; ++j) {
            carry += bytes[j] * 58
            bytes[j] = carry & 0xff
            carry >>= 8
        }
        while (carry > 0) {
            bytes.push(carry & 0xff)
            carry >>= 8
        }
    }
    for (var k = 0; k < s.length && s[k] === "1"; ++k)
        bytes.push(0)
    return bytes.reverse()
}

function bytesToHex(bytes) {
    var out = ""
    for (var i = 0; i < bytes.length; ++i)
        out += ("0" + bytes[i].toString(16)).slice(-2)
    return out
}

// "" when `text` is a LEZ public account id (base58 of exactly 32 bytes).
function lezAccountError(text) {
    var s = String(text || "").trim()
    if (s.length === 0)
        return "Enter the LEZ account that should receive the tokens."
    var b = base58Decode(s)
    if (b === null)
        return "A LEZ account is base58 text (no 0, O, I or l)."
    if (b.length !== 32)
        return "A LEZ account decodes to 32 bytes; this decodes to " + b.length + "."
    return ""
}

function lezAccountHex(text) {
    var b = base58Decode(text)
    return b && b.length === 32 ? bytesToHex(b) : ""
}

// Fee models at the live gas prices (execution `ep`, storage `sp`).
// Calibrated on mainnet-testnet txs at ep=1 / sp=7:
//   inscription (40 B)     mandatory 3509 = 646*1 + (40+369)*7   (exact)
//   LEZ deposit, 1 note    actual    4218 (2cc1bac4, de6c98fa)    -> 646 + 511*7 = 4223
//   wallet transfer 1 in / 2 out ~2.3k (3cac14d1)                -> 590 + 245*7 = 2305
// The wallet computes the exact fee when it builds the transaction; these are
// the preview figures, and the deposit cap below is what the node enforces.
function estimateTransferFee(ep, sp) {
    return 590 * ep + 245 * sp
}

function estimateDepositFee(noteCount, ep, sp) {
    var n = Math.max(1, noteCount | 0)
    return 646 * ep + (511 + 32 * (n - 1)) * sp
}

// Hard cap handed to channel_deposit_with_notes: 1.5x the preview, so normal
// fee movement passes and a mispriced tx is refused by the node.
function depositFeeCap(estimate) {
    return Math.ceil(estimate * 3 / 2)
}

// Lepta (integer, small) to canonical tokens text with 9 decimals trimmed.
function leptaSmallToTokens(lepta) {
    var s = String(Math.max(0, Math.floor(lepta)))
    while (s.length < 10)
        s = "0" + s
    var intPart = s.substring(0, s.length - 9).replace(/^0+(?=\d)/, "")
    var frac = s.substring(s.length - 9).replace(/0+$/, "")
    return frac.length ? intPart + "." + frac : intPart
}

// First note whose value equals `amountLepta` exactly (string compare), or null.
function findExactNote(notes, amountLepta, excludeIds) {
    var ex = excludeIds || []
    for (var i = 0; i < (notes || []).length; ++i) {
        var n = notes[i]
        if (String(n.value) === String(amountLepta) && ex.indexOf(String(n.id)) < 0)
            return { id: String(n.id), value: String(n.value) }
    }
    return null
}

// Plain-language wording for raw module/node errors. Returns the friendly
// sentence followed by the original text as "Details", so nothing the node said
// is hidden. Unknown errors pass through unchanged.
function _leptaToTokensPlain(lepta) {
    var s = String(lepta).replace(/^0+/, "")
    if (s.length === 0) s = "0"
    while (s.length < 10) s = "0" + s
    var whole = s.slice(0, s.length - 9).replace(/^0+(?=\d)/, "")
    var frac = s.slice(s.length - 9).replace(/0+$/, "")
    return frac.length ? whole + "." + frac : whole
}

function humanError(message, formatLepta) {
    var m = String(message === undefined || message === null ? "" : message).trim()
    if (m.length === 0)
        return ""
    var lower = m.toLowerCase()
    var nice = ""
    var avail = /available\s*[=:]\s*(\d+)/i.exec(m)
    if (/not enough funds|insufficient (funds|balance)|not have enough/.test(lower)) {
        nice = "Not enough funds in this account for the amount plus the fee"
        if (avail) nice += " (available " + (formatLepta ? formatLepta(avail[1]) : _leptaToTokensPlain(avail[1]) + " TestToken") + " = " + avail[1] + " base units)"
        nice += ". Lower the amount or pick another account."
    } else if (/not reachable|connection refused|connection to the node module failed|not running|node is offline|module not initialized|timed? ?out|call failed/.test(lower)) {
        nice = "The node is not reachable right now. Start the node (Start Node) and wait until it shows Online, then try again."
    } else if (/(invalid|malformed|bad).{0,40}(key|address|public key|recipient|hex|account)|(key|address).{0,30}(invalid|not valid|out of (range|field))/.test(lower)) {
        nice = "That address is not valid. A wallet address is 64 hex characters; a LEZ account is a base58 string."
    } else if (/(fee|max_tx_fee|max fee).{0,60}(exceed|too (high|low)|above|insufficient|greater)|(exceed|above).{0,40}(fee|cap)/.test(lower)) {
        nice = "The fee would be higher than the maximum you allowed. Raise the max fee a little or try again later."
    } else if (/note.{0,40}(not found|unknown|spent|already)/.test(lower)) {
        nice = "That note is no longer available (already spent or not yet confirmed). Refresh and try again in a minute."
    }
    if (!nice.length)
        return m
    return nice + " Details: " + m
}
