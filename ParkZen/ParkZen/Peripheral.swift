//
//  Peripheral.swift
//  ParkZen
//
//  Created by Colin Hebert on 7/10/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import Foundation

class Peripheral: ConnectedDevice {
    
    final let savedBLEConnectedDevicesKey = "SAVEDBLEDEVICES"
    
    // Keys for encoding/decoding
    enum CodingKeys: String, CodingKey {
        case name, uuid, isConnected
    }
    
    // Unique identifier for all BT peripherals.
    var uuid: UUID? = UUID()
    
    init(name: String, uuid: UUID, isConnected: Bool) {
        super.init()
        self.name = name
        self.uuid = uuid
        self.isConnected = isConnected
    }
    
    required init(from decoder: Decoder) throws {
        super.init()
        // First we get a container.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Then we can address the container, and try to get each property with a Key.
        name = try container.decode(String.self, forKey: .name)
        let uuidStr = try container.decode(String.self, forKey: .uuid)
        uuid = UUID(uuidString: uuidStr) ?? UUID()
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
    }
    
    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(uuid?.uuidString, forKey: .uuid)
        try container.encode(isConnected, forKey: .isConnected)
    }
    
    // Saves changes to a Peripheral locally.
    static func savePeripheralChanges(changedPeripheralID: UUID, isConnected: Bool) {
        // Get all saved Peripherals
        let defaults = UserDefaults.standard
        var savedDevices: [Peripheral] = defaults.structArrayData(Peripheral.self, forKey: "SAVEDBLEDEVICES")
        
        // Check each saved uuid against the uuid of the activatedPeripheral
        savedDevices.forEach { (perif) in
            if perif.uuid == changedPeripheralID {
                // Once found, create a new peripheral with hasConnected = true
                let newPerif = Peripheral(name: perif.name, uuid: perif.uuid!, isConnected: isConnected)
                // Remove the old one, add the new one.
                savedDevices.removeAll(where: {$0.uuid == changedPeripheralID})
                isConnected ? savedDevices.insert(newPerif, at: 0) : savedDevices.append(newPerif)
            }
        }
        // Save it back to UserDefaults
        defaults.setStructArray(savedDevices, forKey: "SAVEDBLEDEVICES")
    }
}
