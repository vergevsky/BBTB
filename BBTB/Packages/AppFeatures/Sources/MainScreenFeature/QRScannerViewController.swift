#if os(iOS)
import UIKit
import AVFoundation

/// IMP-02 / RESEARCH §8.4 — iOS UIKit ViewController hosting AVCaptureSession.
final class QRScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var onScan: ((String) -> Void)?
    private var hasScanned = false

    convenience init(onScan: @escaping (String) -> Void) {
        self.init(nibName: nil, bundle: nil)
        self.onScan = onScan
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
        else { return }

        if session.canAddInput(videoInput) { session.addInput(videoInput) }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.layer.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = readable.stringValue
        else { return }
        hasScanned = true
        session.stopRunning()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        DispatchQueue.main.async { [weak self] in
            self?.onScan?(value)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }
}
#endif

#if os(macOS)
import AppKit
import AVFoundation

/// IMP-02 / RESEARCH §8.5 — macOS NSView hosting AVCaptureSession.
final class QRScannerNSView: NSView, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var onScan: ((String) -> Void)?
    private var hasScanned = false

    init(onScan: @escaping (String) -> Void) {
        super.init(frame: .zero)
        self.onScan = onScan
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        setupSession()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setupSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
        else { return }

        if session.canAddInput(videoInput) { session.addInput(videoInput) }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = bounds
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = readable.stringValue
        else { return }
        hasScanned = true
        session.stopRunning()
        DispatchQueue.main.async { [weak self] in
            self?.onScan?(value)
        }
    }

    func stopSession() {
        if session.isRunning { session.stopRunning() }
    }
}
#endif
