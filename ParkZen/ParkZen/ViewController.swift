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


class ViewController: UIViewController {
    
    @IBOutlet weak var latitudeLabel: UILabel!
    @IBOutlet weak var longitudeLabel: UILabel!
    @IBOutlet weak var activitiesLabel: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var scrollView: UIScrollView!
    
    
    // MARK: Properties
    
    // Manages all location interaction.
    var locationManager: CLLocationManager = CLLocationManager()
    
    let activityManager: CMMotionActivityManager = CMMotionActivityManager()
    
    let accessoryManager: EAAccessoryManager = EAAccessoryManager.shared()
    
    var geotifications: [Geotification] = []
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Struct for holding the previous activity's data.
    struct Activity {
        var id: String = "unknown"
        // Confidence value (0, 1, or 2) of how sure the system is of the activity.  2 is highest.
        var conf: Int = 0
    }
    
    // Struct for holding bluetooth peripheral info.
    struct Peripheral: Codable {
        // Unique identifier for all BT peripherals.
        var uuid: UUID = UUID()
        // Usually optional (but not for us) name of the device.
        var name: String = ""
        // Records whether this devices has connected with us before and if it should autoconnect in the future.
        var hasConnected: Bool = false
    }
    
    // Struct for holding the component displaying connected Bluetooth devices.
    struct perifSwitchComponent {
        // Label with name of the peripheral.
        var label: UILabel = UILabel()
        // Switch to turn connection to peripheral on or off.
        var uiSwitch: UISwitch = UISwitch()
        // The data of the peripheral that is being controlled.
        var savedPerifData: Peripheral = Peripheral()
    }
    
    // Struct for saving most recent parked location coordinates so it's encodable.
    // I actually don't think this is the way to do this, but my only other idea is to create
    // an entire class that is encodable and writing an encode() function like in Geotification.swift,
    // but jeez that seems like a whole lot of sweat for something that doesn't help anything as far
    // as I can tell, so I'm leaving it like this for now.
    struct SumoCoordinate: Codable {
        var latitude: Double = 0
        var longitude: Double = 0
        var timeCreated: Double = Date().timeIntervalSince1970
        
        init() {
        }
        
        init(coord: CLLocationCoordinate2D) {
            self.latitude = coord.latitude
            self.longitude = coord.longitude
        }
    }
    
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
    var isDisconnectLocation: Bool = false;
    // Also only for BG refresh, returns if location is found (so it can end the task).
    var gotLocationInBG: Bool = false;
    // Hey buddy pretty sure both of these are unused now.
    
    // Used to keep track of the label and switches on the scroll view.
    var perifSwitches: [perifSwitchComponent] = []
    
    // Use to keep track of connected peripherals.  God this is a mess.
    // TODO: clean up all the different ways that I'm saving peripherals.
    var connectedPeripherals: [CBPeripheral] = []
    
    final var mostRecentSavedLocationKey = "RECENTLOC"
    
    final var fakeDatabaseSavedLocationsKey = "FAKEDATABASELOCATIONS"
    
    
    
    //MARK: - Initialization
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        mapView.delegate = self
        
        mapView.showsUserLocation = true
        
        // Turns bluetooth management on.
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey : "restore.com.sumocode.parkzen"])

        
        
        // Timer to increment the pins' timer once per minute.
        _ = Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: #selector(ViewController.incrementAnnotations), userInfo: nil, repeats: true)
        
        
        
//        BGTaskScheduler.shared.register(forTaskWithIdentifier:
//            "sumocode.ParkZen.get_location",
//                                        using: nil)
//        {task in
//            self.handleAppRefresh(task: task as! BGAppRefreshTask)
//            print("1")
//        }
        
        //scheduleAppRefresh()
        
        // TODO: Clean this up.  Right now, it removes all geofences then adds the LSU one back and saves it.  We just need to load the LSU one.  But because it is saved on the app, in order to change it when the app is rebuilt I just delete it and resave it.  So in the future.  Just remember this is dumb.
        geotifications.removeAll()
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(geotifications)
            UserDefaults.standard.set(data, forKey: "savedItems")
        } catch {
            print("error encoding geotifications")
        }
        let allGeotifications = Geotification.allGeotifications()
        allGeotifications.forEach {
            print($0.coordinate)
        }
        if allGeotifications.count == 0 {
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
            allGeotifications.forEach {
                add($0)
                startMonitoring(geotification: $0)
            }
            
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(reinstateBackgroundTask), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        
        //let defaults = UserDefaults.standard
        //defaults.set([], forKey: "Peripherals")
        let savedPerifs: [Peripheral] = UserDefaults.standard.structArrayData(Peripheral.self, forKey: "Peripherals")
        
        // Loads all saved peripherals into the scroll view
        for perif in savedPerifs {
            createNewBluetoothSelectComponent(perif: perif)
        }
        
        
        //UserDefaults.standard.setStruct(SumoCoordinate(), forKey: mostRecentSavedLocationKey)
        
//        if let lastLoc = UserDefaults.standard.structData(SumoCoordinate.self, forKey: mostRecentSavedLocationKey) {
//            dropPin(CLLocationCoordinate2D(latitude: lastLoc.latitude, longitude: lastLoc.longitude), "0 minutes", lastLoc.timeCreated)
//        }
        
        
        
        let savedLocs: [SumoCoordinate] = UserDefaults.standard.structArrayData(SumoCoordinate.self, forKey: fakeDatabaseSavedLocationsKey)
        
        for loc in savedLocs {
            print("Woop")
            dropPin(CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude), "0 minutes", loc.timeCreated)
        }
        
        incrementAnnotations()
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    // MARK: - Bluetooth Switches
    func createNewBluetoothSelectComponent(perif: Peripheral) {
        
        // Distance below top of scrollView to create the next switch component.
        let y = perifSwitches.count * 40
        
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 21))

        // you will probably want to set the font (remember to use Dynamic Type!)
        label.font = UIFont.preferredFont(forTextStyle: .footnote)

        // and set the text color too - remember good contrast
        label.textColor = .white

        // may not be necessary (e.g., if the width & height match the superview)
        label.center = CGPoint(x: 60, y: y+13)

        label.textAlignment = .center

        label.text = perif.name

        // Adds the label to the scrollView.
        self.scrollView.addSubview(label)
        
        let perifSwitch = UISwitch(frame:CGRect(x: 150, y: y, width: 0, height: 0))
        perifSwitch.addTarget(self, action: #selector(ViewController.switchStateDidChange(_:)), for: .valueChanged)
        perifSwitch.setOn(perif.hasConnected, animated: false)
        self.scrollView.addSubview(perifSwitch)
        
        // Creates a new perifSwitchComponent struct and then adds it to the list of switches.
        let newSwitch = perifSwitchComponent(label: label, uiSwitch: perifSwitch, savedPerifData: perif)
        perifSwitches.append(newSwitch)
        
        // Sets the size of the scrollView.
        self.scrollView.contentSize = CGSize(width: Int(self.scrollView.visibleSize.width), height: y + 40)
    }
    
    @objc func switchStateDidChange(_ sender:UISwitch!)
    {
        // Finds the correct switch
        let which = findWhichSwitch(sw: sender)
        
        // If the button is turned on, add to activePeripherals
        if (sender.isOn == true) {
            // Grabs the first (and only) returned peripheral based on the UUID
            let activatedPeripheral = centralManager.retrievePeripherals(withIdentifiers: [which.savedPerifData.uuid]).first
            if activatedPeripheral == nil {
                print("Error: Device not available.")
                return
            }
            print(activatedPeripheral?.name! ?? "ERR")
            centralManager.registerForConnectionEvents(options: [CBConnectionEventMatchingOption.peripheralUUIDs : [activatedPeripheral!.identifier]])
            centralManager.connect(activatedPeripheral!, options: nil)
            if !connectedPeripherals.contains(activatedPeripheral!) {
                connectedPeripherals.append(activatedPeripheral!)
            }
            
            
            savePeripheralChanges(changedPeripheralID: activatedPeripheral!.identifier, isConnected: true)
        
        }
        else {
            connectedPeripherals.removeAll(where: {$0.identifier == which.savedPerifData.uuid})
            savePeripheralChanges(changedPeripheralID: which.savedPerifData.uuid, isConnected: false)
        }
    }
    
    // Finds the perifSwitchComponent that corresponds to UISwitch sw.
    func findWhichSwitch(sw: UISwitch) -> perifSwitchComponent {
        for p in perifSwitches {
            if p.uiSwitch == sw {
                return p
            }
        }
        return perifSwitchComponent()
    }
    
    func savePeripheralChanges(changedPeripheralID: UUID, isConnected: Bool) {
        // Get all saved Peripherals
        let defaults = UserDefaults.standard
        var savedPerifs: [Peripheral] = defaults.structArrayData(Peripheral.self, forKey: "Peripherals")
        
        // Check each saved uuid against the uuid of the activatedPeripheral
        savedPerifs.forEach { (perif) in
            if perif.uuid == changedPeripheralID {
                // Once found, create a new peripheral with hasConnected = true
                let newPerif = Peripheral(uuid: perif.uuid, name: perif.name, hasConnected: isConnected)
                // Remove the old one, add the new one.
                savedPerifs.removeAll(where: {$0.uuid == changedPeripheralID})
                isConnected ? savedPerifs.insert(newPerif, at: 0) : savedPerifs.append(newPerif)
            }
        }
        // Save it back to UserDefaults
        defaults.setStructArray(savedPerifs, forKey: "Peripherals")
    }
    
    
    
    // MARK: - Background Updates
    // Registers a background task to run when the app closes.
    func registerBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        assert(backgroundTask != .invalid)
    }
    
    // Runs when the background task completes or when the iOS decides that it's had enough of running it (after about 3 minutes of run time)
    func endBackgroundTask() {
        print("Background task ended.")
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    
    // Reruns the task whenever the app is opened and then closed again.
    @objc func reinstateBackgroundTask() {
        if backgroundTask == .invalid {
            //registerBackgroundTask()
        }
    }
    
    
    // MARK: - Scheduling
    // Creates a request task to run a quick location check every 30 seconds
    // This won't work.  Also this is for when the app is terminated.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "sumocode.ParkZen.get_location")
        // Fetch no earlier than 30 seconds from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30)
        print("Scheduling...")
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Success!")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    
    // Handles the request made in scheduleAppRefresh() when it is called.
    // When the system opens the app in the background, it calls the launch handler to run the task.
    func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule a new refresh task
        print("Rescheduling...")
        notify()
        
        scheduleAppRefresh()
        
        // Ends the task when a location is returned.
        task.setTaskCompleted(success: gotLocationInBG)
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    // MARK: - Location and Pin Stuff
    // Increments the timer on all of the pins that are not the User Location.
    @objc func incrementAnnotations()
    {
        let annotations = mapView.annotations
        for annotation: MKAnnotation in annotations {
            
            if annotation is SumoAnnotation {
                let timeStamp = (annotation as! SumoAnnotation).timeStamp
                
                // Calculates the age in minutes since the annotation has been created.
                let age = Int(round(Date().timeIntervalSince1970 - (annotation as! SumoAnnotation).timeStamp)/60)
                dropPin(annotation.coordinate, String(age) + " minute" + (age == 1 ? "" : "s"), timeStamp)
                mapView.removeAnnotation(annotation)
            }
            
            // This doesn't work anymore and the fact that I wrote this thinking it would is a testament to my ability to
            // not think.
//            if annotation.title!!.isNumeric {
//                // There's gotta be a better way to take care of this but I don't know
//                // type and string manipulation well enough in this language yet :p
//                let str: String = annotation.title!!
//                let num = Int(str)!
//                dropPin(annotation.coordinate, String(num+1) + " minute" + (num == 1 ? "" : "s"))
//                mapView.removeAnnotation(annotation)
//            }
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
        
        let myPin: SumoAnnotation = SumoAnnotation()
        
        // Set the time stamp.
        myPin.timeStamp = timeStamp
        
        // Set the coordinates.
        myPin.coordinate = coord
        
        // Set the title.
        myPin.title = title
        
        // Set subtitle.
        myPin.subtitle = "subtitle"
        
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
    
    func add(_ geotification: Geotification) {
        geotifications.append(geotification)
        mapView.addAnnotation(geotification)
        mapView?.addOverlay(MKCircle(center: geotification.coordinate, radius: geotification.radius))
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

// MARK: Map View Delegate
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
            var savedLocs: [SumoCoordinate] = UserDefaults.standard.structArrayData(SumoCoordinate.self, forKey: fakeDatabaseSavedLocationsKey)
            savedLocs.removeAll(where: {
                Int(round(Date().timeIntervalSince1970 - $0.timeCreated)/60) > oldestAgeAllowed
            })
            UserDefaults.standard.setStructArray(savedLocs, forKey: fakeDatabaseSavedLocationsKey)
            
            // TODO: Do I need to delete it from the database here?  Yes.
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
        if isDisconnectLocation {
            isDisconnectLocation = false
            if let location = locations.first {
                notify(withMessage: "Parking location saved!")
                print("Parking location saved!")
                dropPin(location.coordinate, "0", Date().timeIntervalSince1970)
                let defaults = UserDefaults.standard
                // TODO: Make this save to the database.
                defaults.setStruct(SumoCoordinate(coord: location.coordinate), forKey: mostRecentSavedLocationKey)
                // Add location to the fake database of locations.
                var locs: [SumoCoordinate] = defaults.structArrayData(SumoCoordinate.self, forKey: fakeDatabaseSavedLocationsKey)
                locs.append(SumoCoordinate(coord: location.coordinate))
                defaults.setStructArray(locs, forKey: fakeDatabaseSavedLocationsKey)
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
            //stopActivityMonitor()
            //print("ViewController:stopActivityMonitor()")
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
        perifSwitches.forEach { (perifSwitch) in
            if perifSwitch.savedPerifData.hasConnected {
                identifiers.append(perifSwitch.savedPerifData.uuid)
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
        var savedPerifs: [Peripheral] = UserDefaults.standard.structArrayData(Peripheral.self, forKey: "Peripherals")

        // Make sure the peripheral has a name, and check if it has already been saved
        if peripheral.name != nil && !arrayContainsId(array: savedPerifs, containsId: peripheral.identifier) {
            
            // Create a new Peripheral and add it to the saved list of peripherals
            let newPerif = Peripheral(uuid: peripheral.identifier, name: peripheral.name!, hasConnected: false)
            savedPerifs.append(newPerif)
            print(peripheral.name!)
            
            // Save it back to UserDefaults
            defaults.setStructArray(savedPerifs, forKey: "Peripherals")
            
            // Display the name on screen
            //peripheralListLabel.text = peripheralListLabel.text! + "\n" + peripheral.name!
            createNewBluetoothSelectComponent(perif: newPerif)
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
        isDisconnectLocation = true
        locationManager.requestLocation()
            
        centralManager.connect(peripheral, options: nil)
        
    }
    
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        notify(withMessage: "Restoring state.")

        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            peripherals.forEach { (awakedPeripheral) in
                print("Awaked peripheral \(awakedPeripheral.name ?? "Unnamed Device")")
                //notify(withMessage: "Awaked peripheral \(awakedPeripheral.name ?? "Unnamed Device")")
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
        let data = value.map { try? JSONEncoder().encode($0) }
        
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
