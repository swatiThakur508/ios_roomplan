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
  private var processingOverlay: UIView?
  private var completion: FlutterResult?
  private var lastRoom: CapturedRoom?
  private var capturedRooms: [CapturedRoom] = []
  private var roomStartTimes: [Date] = []
  private var structureTask: Task<Void, Never>?
  private var roomProcessingTimeout: DispatchWorkItem?
  private var startedAt: Date?
  private var lastUpdateEmittedAt = Date.distantPast
  private var cancelled = false
  private var multiRoomEnabled = false
  private var processingRoom = false
  private var roomResultHandled = false
  private let sessionControlQueue = DispatchQueue(label: "ios_roomplan.session-control", qos: .userInitiated)

  private override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleMemoryWarning),
      name: UIApplication.didReceiveMemoryWarningNotification,
      object: nil
    )
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  required init?(coder: NSCoder) { fatalError("RoomPlan controller is not decoded from a storyboard.") }
  func encode(with coder: NSCoder) {}

  static var supported: Bool {
    if #available(iOS 16.0, *) { return RoomCaptureSession.isSupported }
    return false
  }

  static var multiRoomSupported: Bool {
    if #available(iOS 17.0, *) { return RoomCaptureSession.isSupported }
    return false
  }

  func startSession(result: @escaping FlutterResult, multiRoom: Bool = false) {
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
      if multiRoom && !Self.multiRoomSupported {
        result(FlutterError(code: "unsupported_version", message: "Multi-room scanning requires iOS 17 or later and a supported RoomPlan device.", details: nil))
        return
      }
      multiRoomEnabled = multiRoom
      capturedRooms.removeAll(keepingCapacity: false)
      roomStartTimes.removeAll(keepingCapacity: false)
      lastUpdateEmittedAt = .distantPast
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
    processingRoom = false
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
    screen.navigationItem.title = multiRoomEnabled ? "Scan room 1" : "Scan room"
    screen.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelCapture))
    screen.navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: multiRoomEnabled ? "Finish Room" : "Done",
      style: .done,
      target: self,
      action: #selector(finishCapture)
    )
    let navigation = UINavigationController(rootViewController: screen)
    navigation.modalPresentationStyle = .fullScreen
    captureScreen = navigation
    presenter.present(navigation, animated: true) { [weak self] in
      guard let self else { return }
      scannerView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }
  }

  @objc private func finishCapture() {
    guard !processingRoom else { return }
    guard let session = captureView?.captureSession else { return }
    processingRoom = true
    roomResultHandled = false
    roomProcessingTimeout?.cancel()
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, processingRoom, completion != nil else { return }
      handleRoomProcessingError(NSError(
        domain: "RoomPlan",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Room processing did not finish within 90 seconds."]
      ))
    }
    roomProcessingTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)
    if let roomScreen = (captureScreen as? UINavigationController)?.viewControllers.first {
      roomScreen.navigationItem.title = "Processing room…"
      roomScreen.navigationItem.rightBarButtonItem?.isEnabled = false
    }
    if multiRoomEnabled { showProcessingOverlay() }
    if multiRoomEnabled, #available(iOS 17.0, *) {
      sessionControlQueue.async { session.stop(pauseARSession: false) }
    } else {
      sessionControlQueue.async { session.stop() }
    }
  }

  @objc private func cancelCapture() {
    cancelled = true
    finish(nil)
  }

  func stopSession(result: @escaping FlutterResult) {
    onMain { [weak self] in
      guard let self, captureView != nil else {
        result(FlutterError(code: "session_not_running", message: "There is no active room scan.", details: nil))
        return
      }
      cancelled = true
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
    // RoomPlan can emit updates rapidly. The Flutter page only needs a light
    // progress stream; throttling avoids repeatedly encoding large structures.
    let now = Date()
    guard now.timeIntervalSince(lastUpdateEmittedAt) >= 0.5 else { return }
    lastUpdateEmittedAt = now
    do {
      let text = try IosRoomPlanJSONConverter.encode(room: room, startedAt: startedAt, lidar: true)
      DispatchQueue.main.async { sink(text) }
    } catch {
      DispatchQueue.main.async { sink(FlutterError(code: "serialization_error", message: "Could not encode scan progress.", details: error.localizedDescription)) }
    }
  }

  func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
    // Multi-room scans process the raw result through RoomBuilder in the
    // session delegate. This avoids relying on RoomCaptureView's approval
    // presentation between runs of the same capture session.
    !multiRoomEnabled
  }

  func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
    onMain { [weak self] in
      self?.handleProcessedRoom(processedResult, error: error)
    }
  }

  func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
    guard multiRoomEnabled, !cancelled else { return }
    if let error {
      onMain { [weak self] in
        self?.handleRoomProcessingError(error)
      }
      return
    }
    Task { [weak self] in
      do {
        let builder = RoomBuilder(options: [.beautifyObjects])
        let room = try await builder.capturedRoom(from: data)
        guard !Task.isCancelled else { return }
        self?.onMain { [weak self] in
          self?.handleProcessedRoom(room, error: nil)
        }
      } catch {
        self?.onMain { [weak self] in
          self?.handleRoomProcessingError(error)
        }
      }
    }
  }

  private func handleProcessedRoom(_ room: CapturedRoom, error: Error?) {
    guard !cancelled, completion != nil, !roomResultHandled else { return }
    hideProcessingOverlay()
    roomResultHandled = true
    roomProcessingTimeout?.cancel()
    roomProcessingTimeout = nil
    processingRoom = false
    if let error {
      handleRoomProcessingError(error)
      return
    }
    lastRoom = room
    if multiRoomEnabled {
      capturedRooms.append(room)
      roomStartTimes.append(startedAt ?? Date())
      showRoomCompletionChoices()
      return
    }
    do {
      let text = try IosRoomPlanJSONConverter.encode(room: room, startedAt: startedAt, lidar: true)
      finish(text)
    } catch {
      finish(FlutterError(code: "serialization_error", message: "Could not encode the completed scan.", details: error.localizedDescription))
    }
  }

  private func handleRoomProcessingError(_ error: Error) {
    hideProcessingOverlay()
    roomResultHandled = true
    roomProcessingTimeout?.cancel()
    roomProcessingTimeout = nil
    processingRoom = false
    cancelled = true
    finish(FlutterError(code: "processing_failed", message: "RoomPlan could not process the scan.", details: error.localizedDescription))
  }

  private func showRoomCompletionChoices() {
    guard let presenter = captureScreen else {
      finish(FlutterError(code: "ui_error", message: "The room scan screen is no longer available.", details: nil))
      return
    }
    let alert = UIAlertController(
      title: "Room \(capturedRooms.count) is ready",
      message: "Add another connected room or finish your 3D structure.",
      preferredStyle: .actionSheet
    )
    alert.addAction(UIAlertAction(title: "Scan Another Room", style: .default) { [weak self] _ in
      self?.startNextRoom()
    })
    alert.addAction(UIAlertAction(title: "Finish 3D Structure", style: .default) { [weak self] _ in
      self?.finishStructure()
    })
    alert.addAction(UIAlertAction(title: "Cancel Structure", style: .cancel) { [weak self] _ in
      guard let self else { return }
      cancelled = true
      finish(nil)
    })
    if let popover = alert.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }
    presenter.present(alert, animated: true)
  }

  private func startNextRoom() {
    guard let captureView, let screen = captureScreen as? UINavigationController,
          let roomScreen = screen.viewControllers.first else { return }
    startedAt = Date()
    hideProcessingOverlay()
    roomScreen.navigationItem.title = "Scan room \(capturedRooms.count + 1)"
    roomScreen.navigationItem.rightBarButtonItem?.isEnabled = true
    processingRoom = false
    roomResultHandled = false
    roomProcessingTimeout?.cancel()
    roomProcessingTimeout = nil
    if #available(iOS 17.0, *) {
      captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    } else {
      finish(FlutterError(code: "unsupported_version", message: "Multi-room scanning requires iOS 17 or later.", details: nil))
    }
  }

  private func finishStructure() {
    guard #available(iOS 17.0, *) else {
      finish(FlutterError(code: "unsupported_version", message: "Multi-room scanning requires iOS 17 or later.", details: nil))
      return
    }
    guard !capturedRooms.isEmpty else {
      finish(FlutterError(code: "no_capture", message: "Finish at least one room before finishing the structure.", details: nil))
      return
    }
    guard let navigation = captureScreen as? UINavigationController,
          let roomScreen = navigation.viewControllers.first else {
      finish(FlutterError(code: "ui_error", message: "The room scan screen is no longer available.", details: nil))
      return
    }
    roomScreen.navigationItem.rightBarButtonItem?.isEnabled = false
    roomScreen.navigationItem.title = "Building structure…"

    let rooms = capturedRooms
    let startTimes = roomStartTimes
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Structure-\(UUID().uuidString).usdz")
    structureTask = Task { [weak self] in
      guard let self else { return }
      do {
        let builder = StructureBuilder(options: [.beautifyObjects])
        let structure = try await builder.capturedStructure(from: rooms)
        guard !Task.isCancelled else { return }
        guard structure.rooms.count == rooms.count else {
          throw NSError(
            domain: "RoomPlan",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "The merged structure contains \(structure.rooms.count) of \(rooms.count) captured rooms."]
          )
        }
        // Mesh export keeps every room's wall surfaces and openings visible in
        // Quick Look. Parametric exports remain available for single-room use.
        try structure.export(to: url, exportOptions: .mesh)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else {
          throw NSError(domain: "RoomPlan", code: 1, userInfo: [NSLocalizedDescriptionKey: "RoomPlan exported an empty structure model."])
        }
        let payloads = try structure.rooms.enumerated().map { index, room in
          IosRoomPlanJSONConverter.dictionary(
            room: room,
            startedAt: index < startTimes.count ? startTimes[index] : nil,
            lidar: true
          )
        }
        onMain {
          guard self.completion != nil, !self.cancelled else {
            try? FileManager.default.removeItem(at: url)
            return
          }
          self.finish(["rooms": payloads, "modelPath": url.path])
        }
      } catch {
        try? FileManager.default.removeItem(at: url)
        onMain {
          guard self.completion != nil, !self.cancelled else { return }
          self.finish(FlutterError(code: "structure_failed", message: "RoomPlan could not merge these rooms. Scan connected rooms without interrupting tracking, then try again.", details: error.localizedDescription))
        }
      }
    }
  }

  func captureSession(_ session: RoomCaptureSession, didFailWith error: Error) {
    onMain { [weak self] in
      guard let self, !cancelled else { return }
      finish(FlutterError(code: "scan_failed", message: "RoomPlan capture failed.", details: error.localizedDescription))
    }
  }

  @objc private func handleMemoryWarning() {
    onMain { [weak self] in
      guard let self, completion != nil else { return }
      cancelled = true
      structureTask?.cancel()
      finish(FlutterError(
        code: "memory_pressure",
        message: "The device is low on memory. The scan was stopped safely; close other apps and try a smaller structure.",
        details: nil
      ))
    }
  }

  private func finish(_ value: Any?) {
    let callback = completion
    completion = nil
    structureTask?.cancel()
    structureTask = nil
    roomProcessingTimeout?.cancel()
    roomProcessingTimeout = nil
    hideProcessingOverlay()
    // Multi-room scans intentionally keep ARKit running between room captures.
    // Pause it when the whole structure finishes before releasing RoomCaptureView.
    if let session = captureView?.captureSession {
      sessionControlQueue.async { session.stop() }
    }
    captureView?.captureSession.delegate = nil
    captureView?.delegate = nil
    captureView = nil
    capturedRooms.removeAll(keepingCapacity: false)
    roomStartTimes.removeAll(keepingCapacity: false)
    if multiRoomEnabled { lastRoom = nil }
    let screen = captureScreen
    captureScreen = nil
    screen?.dismiss(animated: true)
    callback?(value)
  }

  private func showProcessingOverlay() {
    showStatusOverlay(title: "Processing room…", detail: "Building the room model")
  }

  private func showStatusOverlay(title titleText: String, detail detailText: String) {
    guard processingOverlay == nil,
          let screen = (captureScreen as? UINavigationController)?.viewControllers.first else { return }

    let overlay = UIView()
    overlay.translatesAutoresizingMaskIntoConstraints = false
    overlay.backgroundColor = UIColor.black.withAlphaComponent(0.34)
    overlay.alpha = 0

    let card = UIView()
    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = UIColor(red: 0.07, green: 0.15, blue: 0.19, alpha: 0.97)
    card.layer.cornerRadius = 24
    card.layer.borderWidth = 1
    card.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor

    let spinner = UIActivityIndicatorView(style: .large)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.color = .white
    spinner.startAnimating()

    let title = UILabel()
    title.translatesAutoresizingMaskIntoConstraints = false
    title.text = titleText
    title.textColor = .white
    title.font = .systemFont(ofSize: 17, weight: .semibold)
    title.textAlignment = .center

    let detail = UILabel()
    detail.translatesAutoresizingMaskIntoConstraints = false
    detail.text = detailText
    detail.textColor = UIColor.white.withAlphaComponent(0.74)
    detail.font = .systemFont(ofSize: 13, weight: .regular)
    detail.textAlignment = .center

    screen.view.addSubview(overlay)
    overlay.addSubview(card)
    card.addSubview(spinner)
    card.addSubview(title)
    card.addSubview(detail)
    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: screen.view.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: screen.view.trailingAnchor),
      overlay.topAnchor.constraint(equalTo: screen.view.topAnchor),
      overlay.bottomAnchor.constraint(equalTo: screen.view.bottomAnchor),
      card.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
      card.widthAnchor.constraint(equalToConstant: 260),
      card.heightAnchor.constraint(equalToConstant: 190),
      spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
      title.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
      title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
      detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
      detail.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
      detail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
    ])
    processingOverlay = overlay
    UIView.animate(withDuration: 0.2) { overlay.alpha = 1 }
  }

  private func hideProcessingOverlay() {
    guard let overlay = processingOverlay else { return }
    processingOverlay = nil
    UIView.animate(withDuration: 0.18, animations: { overlay.alpha = 0 }) { _ in
      overlay.removeFromSuperview()
    }
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
