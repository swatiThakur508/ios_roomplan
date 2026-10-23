import AVFoundation
import Flutter
import RoomPlan
import UIKit

/// Owns one RoomPlan capture session and its Flutter callbacks.
@available(iOS 16.0, *)
final class IosRoomPlanController: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, FlutterStreamHandler {
  static let shared = IosRoomPlanController()

  private var eventSink: FlutterEventSink?
  private var captureView: RoomCaptureView?
  private var captureScreen: UIViewController?
  private var completion: FlutterResult?
  private var lastRoom: CapturedRoom?
  private var startedAt: Date?
  private var cancelled = false

  private override init() {}

  required init?(coder: NSCoder) { fatalError("RoomPlan controller is not decoded from a storyboard.") }
  func encode(with coder: NSCoder) {}

  static var supported: Bool {
    if #available(iOS 16.0, *) { return RoomCaptureSession.isSupported }
    return false
  }

  func startSession(result: @escaping FlutterResult) {
    onMain { [weak self] in
      guard let self else { return }
      guard completion == nil else {
        result(FlutterError(code: "session_in_progress", message: "A room scan is already active.", details: nil))
        return
      }
      guard Self.supported else {
        result(FlutterError(code: "not_available", message: "RoomPlan requires a supported LiDAR device and iOS 16 or later.", details: nil))
        return
      }
      completion = result
      requestCameraPermission { [weak self] granted in
        guard let self, completion != nil else { return }
        guard granted else {
          finish(FlutterError(code: "camera_permission_denied", message: "Allow camera access in Settings to scan a room.", details: nil))
          return
        }
        presentCapture()
      }
    }
  }

  private func requestCameraPermission(_ done: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: done(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { allowed in DispatchQueue.main.async { done(allowed) } }
    default: done(false)
    }
  }

  private func presentCapture() {
    guard let presenter = activeViewController() else {
      finish(FlutterError(code: "ui_error", message: "No active screen is available to present the scan.", details: nil))
      return
    }
    cancelled = false
    lastRoom = nil
    startedAt = Date()
    let scannerView = RoomCaptureView(frame: .zero)
    scannerView.delegate = self
    scannerView.captureSession.delegate = self
    captureView = scannerView

    let screen = UIViewController()
    screen.view.backgroundColor = .black
    screen.view.addSubview(scannerView)
    scannerView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scannerView.leadingAnchor.constraint(equalTo: screen.view.leadingAnchor),
      scannerView.trailingAnchor.constraint(equalTo: screen.view.trailingAnchor),
      scannerView.topAnchor.constraint(equalTo: screen.view.topAnchor),
      scannerView.bottomAnchor.constraint(equalTo: screen.view.bottomAnchor),
    ])
    screen.navigationItem.title = "Scan room"
    screen.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelCapture))
    screen.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(finishCapture))
    let navigation = UINavigationController(rootViewController: screen)
    navigation.modalPresentationStyle = .fullScreen
    captureScreen = navigation
    presenter.present(navigation, animated: true) { [weak self] in
      guard let self else { return }
      scannerView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }
  }

  @objc private func finishCapture() { captureView?.captureSession.stop() }

  @objc private func cancelCapture() {
    cancelled = true
    captureView?.captureSession.stop()
    finish(nil)
  }

  func stopSession(result: @escaping FlutterResult) {
    onMain { [weak self] in
      guard let self, captureView != nil else {
        result(FlutterError(code: "session_not_running", message: "There is no active room scan.", details: nil))
        return
      }
      cancelled = true
      captureView?.captureSession.stop()
      finish(FlutterError(code: "CANCELED", message: "Room scan cancelled.", details: nil))
      result(nil)
    }
  }

  func exportLastCapture(result: @escaping FlutterResult) {
    guard let lastRoom else {
      result(FlutterError(code: "no_capture", message: "Complete a scan before exporting a model.", details: nil))
      return
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Room-\(UUID().uuidString).usdz")
    do {
      try lastRoom.export(to: url, exportOptions: .parametric)
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size > 0 else { throw NSError(domain: "RoomPlan", code: 1, userInfo: [NSLocalizedDescriptionKey: "RoomPlan exported an empty model."]) }
      result(url.path)
    } catch {
      try? FileManager.default.removeItem(at: url)
      result(FlutterError(code: "export_failed", message: "Could not export the 3D model.", details: error.localizedDescription))
    }
  }

  func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
    lastRoom = room
    guard let sink = eventSink else { return }
    do {
      let text = try IosRoomPlanJSONConverter.encode(room: room, startedAt: startedAt, lidar: true)
      DispatchQueue.main.async { sink(text) }
    } catch {
      DispatchQueue.main.async { sink(FlutterError(code: "serialization_error", message: "Could not encode scan progress.", details: error.localizedDescription)) }
    }
  }

  func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

  func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
    onMain { [weak self] in
      guard let self, !cancelled else { return }
      if let error {
        finish(FlutterError(code: "processing_failed", message: "RoomPlan could not process the scan.", details: error.localizedDescription))
        return
      }
      lastRoom = processedResult
      do {
        let text = try IosRoomPlanJSONConverter.encode(room: processedResult, startedAt: startedAt, lidar: true)
        finish(text)
      } catch {
        finish(FlutterError(code: "serialization_error", message: "Could not encode the completed scan.", details: error.localizedDescription))
      }
    }
  }

  func captureSession(_ session: RoomCaptureSession, didFailWith error: Error) {
    onMain { [weak self] in
      guard let self, !cancelled else { return }
      finish(FlutterError(code: "scan_failed", message: "RoomPlan capture failed.", details: error.localizedDescription))
    }
  }

  private func finish(_ value: Any?) {
    let callback = completion
    completion = nil
    captureView?.captureSession.delegate = nil
    captureView?.delegate = nil
    captureView = nil
    let screen = captureScreen
    captureScreen = nil
    screen?.dismiss(animated: true)
    callback?(value)
  }

  private func activeViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
    var current = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let shown = current?.presentedViewController { current = shown }
    return current
  }

  private func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
