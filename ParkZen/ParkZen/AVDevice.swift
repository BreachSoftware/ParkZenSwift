//
//  AVDevice.swift
//  ParkZen
//
//  Created by Colin Hebert on 7/10/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import Foundation
import AVKit


class AVDevice: ConnectedDevice {
    
    final let savedAVConnectedDevicesKey = "SAVEDAVDEVICES"
    
    // Keys for encoding/decoding.
    enum CodingKeys: String, CodingKey {
        case name, type, uid, isConnected
    }
    
    // Audio port type of AV device.
    var type: AVAudioSession.Port.RawValue? = ""
    var uid: String = ""
    
    
    
    init(name: String, type: AVAudioSession.Port.RawValue, uid: String, isConnected: Bool) {
        super.init()
        self.name = name
        self.type = type
        self.uid = uid
        self.isConnected = isConnected
    }
    
    required init(from decoder: Decoder) throws {
        super.init()
        // First we get a container.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Then we can address the container, and try to get each property with a Key.
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        uid = try container.decode(String.self, forKey: .uid)
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
    }
    
    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(uid, forKey: .uid)
        try container.encode(isConnected, forKey: .isConnected)
    }
    
    
    static func saveAVDeviceChanges(changedAVDeviceName: String, isConnected: Bool) {
        // Get all saved Peripherals
        let defaults = UserDefaults.standard
        var savedDevices: [AVDevice] = defaults.structArrayData(AVDevice.self, forKey: "SAVEDAVDEVICES")
        
        // Check each saved uuid against the uuid of the activatedPeripheral
        savedDevices.forEach { (device) in
            // Once found, create a new peripheral with hasConnected = true
            let newDevice = AVDevice(name: device.name, type: device.type!, uid: device.uid, isConnected: isConnected)
            // Remove the old one, add the new one.
            savedDevices.removeAll(where: {$0.name == changedAVDeviceName})
            isConnected ? savedDevices.insert(newDevice, at: 0) : savedDevices.append(newDevice)
            
        }
        // Save it back to UserDefaults
        defaults.setStructArray(savedDevices, forKey: "SAVEDAVDEVICES")
    }
}
