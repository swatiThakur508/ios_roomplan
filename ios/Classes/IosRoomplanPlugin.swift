import Flutter
import QuickLook
import UIKit
import RoomPlan

public final class IosRoomplanPlugin: NSObject, FlutterPlugin {
  private var quickLook: QLPreviewController?
  // QLPreviewController keeps its data source weakly. Retain the source for
  // at least as long as the presented viewer, or Quick Look has no item to show.
  private var previewSource: PreviewFileSource?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methods = FlutterMethodChannel(
      name: "ios_roomplan/method_channel",
      binaryMessenger: registrar.messenger()
    )
    let plugin = IosRoomplanPlugin()
    registrar.addMethodCallDelegate(plugin, channel: methods)

    let events = FlutterEventChannel(
      name: "ios_roomplan/event_channel",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(IosRoomPlanController.shared)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(IosRoomPlanController.supported)
    case "isMultiRoomSupported":
      result(IosRoomPlanController.multiRoomSupported)
    case "startRoomCapture":
      IosRoomPlanController.shared.startSession(result: result)
    case "startMultiRoomCapture":
      IosRoomPlanController.shared.startSession(result: result, multiRoom: true)
    case "stopRoomCapture":
      IosRoomPlanController.shared.stopSession(result: result)
    case "exportLastCapture":
      IosRoomPlanController.shared.exportLastCapture(result: result)
    case "previewModel", "previewFloorPlan":
      preview(call, result: result)
    case "shareFile":
      share(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func preview(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "A file path is required.", details: nil))
      return
    }
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "file_not_found", message: "The requested preview file does not exist.", details: path))
      return
    }
    if call.method == "previewFloorPlan" && fileURL.pathExtension.lowercased() != "pdf" {
      result(FlutterError(code: "invalid_file", message: "The floor plan preview expects a PDF file.", details: nil))
      return
    }
    guard var presenter = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?.rootViewController else {
      result(FlutterError(code: "no_presenter", message: "No active screen is available for preview.", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let viewer = QLPreviewController()
    let source = PreviewFileSource(url: fileURL)
    previewSource = source
    viewer.dataSource = source
    quickLook = viewer
    presenter.present(viewer, animated: true) { result(nil) }
  }

  private func share(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "A file path is required.", details: nil))
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "file_not_found", message: "The file to share does not exist.", details: path))
      return
    }
    guard var presenter = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?.rootViewController else {
      result(FlutterError(code: "no_presenter", message: "No active screen is available for sharing.", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }

    let fileURL = URL(fileURLWithPath: path)
    let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }
    activity.completionWithItemsHandler = { _, completed, _, error in
      if let error {
        result(FlutterError(code: "share_failed", message: "Could not share the file.", details: error.localizedDescription))
      } else {
        result(completed)
      }
    }
    presenter.present(activity, animated: true)
  }
}

private final class PreviewFileSource: NSObject, QLPreviewControllerDataSource {
  private let url: URL
  init(url: URL) { self.url = url }
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    url as NSURL
  }
}
