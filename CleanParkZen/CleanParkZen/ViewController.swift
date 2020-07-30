//
//  ViewController.swift
//  CleanParkZen
//
//  Created by Colin Hebert on 7/29/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import AVFoundation
import UserNotifications

class ViewController: UIViewController {
    
    // MARK: - Properties
    @IBOutlet weak var mapView: MKMapView!
    
    var geotifications: [Geotification] = []
    var locationManager = CLLocationManager()
    
    final let travelGeofenceIdentifier = "TRAVELGEO"
    
    enum LocationReason {
        case isNone
        case isDisconnectLocation
        case isTravelGeofence
    }
    public var locationReason: LocationReason = LocationReason.isNone
    
    // MARK: - viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        
        locationManager.startMonitoringSignificantLocationChanges()
        
        mapView.delegate = self
        
        mapView.showsUserLocation = true
        
        // Used for car connection (because most cars do not use BLE)
        let audioSession: AVAudioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay,])
            try audioSession.setActive(true)
        } catch {
            fatalError("Audio session failure")
        }
        
        // Runs the function ViewController:handleRouteChange() whenever a new audio device is found to have connected.  This only works in the foreground or background, but not suspended.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRouteChange),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: AVAudioSession.sharedInstance())
        
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sendingToBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        
        
    }
    
    @objc func sendingToBackground() {
        locationReason = .isTravelGeofence
    }
    
    // MARK: - AV Handler
    // This is called whenever a new audio route (another device to play music on) is connected to the iPhone, called by the Observer in Initialization.
    @objc func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else {
                return
        }
        switch reason {
        case .newDeviceAvailable:
            let session = AVAudioSession.sharedInstance()
            for output in session.currentRoute.outputs {
                print("New audio port: " + output.portName)
                print("Port type: " + output.portType.rawValue)
                // If the output is a HFP (Hands Free Profile), prompt the user to select it as a new car.
                if output.portType == .bluetoothHFP {
                    DispatchQueue.main.async {
                        notify(withMessage: "Possible new car detected. Would you like to set this as your car?")
                    }
                }
            }
        case .oldDeviceUnavailable:
            if let previousRoute =
                userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                for output in previousRoute.outputs {
                    // Saves current location when the previous audio device is disconnected.
                    print("Disconnected port: " + output.portName)
                    print("Disconnected type: " + output.portType.rawValue)
                    DispatchQueue.main.async {
                        notify(withMessage: "Parking location saved! (AV)")
                    }
                }
            }
        default: ()
        }
    }
    
    func startTravelGeofencing(location: CLLocation) {
        let radius = abs(location.speed * 20)
        
        let geotification = Geotification(coordinate: location.coordinate, radius: radius, identifier: travelGeofenceIdentifier, note: "", eventType: .onExit)
        add(geotification)
        startMonitoring(geotification: geotification)
        saveAllGeotifications()
    }
    
    func add(_ geotification: Geotification) {
        geotifications.append(geotification)
        mapView.addAnnotation(geotification)
        addRadiusOverlay(forGeotification: geotification)
    }
    
    func remove(_ geotification: Geotification) {
        guard let index = geotifications.firstIndex(of: geotification) else { return }
        geotifications.remove(at: index)
        mapView.removeAnnotation(geotification)
        removeRadiusOverlay(forGeotification: geotification)
    }
    
    func region(with geotification: Geotification) -> CLCircularRegion {
        let region = CLCircularRegion(center: geotification.coordinate, radius: geotification.radius, identifier: geotification.identifier)
        region.notifyOnEntry = (geotification.eventType == .onEntry)
        region.notifyOnExit = !region.notifyOnEntry
        return region
    }
    
    func startMonitoring(geotification: Geotification) {
        if !CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
            notify(withMessage: "Oof")
            return
        }
        
        if CLLocationManager.authorizationStatus() != .authorizedAlways {
            let message = """
        Your geotification is saved but will only be activated once you grant
        Geotify permission to access the device location.
        """
            notify(withMessage: message)
        }
        
        let fenceRegion = region(with: geotification)
        locationManager.startMonitoring(for: fenceRegion)
    }
    
    func stopMonitoring(geotification: Geotification) {
        for region in locationManager.monitoredRegions {
            guard let circularRegion = region as? CLCircularRegion, circularRegion.identifier == geotification.identifier else { continue }
            locationManager.stopMonitoring(for: circularRegion)
        }
    }
    
    // MARK: Map overlay functions
    func addRadiusOverlay(forGeotification geotification: Geotification) {
        mapView?.addOverlay(MKCircle(center: geotification.coordinate, radius: geotification.radius))
    }
    
    func removeRadiusOverlay(forGeotification geotification: Geotification) {
        // Find exactly one overlay which has the same coordinates & radius to remove
        guard let overlays = mapView?.overlays else { return }
        for overlay in overlays {
            guard let circleOverlay = overlay as? MKCircle else { continue }
            let coord = circleOverlay.coordinate
            if coord.latitude == geotification.coordinate.latitude && coord.longitude == geotification.coordinate.longitude && circleOverlay.radius == geotification.radius {
                mapView?.removeOverlay(circleOverlay)
                break
            }
        }
    }
    
    // MARK: Loading and saving functions
    func loadAllGeotifications() {
        geotifications.removeAll()
        saveAllGeotifications()
    }
    
    func saveAllGeotifications() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(geotifications)
            UserDefaults.standard.set(data, forKey: "savedGeos")
        } catch {
            print("error encoding geotifications")
        }
    }
    
}


// MARK: - MapView Delegate
extension ViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let identifier = "myGeotification"
        if annotation is Geotification {
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKPinAnnotationView
            if annotationView == nil {
                annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
                let removeButton = UIButton(type: .custom)
                removeButton.frame = CGRect(x: 0, y: 0, width: 23, height: 23)
                annotationView?.leftCalloutAccessoryView = removeButton
            } else {
                annotationView?.annotation = annotation
            }
            return annotationView
        }
        return nil
    }
    
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKCircle {
            let circleRenderer = MKCircleRenderer(overlay: overlay)
            circleRenderer.lineWidth = 1.0
            circleRenderer.strokeColor = .purple
            circleRenderer.fillColor = UIColor.purple.withAlphaComponent(0.4)
            return circleRenderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        // Delete geotification
        let geotification = view.annotation as! Geotification
        remove(geotification)
        saveAllGeotifications()
    }
    
    
    
}


// MARK: - Location Manager Delegate
extension ViewController: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        mapView.showsUserLocation = status == .authorizedAlways
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region is CLCircularRegion {
            if region.identifier == travelGeofenceIdentifier {
                for geo in geotifications {
                    if geo.identifier == region.identifier {
                        stopMonitoring(geotification: geo)
                        remove(geo)
                        geotifications.removeAll(where: {$0.identifier == geo.identifier})
                    }
                }
                saveAllGeotifications()
                locationReason = .isTravelGeofence
                locationManager.requestLocation()
                
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if locationReason == .isTravelGeofence {
            locationReason = .isNone
            if locations.last != nil {
                startTravelGeofencing(location: locations.last!)
            }
            return
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with the following error: \(error)")
    }
}


func notify(withMessage msg: String) {
    let notificationContent = UNMutableNotificationContent()
    notificationContent.body = msg
    notificationContent.sound = UNNotificationSound.default
    notificationContent.badge = UIApplication.shared.applicationIconBadgeNumber + 1 as NSNumber
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: "location_change",
                                        content: notificationContent,
                                        trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error: \(error)")
        }
    }
}
