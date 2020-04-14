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
    
    // Struct for holding the previous activity's data.
    struct Activity {
        var id: String = "unknown"
        var conf: Int = 0
    }
    
    var previousActivity: Activity = Activity()
    
    var recentLocation: CLLocationCoordinate2D = CLLocationCoordinate2D()
    
    var initialized: Bool = false;
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        mapView.showsUserLocation = true
        
        beginActivityMonitor()
        
        _ = Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: #selector(ViewController.incrementAnnotations), userInfo: nil, repeats: true)
    }
    
    @objc func incrementAnnotations()
    {
        let annotations = mapView.annotations
        for annotation: MKAnnotation in annotations {
            if !annotation.isKind(of: MKUserLocation.self) {
                let str: String = (annotation.title ?? "ERR1") ?? "ERR2"
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
 
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lastLocation: CLLocation = locations[locations.count - 1]
        self.recentLocation = lastLocation.coordinate
 
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
    
    func animateMap(_ location: CLLocation) {
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        mapView.setRegion(region, animated: true)
    }
    
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
            
            if(self.previousActivity.id == "walking" && self.previousActivity.conf != 0 && modes.first != "walking" && activity.confidence.rawValue != 0) {
                self.dropPin(self.recentLocation)
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
    
//    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
//        // fetch data from internet now
//        guard let data = fetchSomeData() else {
//            // data download failed
//            completionHandler(.failed)
//            return
//        }
//
//        if data.isNew {
//            // data download succeeded and is new
//            completionHandler(.newData)
//        } else {
//            // data downloaded succeeded and is not new
//            completionHandler(.noData)
//        }
//    }
 
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
    
}
