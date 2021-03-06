//
//  Created by Zsombor Szabo on 26/04/2020.
//

import UIKit
import CoreData
import ExposureNotification

import os.log
import SwiftUI

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    // Background tasks
    var isPerformingBackgroundExposureNotification = false
    
    // Diagnosis server
    lazy var diagnosisServer: DiagnosisServer = {
        let appScheme = getAppScheme()
        switch appScheme {
            case .development:
                // TODO
                return GCPGoogleExposureNotificationServer(
                    exposureURLString: getAPIUrl(appScheme) + "/publish",
                    appConfiguration: AppConfiguration(regions: ["US"]),
                    exportConfiguration: ExportConfiguration(
                        filenameRoot: "exposureKeyExport-US",
                        bucketName: "exposure-notification-export-ibznj"
                    )
            )
            case .production:
                // This returns the configuration for the sandbox CW EN server
                return GCPGoogleExposureNotificationServer(
                    exposureURLString: "https://exposure-2sav64smma-uc.a.run.app/",
                    appConfiguration: AppConfiguration(regions: ["US"]),
                    exportConfiguration: ExportConfiguration(
                        filenameRoot: "exposureKeyExport-US",
                        bucketName: "exposure-notification-export-ibznj"
                    )
            )
        }
    }()
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        os_log(
            "Starting app with scheme=%@ and API Url=%@",
            log: .app,
            getAppScheme().description,
            getAPIUrl(getAppScheme())
        )
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        self.window?.tintColor = UIColor(named: "Tint Color")
        window.makeKeyAndVisible()
        let contentView = ContentView()
            .environmentObject(UserData.shared)
            .environmentObject(LocalStore.shared)
        self.window?.rootViewController = UIHostingController(rootView: contentView)
        
        // Setup diagnosis server
        Server.shared.diagnosisServer = self.diagnosisServer
                
        _ = ExposureManager.shared
        _ = ApplicationController.shared
        
        // Setup Background tasks
        self.setupBackgroundTask()
        
        // Setup User notification
        self.configureCurrentUserNotificationCenter()
        self.requestUserNotificationAuthorization(provisional: true)
        
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {

        do {
            guard let cachesDirectoryURL = FileManager.default.urls(
                    for: .cachesDirectory,
                    in: .userDomainMask
                ).first else {
                    throw(CocoaError(.fileNoSuchFile))
            }
            let unzipDestinationDirectory = cachesDirectoryURL.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: unzipDestinationDirectory, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.unzipItem(at: url, to: unzipDestinationDirectory)
            try FileManager.default.removeItem(at: url)
            let zipFileContentURLs = try FileManager.default.contentsOfDirectory(at: unzipDestinationDirectory, includingPropertiesForKeys: nil)
            let filteredZIPFileContentURLs = zipFileContentURLs.filter { (url) -> Bool in
                let size: UInt64 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
                return size != 0
            }
            let result = filteredZIPFileContentURLs
            
            _ = ExposureManager.shared.detectExposures(importURLs: result, notifyUserOnError: true) { success in
                os_log(
                    "Detected exposures from file=%@ success=%d",
                    log: .app,
                    url.description,
                    success
                )
            }
        } catch {
            UIApplication.shared.topViewController?.present(
                error as NSError,
                animated: true
            )
        }

        return true
    }
}
