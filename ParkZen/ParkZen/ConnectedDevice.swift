//
//  ConnectedDevice.swift
//  ParkZen
//
//  Created by Colin Hebert on 7/6/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import Foundation

class ConnectedDevice: Codable {
    
    // Public name of the device.
    var name = ""
    
    // Device is connected to the app, and should notify and save location when it disconnects.
    var isConnected = false
    
    
}
