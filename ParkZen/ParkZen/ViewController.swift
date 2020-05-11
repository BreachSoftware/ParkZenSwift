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
 
class ViewController: UIViewController, CLLocationManagerDelegate {
 
    @IBOutlet weak var latitudeLabel: UILabel!
    @IBOutlet weak var longitudeLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
    @IBOutlet weak var hAccuracyLabel: UILabel!
    @IBOutlet weak var vAccuracyLabel: UILabel!
    @IBOutlet weak var activitiesLabel: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    
    
    var locationManager: CLLocationManager = CLLocationManager()
    
    let manager = CMMotionActivityManager()
    
    var geotifications: [Geotification] = []
    
    // Struct for holding the previous activity's data.
    struct Activity {
        var id: String = "unknown"
        var conf: Int = 0
    }
    
    // Strictly for testing.  This will be pulled from wherever we want to geofence.
    let lsuCoords: CLLocation = CLLocation(latitude: 30.4133, longitude: -91.1800)
    //30.381521, -91.206449
    
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
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        mapView.delegate = self
        
        mapView.showsUserLocation = true
        
        // Begins checking for changes in activity of the user to drop pins.
        beginActivityMonitor()
        
        // Timer to increment the pins' timer once per minute.
        _ = Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: #selector(ViewController.incrementAnnotations), userInfo: nil, repeats: true)
        
        locationManager.allowsBackgroundLocationUpdates = true
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier:
        "sumocode.ParkZen.get_location",
        using: nil)
        {task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        scheduleAppRefresh()
        
        
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
            print("hmmmm")
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
            allGeotifications.forEach { add($0) }
        }
        
        
    }
    
    func add(_ geotification: Geotification) {
      geotifications.append(geotification)
      mapView.addAnnotation(geotification)
        mapView?.addOverlay(MKCircle(center: geotification.coordinate, radius: geotification.radius))
    }
    
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
        [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
            
//        BGTaskScheduler.shared.register(forTaskWithIdentifier:
//        "sumocode.ParkZen.get_location",
//        using: nil)
//        {task in
//            self.handleAppRefresh(task: task as! BGAppRefreshTask)
//        }
        
        
        
        return true
    }
        

    
    
    // Creates a request task to run a quick location check every 30 seconds
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "sumocode.ParkZen.get_location")
        // Fetch no earlier than 30 seconds from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5)
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
        scheduleAppRefresh()
        
        isBackgroundRefresh = true
        
        print("ahhhh")
        
        locationManager.delegate = self
        locationManager.requestLocation()
        
        // Ends the task when a location is returned.
        task.setTaskCompleted(success: gotLocationInBG)
        
        
    // We're not using an operation queue, but it might be a good idea to use one.
    // For testing, I'm gonna forgo using it.
        
//      // Create an operation that performs the main part of the background task
//      let operation = RefreshAppContentsOperation()
//
//      // Provide an expiration handler for the background task
//      // that cancels the operation
//      task.expirationHandler = {
//         operation.cancel()
//      }
//
//      // Inform the system that the background task is complete
//      // when the operation completes
//      operation.completionBlock = {
//         task.setTaskCompleted(success: !operation.isCancelled)
//      }
//
//      // Start the operation
//      operationQueue.addOperation(operation)
    }
    
    
    // Deprecated after iOS 13.
    
//    func application(_ application: UIApplication,
//                     performFetchWithCompletionHandler completionHandler:
//                     @escaping (UIBackgroundFetchResult) -> Void) {
//
//        // Check if location is within geofence.
//        if self.recentLocation.distance(from: myHouseCoords) < 100 {
//            print("Oh HELL yeah baybeeeee");
//        }
//
//    }
    
    
    // Increments the timer on all of the pins that are not the User Location.
    @objc func incrementAnnotations()
    {
        let annotations = mapView.annotations
        for annotation: MKAnnotation in annotations {
            if !annotation.isKind(of: MKUserLocation.self) && annotation.title != nil {
                // There's gotta be a better way to take care of this but I don't know
                // type and string manipulation well enough in this language yet :p
                let str: String = annotation.title!!
                let num = Int(str)!
                dropPin(annotation.coordinate, String(num+1) + " minutes")
                mapView.removeAnnotation(annotation)
            }
        }
    }
    
 
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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
    
    
    // Moves the map to orient it to the user's location.
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
    
    
    // Reports user activity on change.
    func beginActivityMonitor() {
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

            self.activitiesLabel.text = modes.joined(separator: ", ")
            
            if(self.previousActivity.id == "driving" && self.previousActivity.conf != 0 && modes.first != "driving" && activity.confidence.rawValue != 0) {
                self.dropPin(self.recentLocation.coordinate)
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
    
    func region(with geotification: Geotification) -> CLCircularRegion {
      let region = CLCircularRegion(center: geotification.coordinate, radius: geotification.radius, identifier: geotification.identifier)
      region.notifyOnEntry = (geotification.eventType == .onEntry)
      region.notifyOnExit = !region.notifyOnEntry
      return region
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
        
        print("latitude: \(annotation.coordinate.latitude), longitude: \(annotation.coordinate.longitude)")
        
        return myPinView
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      if overlay is MKCircle {
        print("Overlayed")
        let circleRenderer = MKCircleRenderer(overlay: overlay)
        circleRenderer.lineWidth = 1.0
        circleRenderer.strokeColor = .purple
        circleRenderer.fillColor = UIColor.purple.withAlphaComponent(0.4)
        return circleRenderer
      }
      return MKOverlayRenderer(overlay: overlay)
    }
    
}
