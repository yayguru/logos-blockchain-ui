.pragma library
// Small read-only helpers for the node's local HTTP API and the public LEZ
// JSON-RPC. Nothing here signs or sends a transaction.

function get(url, timeoutMs, cb) {
    var x = new XMLHttpRequest()
    var done = false
    x.onreadystatechange = function() {
        if (x.readyState !== XMLHttpRequest.DONE || done) return
        done = true
        if (x.status >= 200 && x.status < 300) cb(true, x.responseText)
        else cb(false, x.status ? ("HTTP " + x.status + " " + (x.responseText || "").slice(0, 200)) : "no answer")
    }
    x.open("GET", url)
    x.timeout = timeoutMs || 20000
    x.ontimeout = function() { if (!done) { done = true; cb(false, "timeout") } }
    x.send()
}

function getJson(url, timeoutMs, cb) {
    get(url, timeoutMs, function(ok, text) {
        if (!ok) { cb(false, text); return }
        try { cb(true, JSON.parse(text)) } catch (e) { cb(false, "bad JSON: " + e) }
    })
}

// blocks_range answers NDJSON, one {"block": ...} object per line.
function getBlocks(apiBase, query, cb) {
    get(apiBase + "/cryptarchia/blocks_range?" + query, 60000, function(ok, text) {
        if (!ok) { cb(false, text); return }
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; ++i) {
            var l = lines[i].trim()
            if (!l.length) continue
            try {
                var o = JSON.parse(l)
                if (o.block) out.push(o.block)
            } catch (e) {}
        }
        cb(true, out)
    })
}

function rpc(url, method, params, cb) {
    var x = new XMLHttpRequest()
    var done = false
    x.onreadystatechange = function() {
        if (x.readyState !== XMLHttpRequest.DONE || done) return
        done = true
        if (x.status < 200 || x.status >= 300) { cb(false, x.status ? "HTTP " + x.status : "no answer"); return }
        try {
            var o = JSON.parse(x.responseText)
            if (o.error) cb(false, JSON.stringify(o.error))
            else cb(true, o.result)
        } catch (e) { cb(false, "bad JSON") }
    }
    x.open("POST", url)
    x.setRequestHeader("Content-Type", "application/json")
    x.timeout = 20000
    x.ontimeout = function() { if (!done) { done = true; cb(false, "timeout") } }
    x.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: method, params: params }))
}

// Decode hex bytes as UTF-8. Returns { text, printable }.
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
