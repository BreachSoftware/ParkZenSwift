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
import BackgroundTasks
import Firebase

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    let locationManager = CLLocationManager()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        let options: UNAuthorizationOptions = [.badge, .sound, .alert]
        UNUserNotificationCenter.current()
            .requestAuthorization(options: options) { success, error in
                if let error = error {
                    print("Error: \(error)")
                }
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier:
        "sumocode.ParkZen.get_location",
        using: nil)
        {task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        let defaults = UserDefaults.standard
        let myarray = defaults.stringArray(forKey: "SavedStringArray") ?? [String]()
        
        for date in myarray {
            print(date)
        }
        
        
        
        return true
        
    }
    
    // Creates a request task to run a quick location check every 30 seconds.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "sumocode.ParkZen.get_location")
        // Fetch no earlier than 30 seconds from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30)
        print("Scheduling...")
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Success!")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    // Handles the request made in scheduleAppRefresh() when it is called.
    // When the system opens the app in the background, it calls the launch handler to run the task.
    func handleAppRefresh(task: BGAppRefreshTask) {
        
        // Sends notification to the phone and adds the time to a list.
        notify()
        
        // Ends the task
        task.setTaskCompleted(success: true)
        
        // Schedule a new refresh task
        print("Rescheduling...")
        scheduleAppRefresh()
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
        //beginActivityMonitor()
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
    
    func notify() {
//        let notificationContent = UNMutableNotificationContent()
//        notificationContent.body = "He he he yep"
//        notificationContent.sound = UNNotificationSound.default
//        notificationContent.badge = UIApplication.shared.applicationIconBadgeNumber + 1 as NSNumber
//        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
//        let request = UNNotificationRequest(identifier: "background",
//                                            content: notificationContent,
//                                            trigger: trigger)
//        UNUserNotificationCenter.current().add(request) { error in
//            if let error = error {
//                print("Error: \(error)")
//            }
//        }
        
        // Get date in string form
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd hh:mm:ss"
        let now = df.string(from: Date())

        // Get the previous array and add to it
        let defaults = UserDefaults.standard
        var myarray = defaults.stringArray(forKey: "SavedStringArray") ?? [String]()
        
        myarray.append(now)
        
        // Save it back
        defaults.set(myarray, forKey: "SavedStringArray")
    }
}


extension AppDelegate: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if region is CLCircularRegion {
            //handleEvent(for: region)
            //print("AppDelete")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region is CLCircularRegion {
            //handleEvent(for: region)
            //print("AppDelete")
        }
    }
}
