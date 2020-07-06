//
//  LoginViewController.swift
//  ParkZen
//
//  Created by Colin Hebert on 7/3/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import Foundation
import UIKit

let isLoggedInKey = "ISLOGGEDIN"


class LoginViewController: UIViewController {
    
    @IBOutlet weak var splashScreen: UIImageView!
    
    @IBAction func loginTapped(_ sender: Any) {
        navigateToMain()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if UserDefaults.standard.bool(forKey: isLoggedInKey) {
            navigateToMain()
        }
        else {
            splashScreen.isHidden = true
        }
        
    }
    
    func navigateToMain() {
        
        UserDefaults.standard.set(true, forKey: isLoggedInKey)
        
        let mainTabController = storyboard?.instantiateViewController(identifier: "MainTabBarController") as! MainTabBarController
        
        mainTabController.modalPresentationStyle = .fullScreen
        
        show(mainTabController, sender: nil)
    }
    
}
