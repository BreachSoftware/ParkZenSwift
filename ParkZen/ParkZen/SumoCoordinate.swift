//
//  SumoCoordinate.swift
//  ParkZen
//
//  Created by Max on 7/8/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import Foundation
import CoreLocation

struct SumoCoordinate: Codable, Hashable {
    var latitude: Double = 0
    var longitude: Double = 0
    var timeCreated: Double = Date().timeIntervalSince1970
    
    init() {
    }
    
    init(coord: CLLocationCoordinate2D) {
        self.latitude = coord.latitude
        self.longitude = coord.longitude
    }
    
    init(lat: Double, lon: Double){
        self.latitude = lat
        self.longitude = lon
    }
}

class SumoCoordinateBuilder {
    
    var latitude = 0.0, longitude = 0.0, time = 0.0
    
    func build() -> SumoCoordinate {
        
        var sc = SumoCoordinate(lat: latitude, lon: longitude)
        sc.timeCreated = self.time
        return sc
    }
    
    func withLatitude(lat: Double) -> SumoCoordinateBuilder {
        
        self.latitude = lat
        return self
    }
    
    func withLongitude(lon: Double) -> SumoCoordinateBuilder {
        
        self.longitude = lon
        return self
    }
    
    func withTime(time: Double) -> SumoCoordinateBuilder {
        
        self.time = time
        return self
    }
}


