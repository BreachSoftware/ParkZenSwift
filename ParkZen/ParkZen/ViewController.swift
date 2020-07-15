//
//  ViewController.swift
//  ParkZen
//
//  Created by Colin Hebert on 4/2/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//


import UIKit
import CoreLocation
import MapKit
import CoreMotion
import BackgroundTasks
import UserNotifications
import CoreBluetooth
import ExternalAccessory
import SwiftUI
import AVFoundation


class ViewController: UIViewController {
    
    @IBOutlet weak var latitudeLabel: UILabel!
    @IBOutlet weak var longitudeLabel: UILabel!
    @IBOutlet weak var activitiesLabel: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var scrollView: UIScrollView!
    
    final var mostRecentSavedLocationKey = "RECENTLOC"
    final var fakeDatabaseSavedLocationsKey = "FAKEDATABASELOCATIONS"
    final let savedBLEConnectedDevicesKey = "SAVEDBLEDEVICES"
    final let savedAVConnectedDevicesKey = "SAVEDAVDEVICES"
    final let travelGeofenceIdentifier = "TRAVELGEOFENCE"
    
    
    // MARK: Properties
    
    // Manages all location interaction.
    var locationManager: CLLocationManager = CLLocationManager()
    
    let activityManager: CMMotionActivityManager = CMMotionActivityManager()
    
    let accessoryManager: EAAccessoryManager = EAAccessoryManager.shared()
    
    var geotifications: [Geotification] = []
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    let expTime = 60.0
    
    // Struct for holding the previous activity's data.
    struct Activity {
        var id: String = "unknown"
        // Confidence value (0, 1, or 2) of how sure the system is of the activity.  2 is highest.
        var conf: Int = 0
    }
    
    // A switch with a label.
    struct SumoSwitch {
        // Label with name of the peripheral.
        var label: UILabel = UILabel()
        // Switch to turn connection to peripheral on or off.
        var uiSwitch: UISwitch = UISwitch()
        // Saved device data (either a Peripheral or AVDevice)
        var deviceData: ConnectedDevice = ConnectedDevice()
    }
    
    
    
    // Struct for saving most recent parked location coordinates so it's encodable.
    // I actually don't think this is the way to do this, but my only other idea is to create
    // an entire class that is encodable and writing an encode() function like in Geotification.swift,
    // but jeez that seems like a whole lot of sweat for something that doesn't help anything as far
    // as I can tell, so I'm leaving it like this for now.
    
    // For bluetooth management
    var centralManager: CBCentralManager!
    
    // Strictly for testing.  This will be pulled from wherever we want to geofence.
    let lsuCoords: CLLocation = CLLocation(latitude: 30.4133, longitude: -91.1800)
    //30.381521, -91.206449
    let stopSignCoords: CLLocation = CLLocation(latitude: 30.403832, longitude: -91.166370)
    
    var previousActivity: Activity = Activity()
    
    // Holds the most recent location received from LocationManager()
    var recentLocation: CLLocation = CLLocation()
    
    // True immediately after it gets the first location data so that the map is only moved once.
    // Maybe this can be removed if animateMap() is moved to viewDidLoad() if a location can be received on load?
    var initialized: Bool = false;
    
    // This is probably not the best way to do this!!
    // True only if this is a background refresh.
    //var isDisconnectLocation: Bool = false;
    enum LocationReason {
        case isNone
        case isDisconnectLocation
        case isTravelGeofence
    }
    
    // Whatever.
    public var locationReason: LocationReason = LocationReason.isNone
    
    // Also only for BG refresh, returns if location is found (so it can end the task).
    var gotLocationInBG: Bool = false;
    // Hey buddy pretty sure both of these are unused now.
    
    // Used to keep track of the label and switches on the scroll view.
    var deviceSwitches: [DeviceSwitch] = []
    
    // Use to keep track of connected peripherals.  God this is a mess.
    // TODO: clean up all the different ways that I'm saving peripherals.
    var connectedPeripherals: [CBPeripheral] = []
    

    
    //MARK: - Initialization
    override func viewDidLoad() {
        super.viewDidLoad()

        
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        locationManager.startMonitoringSignificantLocationChanges()
        
        mapView.delegate = self
        
        mapView.showsUserLocation = true
        
        
        
        let loc1 = SumoCoordinate(lat: 30.412630, lon: -91.177604)
        let loc2 = SumoCoordinate(lat: 30.412884, lon: -91.179256)
        let loc3 = SumoCoordinate(lat: 30.413668, lon: -91.179143)
        let loc4 = SumoCoordinate(lat: 30.413024, lon: -91.174954)
        
        DatabaseDelegate.shared.write(location: loc1)
        DatabaseDelegate.shared.write(location: loc2)
        DatabaseDelegate.shared.write(location: loc3)
        DatabaseDelegate.shared.write(location: loc4)
        
        DatabaseDelegate.shared.read(map: mapView)

        
        // Turns bluetooth management on.
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey : "restore.com.sumocode.parkzen", CBConnectPeripheralOptionEnableTransportBridgingKey : true])
        
        
        // Timer to increment the pins' timer once per minute.
        _ = Timer.scheduledTimer(timeInterval: expTime, target: self, selector: #selector(ViewController.incrementAnnotations), userInfo: nil, repeats: true)
        
        
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
        
        
        
        
        
        
        // TODO: Clean this up.  Right now, it removes all geofences then adds the LSU one back and saves it.  We just need to load the LSU one.  But because it is saved on the app, in order to change it when the app is rebuilt I just delete it and resave it.  So in the future.  Just remember this is dumb.
        // ALSO, this might totally mess stuff up with the TravelGeofences.
        geotifications.removeAll()
        saveAllGeotifications()
        if geotifications.count == 0 {
            let geotification = Geotification(coordinate: lsuCoords.coordinate, radius: 1000, identifier: "lsu", note: "Entered LSU", eventType: .onEntry)
            add(geotification)
            startMonitoring(geotification: geotification)
            let encoder = JSONEncoder()
            do {
                let data = try encoder.encode(geotifications)
                UserDefaults.standard.set(data, forKey: "savedItems")
            } catch {
                print("error encoding geotifications")
            }
        } else {
            loadAllGeotifications()
        }
        
        
        var savedPerifs: [ConnectedDevice] = getAllConnectedDevices()
        
        // Uncomment this to clear savedPerifs
        savedPerifs = []
        UserDefaults.standard.setStructArray(savedPerifs, forKey: savedBLEConnectedDevicesKey)
        UserDefaults.standard.setStructArray(savedPerifs, forKey: savedAVConnectedDevicesKey)
        
        // Loads all saved peripherals into the scroll view
        for perif in savedPerifs {
            createNewDeviceSelectComponent(device: perif)
        }
        
        // HERE MAX!  DO IT HERE
        let savedLocs: [SumoCoordinate] = UserDefaults.standard.structArrayData(SumoCoordinate.self, forKey: fakeDatabaseSavedLocationsKey)
        
        for loc in savedLocs {
            dropPin(CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude), "0 minutes", loc.timeCreated)
        }
        
        incrementAnnotations()
        
    }
    
    deinit {
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
                        self.notify(withMessage: "Possible new car detected. Would you like to set this as your car?")
                    }
                    
                }
                // Create a new Switch on the bluetooth select page.
                DispatchQueue.main.async {
                    self.createNewDeviceSelectComponent(device: AVDevice(name: output.portName, type: output.portType.rawValue, uid: output.uid, isConnected: false))
                    
                    //print("Anotha one")
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
                        self.notify(withMessage: "Parking location saved! (AV)")
                    }
                }
            }
        default: ()
        }
    }
    
    
    // MARK: - Bluetooth Switches
    
    // Returns all devices that have connected before in a heterogeneous array of ConnectedDevices
    func getAllConnectedDevices() -> [ConnectedDevice] {
        let AVArray: [AVDevice] = UserDefaults.standard.structArrayData(AVDevice.self, forKey: savedAVConnectedDevicesKey)
        let PerifArray: [Peripheral] = UserDefaults.standard.structArrayData(Peripheral.self, forKey: savedBLEConnectedDevicesKey)
        var ret: [ConnectedDevice] = AVArray
        ret.append(contentsOf: PerifArray)
        var ret2: [ConnectedDevice] = []
        // Adds all the isConnected devices to the front of the array, and all the non-connected devices to the end.
        for dev in ret {
            if dev.isConnected {
                ret2.insert(dev, at: 0)
            }
            else {
                ret2.append(dev)
            }
        }
        return ret2
    }
    
    
    func createNewDeviceSelectComponent(device: ConnectedDevice) {
        let newComponent = DeviceSwitch(device: device, y: 40*deviceSwitches.count)
        deviceSwitches.append(newComponent)
        scrollView.addSubview(newComponent)
        self.scrollView.contentSize = CGSize(width: Int(self.scrollView.visibleSize.width), height: 40*deviceSwitches.count)
    }

    
    @objc func switchStateDidChange(_ sender:UISwitch!)
    {
        // Finds the correct switch
        let which: DeviceSwitch = findWhichSwitch(sw: sender)!
        
        if (sender.isOn == true) {
            if which.device is Peripheral {
                let perif: Peripheral = which.device as! Peripheral
                // Grabs the first (and only) returned peripheral based on the UUID
                let activatedPeripheral = centralManager.retrievePeripherals(withIdentifiers: [perif.uuid!]).first
                if activatedPeripheral == nil {
                    print("Error: Device not available.")
                    return
                }
                print("Perif Name: " + activatedPeripheral!.name!)
                centralManager.connect(activatedPeripheral!, options: [:])
                centralManager.registerForConnectionEvents(options: [CBConnectionEventMatchingOption.peripheralUUIDs : [activatedPeripheral!.identifier]])
                centralManager.connect(activatedPeripheral!, options: nil)
                if !connectedPeripherals.contains(activatedPeripheral!) {
                    connectedPeripherals.append(activatedPeripheral!)
                }
                
                Peripheral.savePeripheralChanges(changedPeripheralID: activatedPeripheral!.identifier, isConnected: true)
            }
                
            else if which.device is AVDevice {
                let dev: AVDevice = which.device as! AVDevice
                AVDevice.saveAVDeviceChanges(changedAVDeviceName: dev.name, isConnected: true)
            }
        }
        else {
            if which.device is Peripheral {
                // If the switch is turned off and that device was a BLE perif, then disconnect from that perif.
                let perif: Peripheral = which.device as! Peripheral
                if connectedPeripherals.first(where: {$0.identifier == perif.uuid}) != nil {
                    print("Disconnected from \(perif.name)")
                    centralManager.cancelPeripheralConnection(connectedPeripherals.first(where: {$0.identifier == perif.uuid})!)
                }
                // Remove the perif from the connected list, and save it.
                connectedPeripherals.removeAll(where: {$0.identifier == perif.uuid})
                Peripheral.savePeripheralChanges(changedPeripheralID: perif.uuid!, isConnected: false)
            }
            else if which.device is AVDevice {
                // If the switch is turned off and
                let device: AVDevice = which.device as! AVDevice
                AVDevice.saveAVDeviceChanges(changedAVDeviceName: device.name, isConnected: false)
            }
        }
    }
    
    // Finds the perifSwitchComponent that corresponds to UISwitch sw.
    func findWhichSwitch(sw: UISwitch) -> DeviceSwitch? {
        for p in deviceSwitches {
            if p.uiSwitch == sw {
                return p
            }
        }
        return nil
    }
    
    // MARK: - Location and Pin Stuff
    // Increments the timer on all of the pins that are not the User Location.
    @objc func incrementAnnotations()
    {
        DatabaseDelegate.shared.read(map: mapView)

        let annotations = mapView.annotations
        for annotation: MKAnnotation in annotations {
            
            if annotation is SumoAnnotation {
                let timeStamp = (annotation as! SumoAnnotation).timeStamp
                
                // Calculates the age in minutes since the annotation has been created.
                let age = Int(round(Date().timeIntervalSince1970 - (annotation as! SumoAnnotation).timeStamp)/60)
                dropPin(annotation.coordinate, String(age) + " minute" + (age == 1 ? "" : "s"), timeStamp)
                mapView.removeAnnotation(annotation)
            }
        }
    }
    
    
    // Animates the map to orient it to the specified location.
    func animateMap(_ location: CLLocation) {
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        mapView.setRegion(region, animated: true)
    }
    
    
    // Creates and adds a pin to the map.
    func dropPin(_ coord: CLLocationCoordinate2D, _ title: String? = "0", _ timeStamp: Double? = Date().timeIntervalSince1970) {
        
        // let allAnnotations = self.mapView.annotations
        //self.mapView.removeAnnotations(allAnnotations)
        
        let myPin: SumoAnnotation = SumoAnnotation(sc: SumoCoordinate(coord: coord), title: title!)
        
        // Set the time stamp.
        myPin.timeStamp = timeStamp
        
        // Added pins to MapView.
        self.mapView.addAnnotation(myPin)
    }
    
    //MARK: - Activity Monitoring
    // Reports user activity on change.
    public func beginActivityMonitor() {
        print("Began monitoring activities...")
        activityManager.startActivityUpdates(to: .main) { (activity) in
            guard let activity = activity else {
                return
            }
            
            var modes: Set<String> = []
            if activity.stationary {
                modes.insert("stationary")
            }
            if activity.walking {
                modes.insert("walking")
            }
            if activity.running {
                modes.insert("running")
            }
            if activity.cycling {
                modes.insert("cycling")
            }
            if activity.automotive {
                modes.insert("driving")
            }
            if activity.unknown {
                modes.insert("unknown")
            }
            if modes.count == 0 {
                modes.insert("unknown")
            }
            
            self.activitiesLabel.text = modes.joined(separator: ", ")
            print(modes.joined(separator: ", "))
            self.notify()
            //self.registerBackgroundTask()
            
            switch UIApplication.shared.applicationState {
            case .active:
                print("We active")
            case .background:
                print("App is backgrounded.")
                print("Background time remaining = \(UIApplication.shared.backgroundTimeRemaining) seconds")
            case .inactive:
                break
            @unknown default:
                fatalError()
            }
            
            if(self.previousActivity.id == "driving" && self.previousActivity.conf != 0 && modes.first != "driving" && activity.confidence.rawValue != 0) {
                self.dropPin(self.recentLocation.coordinate)
                print("Dropped pin.")
            }
                // This is debug stuff
            else {
                self.activitiesLabel.text = (modes.first ?? "unknown") + String(activity.confidence.rawValue)
            }
            
            // Checks if the confidence is high enough to warrant a change in activity, then changes it.
            if activity.confidence.rawValue != 0 {
                self.previousActivity.id = (modes.first ?? "unknown")
                self.previousActivity.conf = activity.confidence.rawValue
            }
        }
    }
    
    public func stopActivityMonitor() {
        activityManager.stopActivityUpdates()
    }
    
    
    
    // MARK: - Geofence Handling
    func region(with geotification: Geotification) -> CLCircularRegion {
        let region = CLCircularRegion(center: geotification.coordinate, radius: geotification.radius, identifier: geotification.identifier)
        region.notifyOnEntry = (geotification.eventType == .onEntry)
        region.notifyOnExit = true
        return region
    }
    
    // Adds a geofence to the saved geofences, then adds it to the map (the map is just for testing).
    func add(_ geotification: Geotification) {
        geotifications.append(geotification)
        mapView.addAnnotation(geotification)
        mapView?.addOverlay(MKCircle(center: geotification.coordinate, radius: geotification.radius))
    }
    
    func remove(_ geotification: Geotification) {
        guard let index = geotifications.firstIndex(of: geotification) else { return }
        geotifications.remove(at: index)
        mapView.removeAnnotation(geotification)
        removeRadiusOverlay(forGeotification: geotification)
        //updateGeotificationsCount()
    }
    
    // Removes the overlay on the map for the specified geofence.
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
    
    
    func loadAllGeotifications() {
        geotifications.removeAll()
        let allGeotifications = Geotification.allGeotifications()
        allGeotifications.forEach { add($0) }
    }
    
    
    func saveAllGeotifications() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(geotifications)
            UserDefaults.standard.set(data, forKey: "savedItems")
        } catch {
            print("error encoding geotifications")
        }
    }
    
    
    func startMonitoring(geotification: Geotification) {
        if !CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
            showAlert(withTitle:"Error", message: "Geofencing is not supported on this device!")
            return
        }
        
        if CLLocationManager.authorizationStatus() != .authorizedAlways {
            let message = """
        Your geotification is saved but will only be activated once you grant
        Geotify permission to access the device location.
        """
            showAlert(withTitle:"Warning", message: message)
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
    
    func note(from identifier: String) -> String? {
        let geotifications = Geotification.allGeotifications()
        guard let matched = geotifications.filter({
            $0.identifier == identifier
        }).first else { return nil }
        return matched.note
    }
    
    func handleEvent(for region: CLRegion!) {
        //beginActivityMonitor()
    }
    
    func startTravelGeofencing(location: CLLocationCoordinate2D) {
        for geo in geotifications {
            if geo.identifier == travelGeofenceIdentifier {
                remove(geo)
            }
        }
        let geotification = Geotification(coordinate: location, radius: 300, identifier: travelGeofenceIdentifier, note: "", eventType: .onExit)
        add(geotification)
        startMonitoring(geotification: geotification)
        saveAllGeotifications()
    }
    
    //MARK: - Notifications
    func notify() {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.body = "Notif"
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
}

// MARK: - Map View Delegate
extension ViewController: MKMapViewDelegate {
    
    
    // Delegate method called when addAnnotation is done.
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        if !(annotation is SumoAnnotation) {
            return nil
        }
        
        let myPinIdentifier = "PinAnnotationIdentifier"
        
        // Generate pins.
        let myPinView = MKAnnotationView(annotation: annotation, reuseIdentifier: myPinIdentifier)
        
        // Decides which image to display based on the age of the pin.
        var imageName = ""
        let oldestAgeAllowed = 30 // minutes
        let increment = 4 // minutes between each range
        let age = Int(round(Date().timeIntervalSince1970 - (annotation as! SumoAnnotation).timeStamp)/60)
        // For me in the future: Yes, I know I could have done this in a super cool way, where you have a for loop that increases some integer value by 3 every loop and then increments some array of imageNames each time, but that is so hard to follow, so I'm writing it very simply for the sake of maintainability later on.
        if age >= 0 && age < increment {
            imageName = "ParkZen_Spot1_small"
        }
        else if age >= increment && age < increment*2 {
            imageName = "ParkZen_Spot2_small"
        }
        else if age >= increment*2 && age < increment*3 {
            imageName = "ParkZen_Spot3_small"
        }
        else if age >= increment*3 && age < increment*4 {
            imageName = "ParkZen_Spot4_small"
        }
        else if age >= increment*4 && age < increment*5 {
            imageName = "ParkZen_Spot5_small"
        }
        else if age >= increment*5 && age < oldestAgeAllowed {
            imageName = "ParkZen_Spot6_small"
        }
        else {
            mapView.removeAnnotation(annotation)
            // MAX HERE
            var savedLocs: [SumoCoordinate] = UserDefaults.standard.structArrayData(SumoCoordinate.self, forKey: fakeDatabaseSavedLocationsKey)
            savedLocs.removeAll(where: {
                Int(round(Date().timeIntervalSince1970 - $0.timeCreated)/60) > oldestAgeAllowed
            })
            UserDefaults.standard.setStructArray(savedLocs, forKey: fakeDatabaseSavedLocationsKey)
            
            // TODO: DATABASE Do I need to delete it from the database here?  Yes.
            return nil
        }
        
        // Sets image
        let offset = age < 10 ? 11 : 8
        myPinView.image = textToImage(drawText: String(age), inImage: UIImage(named: imageName)!, atPoint: CGPoint(x: offset, y: 7))
        
        // Add animation.
        //myPinView.animatesDrop = true
        
        // Display callouts.
        myPinView.canShowCallout = true
        
        
        // Set annotation.
        //myPinView.annotation = annotation
        
        // Set image.
        //myPinView.image = UIImage(named: "ParkZen_Spot1")
        
        //print("latitude: \(annotation.coordinate.latitude), longitude: \(annotation.coordinate.longitude)")
        
        return myPinView
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
    
    // Credit to Stack Overflow user Christopher Wade Cantley.
    // https://stackoverflow.com/users/3750109/christopher-wade-cantley
    func textToImage(drawText text: String, inImage image: UIImage, atPoint point: CGPoint) -> UIImage {
        let textColor = UIColor.black
        let textFont = UIFont(name: "Helvetica Bold", size: 12)!
        
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(image.size, false, scale)
        
        let textFontAttributes = [
            NSAttributedString.Key.font: textFont,
            NSAttributedString.Key.foregroundColor: textColor,
            ] as [NSAttributedString.Key : Any]
        image.draw(in: CGRect(origin: CGPoint.zero, size: image.size))
        
        let rect = CGRect(origin: point, size: image.size)
        text.draw(in: rect, withAttributes: textFontAttributes)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage!
    }
}

// MARK: - Location Manager Delegate
extension ViewController: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        mapView.showsUserLocation = status == .authorizedAlways
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Monitoring failed for region with identifier: \(region!.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        // Only is true if this is called from a disconnection event.  Otherwise, we don't want this to run, but we want to use the rest of the code for other stuff.
        if locationReason == .isDisconnectLocation {
            locationReason = .isNone
            if let location = locations.first {
                notify(withMessage: "Parking location saved!")
                print("Parking location saved!")
                dropPin(location.coordinate, "0", Date().timeIntervalSince1970)
                let defaults = UserDefaults.standard
                // TODO: Make this save to the database.
                defaults.setStruct(SumoCoordinate(coord: location.coordinate), forKey: mostRecentSavedLocationKey)
                // Add location to the fake database of locations.
                // MAX HERE ALSO
                var locs: [SumoCoordinate] = defaults.structArrayData(SumoCoordinate.self, forKey: fakeDatabaseSavedLocationsKey)
                locs.append(SumoCoordinate(coord: location.coordinate))
                defaults.setStructArray(locs, forKey: fakeDatabaseSavedLocationsKey)
            }
            return
        }
        
        if locationReason == .isTravelGeofence {
            locationReason = .isNone
            if locations.first != nil {
                startTravelGeofencing(location: locations.first!.coordinate)
            }
            return
        }
        
        let lastLocation: CLLocation = locations[locations.count - 1]
        self.recentLocation = lastLocation
        
        // Displays info at the top of the screen about location data.
        latitudeLabel.text = String(format: "%.6f", lastLocation.coordinate.latitude)
        longitudeLabel.text = String(format: "%.6f", lastLocation.coordinate.longitude)
        //        altitudeLabel.text = String(format: "%.6f", lastLocation.altitude)
        //        hAccuracyLabel.text = String(format: "%.6f", lastLocation.horizontalAccuracy)
        //        vAccuracyLabel.text = String(format: "%.6f", lastLocation.verticalAccuracy)
        
        // Runs when the app is opened to center the map to the user's location.
        if !initialized {
            animateMap(lastLocation)
            initialized = true
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with the following error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if region is CLCircularRegion {
            //beginActivityMonitor()
            //print("ViewController:beginActivityMonitor()")
        }
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
}


// MARK: - Bluetooth
extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            print("central.state is .unknown")
        case .resetting:
            print("central.state is .resetting")
        case .unsupported:
            print("central.state is .unsupported")
        case .unauthorized:
            print("central.state is .unauthorized")
        case .poweredOff:
            print("central.state is .poweredOff")
        case .poweredOn:
            print("central.state is .poweredOn")
            centralManager.scanForPeripherals(withServices: nil)
            connectToMarkedPeripherals()
        default:
            print("turn ya noodle to nada")
        }
    }
    
    func connectToMarkedPeripherals() {
        var identifiers: [UUID] = []
        deviceSwitches.forEach { (perifSwitch) in
            if perifSwitch.device is Peripheral && perifSwitch.device.isConnected {
                identifiers.append((perifSwitch.device as! Peripheral).uuid!)
            }
        }
        let activatedPeripheral = centralManager.retrievePeripherals(withIdentifiers: identifiers)
        for perif in activatedPeripheral {
            if !connectedPeripherals.contains(perif) {
                connectedPeripherals.append(perif)
            }
            centralManager.connect(perif, options: nil)
            print("Attempting to connect to \(perif.name ?? "Unnamed Device")...")
        }
    }
    
    // Runs when a new Bluetooth device is discovered
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Get the saved Peripherals from the UserDefaults
        let defaults = UserDefaults.standard
        var savedPerifs: [Peripheral] = UserDefaults.standard.structArrayData(Peripheral.self, forKey: savedBLEConnectedDevicesKey)
        
        
        
        // Make sure the peripheral has a name, and check if it has already been saved
        if peripheral.name != nil && !arrayContainsId(array: savedPerifs, containsId: peripheral.identifier) {
            
            // Create a new Peripheral and add it to the saved list of peripherals
            let newPerif = Peripheral(name: peripheral.name!, uuid: peripheral.identifier, isConnected: false)
            savedPerifs.append(newPerif)
            print("did Discover: " + peripheral.name!)
            
            // Save it back to UserDefaults
            defaults.setStructArray(savedPerifs, forKey: savedBLEConnectedDevicesKey)
            
            // Display the name on screen
            //peripheralListLabel.text = peripheralListLabel.text! + "\n" + peripheral.name!
            createNewDeviceSelectComponent(device: newPerif)
        }
        
    }
    
    
    // Activates when any connection event occures
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent,
                        for peripheral: CBPeripheral) {
        switch event {
        case .peerConnected:
            notify(withMessage: (peripheral.name ?? "Unnamed Device") + " has connected.")
            print((peripheral.name ?? "Unnamed Device") + " has connected. ")
        case .peerDisconnected:
        break // didDisconnectPeripheral handles this for us.
        default:
            print("Default case: CentralManager:ConnectionEventDidOccur")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        notify(withMessage: "Connected to \(peripheral.name ?? "Unnamed Device")")
        print("Connected to \(peripheral.name ?? "Unnamed Device")")
        
        
    }
    
    // Activates when a peripheral disconnects from the device for any reason besides disconnectPeripheral()
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        notify(withMessage: (peripheral.name ?? "Unnamed Device") + " has disconnected.")
        print((peripheral.name ?? "Unnamed Device") + " has disconnected. ", terminator: "")
        if error != nil {
            print("Reason: \(error!.localizedDescription)")
        }
        locationReason = .isDisconnectLocation
        locationManager.requestLocation()
        
        centralManager.connect(peripheral, options: nil)
        
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        notify(withMessage: "Restoring state.")
        
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            peripherals.forEach { (awakedPeripheral) in
                print("Awaked peripheral \(awakedPeripheral.name ?? "Unnamed Device")")
                notify(withMessage: "Awaked peripheral \(awakedPeripheral.name ?? "Unnamed Device")")
                
                centralManager.connect(awakedPeripheral, options: nil)
                
                if !connectedPeripherals.contains(awakedPeripheral) {
                    connectedPeripherals.append(awakedPeripheral)
                }
            }
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        print("Peripheral value changed for \(peripheral.name ?? "Unnamed Device")")
    }
    
    
    private func arrayContainsId(array: [Any], containsId: UUID) -> Bool {
        for perif in array {
            if (perif as! Peripheral).uuid == containsId {
                return true
            }
        }
        return false
    }
    
    
}



// MARK: - Random Useful Stuff
// This should probably all be moved to a personal library so I can use it forever
extension UserDefaults {
    open func setStruct<T: Codable>(_ value: T?, forKey defaultName: String){
        let data = try? JSONEncoder().encode(value)
        set(data, forKey: defaultName)
    }
    
    open func structData<T>(_ type: T.Type, forKey defaultName: String) -> T? where T : Decodable {
        guard let encodedData = data(forKey: defaultName) else {
            return nil
        }
        
        return try! JSONDecoder().decode(type, from: encodedData)
    }
    
    open func setStructArray<T: Codable>(_ value: [T], forKey defaultName: String){
        let data = value.map {
            try? JSONEncoder().encode($0)
        }
        
        set(data, forKey: defaultName)
    }
    
    open func structArrayData<T>(_ type: T.Type, forKey defaultName: String) -> [T] where T : Decodable {
        guard let encodedData = array(forKey: defaultName) as? [Data] else {
            return []
        }
        
        return encodedData.map { try! JSONDecoder().decode(type, from: $0) }
    }
}


extension String {
    var isNumeric: Bool {
        guard self.count > 0 else { return false }
        let nums: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        return Set(self).isSubset(of: nums)
    }
}
