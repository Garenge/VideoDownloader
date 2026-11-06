import CoreLocation
import Flutter
import Foundation

final class IosBackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
  private static let channelName = "videodownloader/ios_background_keep_alive"
  private let locationManager = CLLocationManager()
  private var isRunning = false

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    locationManager.distanceFilter = 1000
    locationManager.pausesLocationUpdatesAutomatically = false
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "KEEP_ALIVE_UNAVAILABLE", message: "后台保活模块已释放", details: nil))
        return
      }

      switch call.method {
      case "start":
        self.start()
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func start() {
    isRunning = true
    switch locationManager.authorizationStatus {
    case .authorizedAlways:
      locationManager.startUpdatingLocation()
      print("ios/Runner/IosBackgroundKeepAlive.swift#start: location updates started")
    case .notDetermined:
      locationManager.requestWhenInUseAuthorization()
      print("ios/Runner/IosBackgroundKeepAlive.swift#start: requesting when-in-use authorization")
    case .authorizedWhenInUse:
      locationManager.requestAlwaysAuthorization()
      print("ios/Runner/IosBackgroundKeepAlive.swift#start: requesting always authorization")
    default:
      print(
        "ios/Runner/IosBackgroundKeepAlive.swift#start: location authorization unavailable status=\(locationManager.authorizationStatus.rawValue)"
      )
    }
  }

  private func stop() {
    isRunning = false
    locationManager.stopUpdatingLocation()
    print("ios/Runner/IosBackgroundKeepAlive.swift#stop: location updates stopped")
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard isRunning else {
      return
    }

    switch manager.authorizationStatus {
    case .authorizedAlways:
      manager.startUpdatingLocation()
      print("ios/Runner/IosBackgroundKeepAlive.swift#locationManagerDidChangeAuthorization: always authorization granted")
    case .authorizedWhenInUse:
      manager.requestAlwaysAuthorization()
      print("ios/Runner/IosBackgroundKeepAlive.swift#locationManagerDidChangeAuthorization: requesting always authorization")
    default:
      print(
        "ios/Runner/IosBackgroundKeepAlive.swift#locationManagerDidChangeAuthorization: authorization not granted status=\(manager.authorizationStatus.rawValue)"
      )
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      return
    }
    print(
      "ios/Runner/IosBackgroundKeepAlive.swift#didUpdateLocations: accuracy=\(location.horizontalAccuracy)"
    )
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print(
      "ios/Runner/IosBackgroundKeepAlive.swift#didFailWithError: location update failed error=\(error.localizedDescription)"
    )
  }
}
