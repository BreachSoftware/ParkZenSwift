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

class ViewController: UIViewController {
    
    @IBOutlet weak var latitudeLabel: UILabel!
    @IBOutlet weak var longitudeLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
    @IBOutlet weak var hAccuracyLabel: UILabel!
    @IBOutlet weak var vAccuracyLabel: UILabel!
    @IBOutlet weak var activitiesLabel: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    
    
    // MARK: Properties
    var locationManager: CLLocationManager = CLLocationManager()
    
    let manager = CMMotionActivityManager()
    
    var geotifications: [Geotification] = []
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Struct for holding the previous activity's data.
    struct Activity {
        var id: String = "unknown"
        var conf: Int = 0
    }
    
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
    var isBackgroundRefresh: Bool = false;
    // Also only for BG refresh, returns if location is found (so it can end the task)
    var gotLocationInBG: Bool = false;
    
    
    //MARK: Initialization
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        mapView.delegate = self
        
        mapView.showsUserLocation = true
        
        
        // Timer to increment the pins' timer once per minute.
        _ = Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: #selector(ViewController.incrementAnnotations), userInfo: nil, repeats: true)
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier:
            "sumocode.ParkZen.get_location",
                                        using: nil)
        {task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
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
        
    }
    
    deinit {
      NotificationCenter.default.removeObserver(self)
    }
    

    
    
    //    func application(_ application: UIApplication,
    //                     didFinishLaunchingWithOptions launchOptions:
    //        [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    //        // Override point for customization after application launch.
    //        print("Gang.")
    //        BGTaskScheduler.shared.register(forTaskWithIdentifier:
    //        "sumocode.ParkZen.get_location",
    //        using: nil)
    //        {task in
    //            self.handleAppRefresh(task: task as! BGAppRefreshTask)
    //        }
    //
    //        return true
    //    }
    
    // MARK: Background Updates
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
    
    
    @objc func reinstateBackgroundTask() {
        if backgroundTask == .invalid {
            registerBackgroundTask()
        }
    }
    
    
    // MARK: Scheduling
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
        
        scheduleAppRefresh()
        
        isBackgroundRefresh = true
        
        locationManager.delegate = self
        locationManager.requestLocation()
        
        
        // Ends the task when a location is returned.
        task.setTaskCompleted(success: gotLocationInBG)
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    // MARK: Location and Pin Stuff
    // Increments the timer on all of the pins that are not the User Location.
    @objc func incrementAnnotations()
    {
        let annotations = mapView.annotations
        for annotation: MKAnnotation in annotations {
            if annotation.title!!.isNumeric {
                // There's gotta be a better way to take care of this but I don't know
                // type and string manipulation well enough in this language yet :p
                let str: String = annotation.title!!
                let num = Int(str)!
                dropPin(annotation.coordinate, String(num+1) + " minutes")
                mapView.removeAnnotation(annotation)
            }
        }
    }
    
    // Gets location whenever it is updated and updates the associated labels.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        // Runs only if this is called from a background refresh.  Simply returns and prints the location.
        if isBackgroundRefresh {
            if let location = locations.first {
                print("Found user's location: \(location)")
                gotLocationInBG = true
            }
            return;
        }
        
        let lastLocation: CLLocation = locations[locations.count - 1]
        self.recentLocation = lastLocation
        
        // Displays info at the top of the screen about location data.
        latitudeLabel.text = String(format: "%.6f", lastLocation.coordinate.latitude)
        longitudeLabel.text = String(format: "%.6f", lastLocation.coordinate.longitude)
        altitudeLabel.text = String(format: "%.6f", lastLocation.altitude)
        hAccuracyLabel.text = String(format: "%.6f", lastLocation.horizontalAccuracy)
        vAccuracyLabel.text = String(format: "%.6f", lastLocation.verticalAccuracy)
        
        // Runs when the app is opened to center the map to the user's location.
        if !initialized {
            animateMap(lastLocation)
            initialized = true
        }
    }
    
    
    // Animates the map to orient it to the specified location.
    func animateMap(_ location: CLLocation) {
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        mapView.setRegion(region, animated: true)
    }
    
    
    // Creates and adds a pin to the map.
    func dropPin(_ coord: CLLocationCoordinate2D, _ title: String? = "0") {
        
        let allAnnotations = self.mapView.annotations
        self.mapView.removeAnnotations(allAnnotations)
        
        let myPin: MKPointAnnotation = MKPointAnnotation()
        
        // Set the coordinates.
        myPin.coordinate = coord
        
        // Set the title.
        myPin.title = title
        
        // Set subtitle.
        myPin.subtitle = "subtitle"
        
        // Added pins to MapView.
        self.mapView.addAnnotation(myPin)
    }
    
    //MARK: Activity Monitoring
    // Reports user activity on change.
    public func beginActivityMonitor() {
        print("Began monitoring activities...")
        manager.startActivityUpdates(to: .main) { (activity) in
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
            self.registerBackgroundTask()
            
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
        manager.stopActivityUpdates()
    }
    
    
    
    // MARK: Geofence Handling
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
        beginActivityMonitor()
    }
    
    //MARK: Notifications
    func notify() {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.body = self.previousActivity.id
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



extension ViewController: MKMapViewDelegate {
    
    
    // Delegate method called when addAnnotation is done.
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        let myPinIdentifier = "PinAnnotationIdentifier"
        
        // Generate pins.
        let myPinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: myPinIdentifier)
        
        // Add animation.
        myPinView.animatesDrop = true
        
        // Display callouts.
        myPinView.canShowCallout = true
        
        // Set annotation.
        myPinView.annotation = annotation
        
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
}

// MARK: - Location Manager Delegate
extension ViewController: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        mapView.showsUserLocation = status == .authorizedAlways
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Monitoring failed for region with identifier: \(region!.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with the following error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if region is CLCircularRegion {
            beginActivityMonitor()
            print("ViewController:beginActivityMonitor()")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region is CLCircularRegion {
            stopActivityMonitor()
            print("ViewController:stopActivityMonitor()")
        }
    }
}


extension String {
    var isNumeric: Bool {
        guard self.count > 0 else { return false }
        let nums: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        return Set(self).isSubset(of: nums)
    }
}


