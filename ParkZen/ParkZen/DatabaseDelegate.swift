//
//  DatabaseDelegate.swift
//  Test
//
//  Created by Max on 7/6/20.
//  Copyright © 2020 Max. All rights reserved.
//

import Foundation
import FirebaseDatabase
import MapKit

class DatabaseDelegate {
    
    var ref: DatabaseReference!
    let expTime = 1800.0
    var spotSet = Set<SumoCoordinate>()
    let scBuilder = SumoCoordinateBuilder()
    let mapView: MKMapView
    let ageInMinutes:(Double) -> Int = { timeCreated in
        Int((Date().timeIntervalSince1970 - timeCreated)/60)
    }
    
    init(map: MKMapView) {
        
        mapView = map
        ref = Database.database().reference()
    }
    
    func write(location: SumoCoordinate) {
        
        self.ref.childByAutoId().setValue(["latitude": location.latitude, "longitude": location.longitude, "TimeCreated": location.timeCreated])
    }
    
    func read() {
        
        self.ref.observeSingleEvent(of: .value, with: { (snapshot) in
            
            let dataDict = snapshot.value as? [String:Any]
            var spotDict: [String : Double]
            var spot: SumoCoordinate
            
            for (key, _) in dataDict! {
                
                spotDict = snapshot.childSnapshot(forPath: key).value as! [String : Double]
                
                if(Date().timeIntervalSince1970 - spotDict["TimeCreated"]! > self.expTime){
                    
                    self.ref.child(key).removeValue()
                   
    
                } else {
                    
                    spot = self.scBuilder
                        .withLatitude(lat: spotDict["latitude"]!)
                        .withLongitude(lon: spotDict["longitude"]!)
                        .withTime(time: spotDict["TimeCreated"]!)
                        .build()
                    
                    self.draw(spot)
                    self.spotSet.insert(spot)
                }
            }
                
        })
        
    }
    
    func draw(_ sc: SumoCoordinate){
        
        let pin: SumoAnnotation = SumoAnnotation(sc: sc, title: "\(ageInMinutes(sc.timeCreated)) minutes")
        mapView.addAnnotation(pin)
        
    }
}
