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
    static let shared: DatabaseDelegate = DatabaseDelegate()
    let expTime = 60.0 //experiation time in mintues
    var spotSet = Set<SumoCoordinate>()
    let scBuilder = SumoCoordinateBuilder()
    let ageInMinutes:(Double) -> Double = { timeCreated in
        (Date().timeIntervalSince1970 - timeCreated)/60
    }
    
    private init() {
        
        ref = Database.database().reference()
    }
    
    func write(location: SumoCoordinate) {
        
        self.ref.childByAutoId().setValue(["latitude": location.latitude, "longitude": location.longitude, "TimeCreated": location.timeCreated])
    }
    
    func read(map: MKMapView) {
        
        self.ref.observeSingleEvent(of: .value, with: { (snapshot) in
            
            let dataDict = snapshot.value as? [String:Any]
            var spotDict: [String : Double]
            var spot: SumoCoordinate
            
            for (key, _) in dataDict! {
                
                spotDict = snapshot.childSnapshot(forPath: key).value as! [String : Double]
                
                spot = self.scBuilder
                            .withLatitude(lat: spotDict["latitude"]!)
                            .withLongitude(lon: spotDict["longitude"]!)
                            .withTime(time: spotDict["TimeCreated"]!)
                            .build()
                
                if (self.ageInMinutes(spotDict["TimeCreated"]!) > self.expTime) {
                    
                    self.ref.child(key).removeValue()
                    self.spotSet.remove(spot)
    
                } else if(!self.spotSet.contains(spot)) {
                          
                    self.draw(spot, map: map)
                    self.spotSet.insert(spot)
                }
            }
                
        })
        
    }
    
    func draw(_ sc: SumoCoordinate, map: MKMapView){
        
        let pin: SumoAnnotation = SumoAnnotation(sc: sc, title: "\(ageInMinutes(sc.timeCreated)) minutes")
        map.addAnnotation(pin)
    }
}
