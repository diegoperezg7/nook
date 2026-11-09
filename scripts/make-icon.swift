// Genera el icono de Nook (todas las resoluciones) con CoreGraphics.
// Una gota de cristal liquido que cuelga del notch, sobre azul electrico.
// Uso: swift scripts/make-icon.swift Nook/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreImage

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)!
}

/// Silueta de la gota: cuelga del notch con un cuello que se ensancha en una esfera.
/// Las curvas del cuello llegan tangentes al arco, asi no hay costuras ni bultos.
func dropPath(in body: CGRect) -> CGPath {
    let s = body.width
    let mid = body.midX
    let top = body.maxY - s * 0.15           // base del notch
    let neckHalf = s * 0.085                  // medio ancho del cuello
    let radius = s * 0.25                     // radio de la esfera
    let center = CGPoint(x: mid, y: top - s * 0.43)
    let a: CGFloat = 0.6                      // angulo de union sobre el ecuador
    let k = radius * 0.75                     // tension de la curva

    let leftJoin = CGPoint(x: center.x - radius * cos(a), y: center.y + radius * sin(a))
    let rightJoin = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))

    let path = CGMutablePath()
    path.move(to: CGPoint(x: mid - neckHalf, y: top))
    // Recorrido antihorario: la tangente en el angulo pi-a apunta a (-sin a, -cos a).
    path.addCurve(
        to: leftJoin,
        control1: CGPoint(x: mid - neckHalf, y: top - s * 0.09),
        control2: CGPoint(x: leftJoin.x + k * sin(a), y: leftJoin.y + k * cos(a))
    )
    path.addArc(center: center, radius: radius, startAngle: .pi - a, endAngle: a, clockwise: false)
    path.addCurve(
        to: CGPoint(x: mid + neckHalf, y: top),
        control1: CGPoint(x: rightJoin.x - k * sin(a), y: rightJoin.y + k * cos(a)),
        control2: CGPoint(x: mid + neckHalf, y: top - s * 0.09)
    )
    path.closeSubpath()
    return path
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Lienzo de macOS: cuadrado redondeado con margen (824/1024).
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Sombra del icono.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x1238C9))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Fondo: azul electrico profundo con un halo de luz arriba.
    ctx.drawLinearGradient(
        gradient([color(0x3D7BFF), color(0x1F4FF0), color(0x0B1E78)], [0, 0.5, 1]),
        start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: []
    )
    ctx.drawRadialGradient(
        gradient([color(0x9CC0FF, 0.55), color(0x9CC0FF, 0)], [0, 1]),
        startCenter: CGPoint(x: body.midX, y: body.maxY - body.height * 0.35), startRadius: 0,
        endCenter: CGPoint(x: body.midX, y: body.maxY - body.height * 0.35), endRadius: body.width * 0.6,
        options: []
    )

    // Gota de cristal: sombra, cuerpo translucido, degradado interior y borde de luz.
    let drop = dropPath(in: body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: color(0x020A33, 0.55))
    ctx.addPath(drop)
    ctx.setFillColor(color(0xFFFFFF, 0.16))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(drop)
    ctx.clip()
    let dropBox = drop.boundingBoxOfPath
    ctx.drawLinearGradient(
        gradient([color(0xFFFFFF, 0.42), color(0xFFFFFF, 0.06), color(0x7FB0FF, 0.35)], [0, 0.55, 1]),
        start: CGPoint(x: dropBox.midX, y: dropBox.maxY), end: CGPoint(x: dropBox.midX, y: dropBox.minY), options: []
    )
    // Refraccion: luz concentrada abajo, como en una gota real.
    ctx.drawRadialGradient(
        gradient([color(0xCFE0FF, 0.75), color(0xCFE0FF, 0)], [0, 1]),
        startCenter: CGPoint(x: dropBox.midX, y: dropBox.minY + dropBox.height * 0.18), startRadius: 0,
        endCenter: CGPoint(x: dropBox.midX, y: dropBox.minY + dropBox.height * 0.18), endRadius: dropBox.width * 0.42,
        options: []
    )
    // Brillo especular: un arco fino que sigue el borde izquierdo de la esfera.
    let sphereRadius = dropBox.width / 2
    let sphereCenter = CGPoint(x: dropBox.midX, y: dropBox.minY + sphereRadius)
    ctx.addArc(
        center: sphereCenter, radius: sphereRadius * 0.78,
        startAngle: .pi * 0.62, endAngle: .pi * 0.95, clockwise: false
    )
    ctx.setStrokeColor(color(0xFFFFFF, 0.8))
    ctx.setLineWidth(sphereRadius * 0.09)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.addPath(drop)
    ctx.setStrokeColor(color(0xFFFFFF, 0.75))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()

    // Notch negro, por encima de la gota (de el cuelga).
    let notchW = body.width * 0.5
    let notchH = body.height * 0.15
    let notch = CGRect(x: body.midX - notchW / 2, y: body.maxY - notchH, width: notchW, height: notchH + body.height)
    let r = notchH * 0.6
    ctx.addPath(CGPath(roundedRect: notch, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.setFillColor(color(0x05070D))
    ctx.fillPath()

    ctx.restoreGState()

    // Borde fino de luz del icono (acabado de cristal).
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.22))
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(size: size).write(to: output.appendingPathComponent("icon_\(size).png"))
}
print("Iconos generados en \(output.path)")
