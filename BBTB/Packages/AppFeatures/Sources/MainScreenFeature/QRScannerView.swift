import SwiftUI
import Localization
import DesignSystem
import AVFoundation

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

/// IMP-02 / UI-SPEC §5 — QR-scanner SwiftUI обёртка над AVFoundation.
public struct QRScannerView: View {
    public let onCodeScanned: (String) -> Void
    public let onCancel: () -> Void

    @State private var permissionState: CameraPermission.Status = CameraPermission.currentStatus()

    public init(onCodeScanned: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCodeScanned = onCodeScanned
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L10n.qrCancel, action: onCancel)
                Spacer()
                Text(L10n.qrTitle).bold()
                Spacer()
                // Symmetric spacer (invisible).
                Color.clear.frame(width: 60, height: 1)
            }
            .padding()

            ZStack {
                Color.black
                if permissionState == .denied || permissionState == .restricted {
                    permissionDeniedView
                } else if permissionState == .authorized {
                    cameraPreview
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
        }
        .task {
            await requestPermissionIfNeeded()
        }
    }

    private func requestPermissionIfNeeded() async {
        do {
            _ = try await CameraPermission.request()
            permissionState = CameraPermission.currentStatus()
        } catch {
            permissionState = CameraPermission.currentStatus()
        }
    }

    @ViewBuilder
    private var cameraPreview: some View {
        #if os(iOS)
        ZStack {
            QRScannerRepresentable(onScan: onCodeScanned)
                .ignoresSafeArea()
            VStack {
                Spacer()
                Text(L10n.qrHint)
                    .foregroundColor(.white.opacity(0.9))
                    .font(DS.Typography.callout)
                    .padding()
            }
        }
        #elseif os(macOS)
        ZStack {
            QRScannerNSRepresentable(onScan: onCodeScanned)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                Spacer()
                Text(L10n.qrHint)
                    .foregroundColor(.white.opacity(0.9))
                    .font(DS.Typography.callout)
                    .padding()
            }
        }
        #endif
    }

    @ViewBuilder
    private var permissionDeniedView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "video.slash")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(L10n.qrPermissionDeniedTitle)
                .font(DS.Typography.title)
                .foregroundColor(.white)
            Text(L10n.qrPermissionDeniedMessage)
                .font(DS.Typography.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button(L10n.qrPermissionDeniedOpenSettings, action: openSystemSettings)
                .buttonStyle(.borderedProminent)
            Button(L10n.actionCancel, action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

#if os(iOS)
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(onScan: onScan)
    }
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}
#elseif os(macOS)
private struct QRScannerNSRepresentable: NSViewRepresentable {
    let onScan: (String) -> Void
    func makeNSView(context: Context) -> QRScannerNSView {
        QRScannerNSView(onScan: onScan)
    }
    func updateNSView(_ nsView: QRScannerNSView, context: Context) {}
}
#endif
