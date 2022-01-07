import AVFoundation

class AVFoundationBarcodeScanner: NSObject, BarcodeScanner, AVCaptureMetadataOutputObjectsDelegate {
    typealias Barcode = AVMetadataMachineReadableCodeObject

    init(resultHandler: @escaping ResultHandler) {
        self.resultHandler = resultHandler
    }

    // Detections are handled by this function.
    var resultHandler: ResultHandler

    // Acts as an "on detection notifier"
    // for the Camera.
    var onDetection: (() -> Void)?

    private let output = AVCaptureMetadataOutput()
    private let metadataQueue = DispatchQueue(label: "fast_barcode_scanner.avfoundation_scanner.serial")
    private var _session: AVCaptureSession?
    private var _symbologies = [String]()
    private var isPaused = false

    var symbologies: [String] {
        get { _symbologies }
        set {
            _symbologies = newValue

            // This will just ignore all unsupported types
            output.metadataObjectTypes = newValue.compactMap { avMetadataObjectTypes[$0] }

            // UPC-A is reported as EAN-13
            if newValue.contains("upcA") && !output.metadataObjectTypes.contains(.ean13) {
                output.metadataObjectTypes.append(.ean13)
            }

            // Report to the user if any types are not supported
            if output.metadataObjectTypes.count != newValue.count {
                let unsupportedTypes = newValue.filter { avMetadataObjectTypes[$0] == nil }
                print("WARNING: Unsupported barcode types selected: \(unsupportedTypes)")
            }
        }
    }

    var session: AVCaptureSession? {
        get { _session }
        set {
            _session = newValue
            if let session = newValue, session.canAddOutput(output), !session.outputs.contains(output) {
                session.addOutput(output)
            }
        }
    }

    func start() {
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
    }

    func stop() {
        output.setMetadataObjectsDelegate(nil, queue: nil)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {

    // TODO: return all scanned codes
		guard
			let metadata = metadataObjects.first,
			let readableCode = metadata as? AVMetadataMachineReadableCodeObject,
            var type = flutterMetadataObjectTypes[readableCode.type],
            var value = readableCode.stringValue
        else { return }
        let transformedCode = PreviewViewFactory.preview?.videoPreviewLayer.transformedMetadataObject(for: readableCode) as? AVMetadataMachineReadableCodeObject

        // Fix UPC-A, see https://developer.apple.com/library/archive/technotes/tn2325/_index.html#//apple_ref/doc/uid/DTS40013824-CH1-IS_UPC_A_SUPPORTED_
        if readableCode.type == .ean13 {
            if value.hasPrefix("0") {
                // UPC-A
                guard symbologies.contains("upcA") else { return }
                type = "upcA"
                value.removeFirst()
            } else {
                // EAN-13
                guard symbologies.contains(type) else { return }
            }
        }

        onDetection?()

        resultHandler([type, value, nil, transformedCode?.corners.pointList])
	}
}

extension Array where Element == CGPoint {
    // convert bounding Rect to point list
    var pointList: [[Int]] {
        get {
            [
                [Int(self[0].x), Int(self[0].y)],
                [Int(self[1].x), Int(self[1].y)],
                [Int(self[2].x), Int(self[2].y)],
                [Int(self[3].x), Int(self[3].y)]
            ]
        }
    }
}
