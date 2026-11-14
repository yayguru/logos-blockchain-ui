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
