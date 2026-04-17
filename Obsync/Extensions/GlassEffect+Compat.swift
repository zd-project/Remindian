import SwiftUI

/// Compatibility stub for macOS 26.0 GlassStyle.
enum GlassStyle {
    case regular, clear
}

extension View {
    /// Compatibility shim for macOS 26.0+ Liquid Glass.
    /// Provides an `.ultraThinMaterial` fallback for older systems.
    /// Shape is generic to match the real API's flexibility.
    func glassEffect<S: Shape>(_ style: GlassStyle = .regular, in shape: S) -> some View {
        self.background(.ultraThinMaterial, in: shape)
    }
}
