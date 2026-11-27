import QtQuick

// Draws a QR matrix ({ size, rows: ["0101…"] }) with a quiet zone, always
// black on white so phone cameras read it in either theme.
Canvas {
    id: root

    property var matrix: null
    readonly property int modules: matrix && matrix.size ? matrix.size : 0

    implicitWidth: 200
    implicitHeight: 200
    onMatrixChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = "#ffffff"
        ctx.fillRect(0, 0, width, height)
        if (modules <= 0)
            return
        const quiet = 4
        const cell = Math.floor(Math.min(width, height) / (modules + 2 * quiet))
        if (cell <= 0)
            return
        const offX = Math.floor((width - cell * modules) / 2)
        const offY = Math.floor((height - cell * modules) / 2)
        ctx.fillStyle = "#000000"
        for (let y = 0; y < modules; y++) {
            const row = matrix.rows[y]
            for (let x = 0; x < modules; x++) {
                if (row.charAt(x) === "1")
                    ctx.fillRect(offX + x * cell, offY + y * cell, cell, cell)
            }
        }
    }
}
