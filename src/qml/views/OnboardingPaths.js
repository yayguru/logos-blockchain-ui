.pragma library

// Shared by the setup and network steps, which both take a path from a
// FileDialog and show it in an editable field.
//
// Was duplicated in both files. A file dialog answers with file:///…; the
// field shows a path, so that what the user sees is what they could have
// typed themselves. Two copies of that rule is two places for it to diverge.
function toLocalPath(url) {
    var s = String(url)
    if (s.indexOf("file:") !== 0)
        return s
    // file:///C:/Users/x -> C:\Users\x ; file:///home/x -> /home/x ;
    // file://server/share -> \\server\share (Windows UNC).
    var rest = s.replace(/^file:(\/\/(localhost)?)?/i, "")
    rest = decodeURIComponent(rest)
    if (/^\/[A-Za-z]:/.test(rest))
        return rest.substring(1).replace(/\//g, "\\")
    if (rest.indexOf("/") !== 0 && rest.length > 0)
        return "\\\\" + rest.replace(/\//g, "\\")
    return rest
}

// The inverse, for FileDialog.currentFolder: the directory holding `path`, as a
// URL. Browsing for a config should start where the current one lives rather
// than wherever Qt last happened to be.
function toFolderUrl(path) {
    var s = String(path).trim().replace(/\\/g, "/")
    var cut = s.lastIndexOf("/")
    if (cut <= 0)
        return ""
    var dir = s.substring(0, cut)
    // C:/x needs file:///C:/x, /home/x needs file:///home/x.
    return (/^[A-Za-z]:/.test(dir) ? "file:///" : "file://") + encodeURI(dir)
}
