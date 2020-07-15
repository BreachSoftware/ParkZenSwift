//
//  BluetoothSwitch.swift
//  ParkZen
//
//  Created by Colin Hebert on 7/10/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import Foundation
import UIKit

class DeviceSwitch: UIView {
    
    var device: ConnectedDevice = ConnectedDevice()
    
    var y = 0
    
    var uiLabel: UILabel = UILabel()
    
    var uiSwitch: UISwitch = UISwitch()
    
    init(device: ConnectedDevice, y: Int) {
        super.init(frame: CGRect(x: 0, y: y, width: 200, height: 40))
        
        self.device = device
        self.y = y
        
        
        // MARK: Label
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 21))
        
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        
        label.textColor = .white
        
        // may not be necessary (e.g., if the width & height match the superview)
        label.center = CGPoint(x: 60, y: 13)
        
        label.textAlignment = .center
        
        label.text = device.name
        
        // Adds the label to the object.
        self.addSubview(label)
        // Then sets our local variable to it.
        uiLabel = label
        
        
        // MARK: Switch
        let deviceSwitch = UISwitch(frame:CGRect(x: 150, y: 0, width: 0, height: 0))
        deviceSwitch.addTarget(self, action: #selector(ViewController.switchStateDidChange(_:)), for: .valueChanged)
        deviceSwitch.setOn(device.isConnected, animated: false)
        
        // Adds the switch to the object.
        self.addSubview(deviceSwitch)
        // And sets our local variable to it.
        uiSwitch = deviceSwitch
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
