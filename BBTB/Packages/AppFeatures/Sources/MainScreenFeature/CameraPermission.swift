import Foundation
import AVFoundation

/// IMP-02 / RESEARCH §8.2 — camera permission gating.
public enum CameraPermission {
    public enum Status: Sendable {
        case authorized
        case denied
        case restricted
        case notDetermined
    }

    public enum CameraError: Error, LocalizedError {
        case userDenied
        case restricted
        case noCamera

        public var errorDescription: String? {
            switch self {
            case .userDenied: return "User denied camera access"
            case .restricted: return "Camera access is restricted (e.g. parental controls)"
            case .noCamera: return "No camera device available"
            }
        }
    }

    public static func currentStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    /// Returns true when access granted; throws if denied or restricted.
    public static func request() async throws -> Bool {
        switch currentStatus() {
        case .authorized:
            return true
        case .denied:
            throw CameraError.userDenied
        case .restricted:
            throw CameraError.restricted
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        }
    }
}
