import Foundation
import RoomPlan
import simd
import UIKit

/// Converts Apple's processed RoomPlan value into the plugin's transport format.
@available(iOS 16.0, *)
enum IosRoomPlanJSONConverter {
  static func encode(room: CapturedRoom, startedAt: Date?, lidar: Bool) throws -> String {
    let payload = dictionary(room: room, startedAt: startedAt, lidar: lidar)
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
    guard let text = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return text
  }

  static func dictionary(room: CapturedRoom, startedAt: Date?, lidar: Bool) -> [String: Any] {
    let elapsed = startedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
    return [
      "room": [
        "walls": room.walls.map(surface),
        "objects": room.objects.map(object),
        "doors": room.doors.map(surface),
        "windows": room.windows.map(surface),
        "openings": room.openings.map(surface),
      ],
      "metadata": [
        "session_duration": elapsed,
        "device_model": UIDevice.current.model,
        "has_lidar": lidar,
      ],
    ]
  }

  private static func surface(_ item: CapturedRoom.Surface) -> [String: Any] {
    [
      "uuid": item.identifier.uuidString,
      "category": String(describing: item.category),
      "dimensions": vector(item.dimensions),
      "transform": matrix(item.transform),
      "confidence": String(describing: item.confidence),
    ]
  }

  private static func object(_ item: CapturedRoom.Object) -> [String: Any] {
    [
      "uuid": item.identifier.uuidString,
      "category": String(describing: item.category),
      "dimensions": vector(item.dimensions),
      "transform": matrix(item.transform),
      "confidence": String(describing: item.confidence),
    ]
  }

  private static func vector(_ value: SIMD3<Float>) -> [String: Float] {
    ["x": value.x, "y": value.y, "z": value.z]
  }

  private static func matrix(_ value: simd_float4x4) -> [Float] {
    (0..<4).flatMap { column in (0..<4).map { row in value[column][row] } }
  }
}
