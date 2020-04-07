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
    
    var previousActivity: String = "none"
    
    var recentLocation: CLLocationCoordinate2D = CLLocationCoordinate2D()
    
    var initialized: Bool = false;
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        mapView.showsUserLocation = true
        
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
                modes.insert("uknown")
            }

            self.activitiesLabel.text = modes.joined(separator: ", ")
            
            if(self.previousActivity == "walking" && modes.first == "stationary") {
                self.activitiesLabel.text = "DROP A PIN"
                self.dropPin(self.recentLocation)
            }
            else {
                self.activitiesLabel.text = modes.first

            }
            
            if modes.first != "unknown" {
                self.previousActivity = modes.first ?? self.previousActivity
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
 
        latitudeLabel.text = String(format: "%.6f", lastLocation.coordinate.latitude)
        longitudeLabel.text = String(format: "%.6f", lastLocation.coordinate.longitude)
        altitudeLabel.text = String(format: "%.6f", lastLocation.altitude)
        hAccuracyLabel.text = String(format: "%.6f", lastLocation.horizontalAccuracy)
        vAccuracyLabel.text = String(format: "%.6f", lastLocation.verticalAccuracy)
        
        if !initialized {
            animateMap(lastLocation)
            initialized = true
        }
    }
    
    func animateMap(_ location: CLLocation) {
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        mapView.setRegion(region, animated: true)
    }
    
    func dropPin(_ coord: CLLocationCoordinate2D) {
        print(String(coord.latitude) + " " + String(coord.longitude))
        let myPin: MKPointAnnotation = MKPointAnnotation()
        
        // Set the coordinates.
        myPin.coordinate = coord
        
        // Set the title.
        myPin.title = "title"
        
        // Set subtitle.
        myPin.subtitle = "subtitle"
        
        // Added pins to MapView.
        self.mapView.addAnnotation(myPin)
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
    
}
