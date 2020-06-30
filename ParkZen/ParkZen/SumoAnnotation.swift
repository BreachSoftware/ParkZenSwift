//
//  SumoAnnotation.swift
//  ParkZen
//
//  Created by Colin Hebert on 6/30/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import Foundation
import MapKit


class SumoAnnotation: MKPointAnnotation {
    var image: String!
    var timeStamp: Double! = Date().timeIntervalSince1970
}
