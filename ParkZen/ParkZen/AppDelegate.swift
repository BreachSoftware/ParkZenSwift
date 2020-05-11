//
//  AppDelegate.swift
//  ParkZen
//
//  Created by Colin Hebert on 4/2/20.
//  Copyright © 2020 Colin Hebert. All rights reserved.
//

import UIKit
import CoreLocation
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    func note(from identifier: String) -> String? {
      let geotifications = Geotification.allGeotifications()
      guard let matched = geotifications.filter({
        $0.identifier == identifier
      }).first else { return nil }
      return matched.note
    }
    
    func handleEvent(for region: CLRegion!) {
      // Show an alert if application is active
      if UIApplication.shared.applicationState == .active {
        guard let message = note(from: region.identifier) else { return }
        window?.rootViewController?.showAlert(withTitle: nil, message: message)
      } else {
        // Otherwise present a local notification
        guard let body = note(from: region.identifier) else { return }
        let notificationContent = UNMutableNotificationContent()
        notificationContent.body = body
        notificationContent.sound = UNNotificationSound.default
        notificationContent.badge = UIApplication.shared.applicationIconBadgeNumber + 1 as NSNumber
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "location_change",
                                            content: notificationContent,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
          if let error = error {
            print("Error: \(error)")
          }
        }
      }
    }
}

extension AppDelegate: CLLocationManagerDelegate {
  
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    if region is CLCircularRegion {
      handleEvent(for: region)
    }
  }
  
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    if region is CLCircularRegion {
      handleEvent(for: region)
    }
  }
}
