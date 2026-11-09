import SwiftUI

/// Tipografia centralizada: fuente del sistema con los tamaños de macOS.
enum AppTypography {
    static let cardTitle = Font.system(size: 11, weight: .medium)
    static let cardCaption = Font.system(size: 10, weight: .regular)
    static let cardText = Font.system(size: 10.5, weight: .regular)
    static let body = Font.system(size: 12, weight: .regular)
    static let bodyStrong = Font.system(size: 12, weight: .semibold)
    static let title = Font.system(size: 13, weight: .semibold)
    static let subtitle = Font.system(size: 11, weight: .regular)
}
