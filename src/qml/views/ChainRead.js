.pragma library
// Read-only chain helpers that go through the blockchain backend (the module
// API), not HTTP: Basecamp sandboxes ui_qml plugins and blocks their network
// access. `chain` is an object with info(cb) and block(headerId, cb), provided
// by BlockchainView. Nothing here signs or sends.

// Normalise the get_cryptarchia_info answer to { slot, lib_slot, tip, height }.
function parseInfo(v) {
    var o = v
    if (typeof o === "string") { try { o = JSON.parse(o) } catch (e) { return null } }
    if (o && o.cryptarchia_info) o = o.cryptarchia_info
    if (!o || o.slot === undefined) return null
    return { slot: Number(o.slot), lib_slot: Number(o.lib_slot), tip: String(o.tip || ""), height: Number(o.height) }
}

// Normalise a get_block answer to the block object ({ header, transactions }).
function parseBlock(v) {
    var o = v
    if (typeof o === "string") { try { o = JSON.parse(o) } catch (e) { return null } }
    if (o && o.block !== undefined) {
        o = o.block
        if (typeof o === "string") { try { o = JSON.parse(o) } catch (e) { return null } }
    }
    return o && o.header ? o : null
}

// Walk back from `fromId` through parent links, at most `max` blocks or until
// a block's slot is below `minSlot`. onBlock(block) may return true to stop.
function walkBack(chain, fromId, max, minSlot, onBlock, done) {
    var n = 0
    function next(id) {
        if (!id || n >= max) { done(true, id, n); return }
        chain.block(id, function(ok, raw) {
            if (!ok) { done(false, raw, n); return }
            var b = parseBlock(raw)
            if (!b) { done(false, "unreadable block", n); return }
            n++
            var slot = Number(b.header.slot)
            if (minSlot >= 0 && slot < minSlot) { done(true, "", n); return }
            if (onBlock(b) === true) { done(true, "", n); return }
            next(String(b.header.parent_block || ""))
        })
    }
    next(fromId)
}

// Decode hex bytes as UTF-8. Returns { text, printable, size }.
function hexToText(hex) {
    var h = String(hex || "").replace(/^0x/i, "")
    var bytes = []
    for (var i = 0; i + 1 < h.length; i += 2) bytes.push(parseInt(h.substr(i, 2), 16))
    var s = ""
    var printable = true
    for (var j = 0; j < bytes.length; ) {
        var c = bytes[j], cp = -1, n = 0
        if (c < 0x80) { cp = c; n = 1 }
        else if ((c & 0xe0) === 0xc0) { cp = c & 0x1f; n = 2 }
        else if ((c & 0xf0) === 0xe0) { cp = c & 0x0f; n = 3 }
        else if ((c & 0xf8) === 0xf0) { cp = c & 0x07; n = 4 }
        if (cp < 0 || j + n > bytes.length) { printable = false; break }
        for (var k = 1; k < n; ++k) {
            if ((bytes[j + k] & 0xc0) !== 0x80) { printable = false; break }
            cp = (cp << 6) | (bytes[j + k] & 0x3f)
        }
        if (!printable) break
        if (cp < 0x20 && cp !== 0x0a && cp !== 0x0d && cp !== 0x09) { printable = false; break }
        s += String.fromCodePoint(cp)
        j += n
    }
    return { text: printable ? s : "", printable: printable, size: bytes.length }
}

// ---- Image inscriptions (windows.13) ----
// The image type of a payload from its magic bytes, or "".
function imageKind(hex) {
    var h = String(hex || "").replace(/^0x/i, "").toLowerCase()
    if (h.indexOf("89504e470d0a1a0a") === 0) return "png"
    if (h.indexOf("ffd8ff") === 0) return "jpeg"
    if (h.indexOf("474946383761") === 0 || h.indexOf("474946383961") === 0) return "gif"
    if (h.indexOf("52494646") === 0 && h.substr(16, 8) === "57454250") return "webp"
    return ""
}

function hexToBase64(hex) {
    var h = String(hex || "").replace(/^0x/i, "")
    var al = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var out = []
    var n = Math.floor(h.length / 2)
    var b = function(i) { return parseInt(h.substr(2 * i, 2), 16) }
    for (var i = 0; i < n; i += 3) {
        var b0 = b(i), b1 = i + 1 < n ? b(i + 1) : 0, b2 = i + 2 < n ? b(i + 2) : 0
        var t = (b0 << 16) | (b1 << 8) | b2
        out.push(al[(t >> 18) & 63], al[(t >> 12) & 63],
                 i + 1 < n ? al[(t >> 6) & 63] : "=",
                 i + 2 < n ? al[t & 63] : "=")
    }
    return out.join("")
}

// data: URL for an image payload, or "" when it is not one of the four types.
function imageDataUrl(hex) {
    var k = imageKind(hex)
    if (!k.length) return ""
    return "data:image/" + k + ";base64," + hexToBase64(hex)
}
