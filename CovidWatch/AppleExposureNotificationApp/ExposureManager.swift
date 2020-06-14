/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class that manages a singleton ENManager object.
*/

import Foundation
import ExposureNotification
import UserNotifications
import os.log
import UIKit

class ExposureManager {
    
    static let shared = ExposureManager()
    
    let manager = ENManager()
    
    init() {
        manager.activate { _ in
            // Ensure exposure notifications are enabled if the app is authorized. The app
            // could get into a state where it is authorized, but exposure
            // notifications are not enabled,  if the user initially denied Exposure Notifications
            // during onboarding, but then flipped on the "COVID-19 Exposure Notifications" switch
            // in Settings.
//            if ENManager.authorizationStatus == .authorized && !self.manager.exposureNotificationEnabled {
//                self.manager.setExposureNotificationEnabled(true) { _ in
//                    // No error handling for attempts to enable on launch
//                }
//            }
        }
    }
    
    deinit {
        manager.invalidate()
    }
    
    func updateSavedExposures(newExposures : [Exposure]) {
        LocalStore.shared.exposures.append(contentsOf: newExposures)
        LocalStore.shared.exposures.sort { $0.date > $1.date }
        LocalStore.shared.dateLastPerformedExposureDetection = Date()
        LocalStore.shared.exposureDetectionErrorLocalizedDescription = nil
    }
    
    static let authorizationStatusChangeNotification = Notification.Name("ExposureManagerAuthorizationStatusChangedNotification")
    
    var detectingExposures = false
    
    private let goDeeperQueue = DispatchQueue(label: "com.ninjamonkeycoders.gaen.goDeeper", attributes: .concurrent)
    
    func detectExposures(importURLs: [URL] = [], notifyUserOnError: Bool = false, completionHandler: ((Bool) -> Void)? = nil) -> Progress {
        let progress = Progress()
        
        // Disallow concurrent exposure detection, because if allowed we might try to detect the same diagnosis keys more than once
        guard !detectingExposures else {
            completionHandler?(false)
            return progress
        }
        detectingExposures = true
        
        var localURLs = importURLs
        let nextDiagnosisKeyFileIndex = LocalStore.shared.nextDiagnosisKeyFileIndex
        
        func finish(_ result: Result<Int, Error>) {
            try? Server.shared.deleteDiagnosisKeyFile(at: localURLs)
            
            let success: Bool
            if progress.isCancelled {
                success = false
            } else {
                switch result {
                case let .success(nextDiagnosisKeyFileIndex):
                    LocalStore.shared.nextDiagnosisKeyFileIndex = nextDiagnosisKeyFileIndex
                    success = true
                case let .failure(error):
                    LocalStore.shared.exposureDetectionErrorLocalizedDescription = error.localizedDescription
                    // Consider posting a user notification that an error occured
                    success = false
                    if notifyUserOnError {
                        UIApplication.shared.topViewController?.present(error as NSError, animated: true)
                    }
                }
            }
            
            self.detectingExposures = false
            completionHandler?(success)
        }
        
        
        let actionAfterHasLocalURLs = {
            Server.shared.getExposureConfigurationList { result in
                switch result {
                case let .failure(error):
                    finish(.failure(error))
                case let .success(configurationList):
                    let semaphore = DispatchSemaphore(value: 0)
                    for configuration in configurationList{
                    ExposureManager.shared.manager.detectExposures(configuration: configuration, diagnosisKeyURLs: localURLs) { summary, error in
                            if let error = error {
                                finish(.failure(error))
                                semaphore.signal()
                                return
                            }
                            let userExplanation = NSLocalizedString("USER_NOTIFICATION_EXPLANATION", comment: "User notification")
                            ExposureManager.shared.manager.getExposureInfo(summary: summary!, userExplanation: userExplanation) { exposures, error in
                                    if let error = error {
                                        finish(.failure(error))
                                        semaphore.signal()
                                        return
                                    }
                                let scorer = AZExposureRiskScorer()
                                let newExposures: [Exposure] = exposures!.map { exposure in
    //                                var totalRiskScore = Double(exposure.totalRiskScore) * 8.0 / 255.0 // Map score between 0 and 8
    //                                if let totalRiskScoreFullRange = exposure.metadata?["totalRiskScoreFullRange"] as? Double {
    //                                    totalRiskScore = totalRiskScoreFullRange * 8.0 / 4096 // Map score between 0 and 8
    //                                }
                                    let recomputedTotalRiskScore = scorer.computeRiskScore(
                                        forAttenuationDurations: exposure.attenuationDurations,
                                        transmissionRiskLevel: exposure.transmissionRiskLevel
                                    )
                                    let e = Exposure(
                                        attenuationDurations: exposure.attenuationDurations.map({ $0.doubleValue }),
                                        attenuationValue: exposure.attenuationValue,
                                        date: exposure.date,
                                        duration: exposure.duration,
    //                                    totalRiskScore: ENRiskScore(totalRiskScore.rounded()),
    //                                    totalRiskScoreFullRange: (exposure.metadata?["totalRiskScoreFullRange"] as? Int) ?? Int(totalRiskScore.rounded()),
                                        totalRiskScore: recomputedTotalRiskScore,
                                        totalRiskScoreFullRange: Int(recomputedTotalRiskScore),
                                        transmissionRiskLevel: exposure.transmissionRiskLevel,
                                        attenuationDurationThresholds: configuration.value(forKey: "attenuationDurationThresholds") as! [Int],
                                        timeDetected : Date()
                                    )
                                    semaphore.signal()
                                    return e
                                }
                                os_log(
                                    "Detected exposures count=%d",
                                    log: .en,
                                    exposures!.count
                                )
                                //TODO: add check on progress.isCancelled here
                                self.updateSavedExposures(newExposures : newExposures)
                            }
                        }
                        semaphore.wait()
                    }
                    finish(.success(nextDiagnosisKeyFileIndex + localURLs.count))
                }
            }
        }
        
        goDeeperQueue.async {
            if localURLs.isEmpty {
                Server.shared.getDiagnosisKeyFileURLs(startingAt: nextDiagnosisKeyFileIndex) { result in
                    
                    let dispatchGroup = DispatchGroup()
                    var localURLResults = [Result<[URL], Error>]()
                    
                    switch result {
                    case let .success(remoteURLs):
                        for remoteURL in remoteURLs {
                            dispatchGroup.enter()
                            Server.shared.downloadDiagnosisKeyFile(at: remoteURL) { result in
                                localURLResults.append(result)
                                dispatchGroup.leave()
                            }
                        }
                        
                    case let .failure(error):
                        finish(.failure(error))
                    }
                    dispatchGroup.notify(queue: .main) {
                        for result in localURLResults {
                            switch result {
                            case let .success(urls):
                                localURLs.append(contentsOf: urls)
                            case let .failure(error):
                                finish(.failure(error))
                                return
                            }
                        }
                        
                        actionAfterHasLocalURLs()
                    }
                }
            }
            else {
                actionAfterHasLocalURLs()
            }
            
            
        }
        return progress
    }
    
    func getAndPostDiagnosisKeys(testResult: TestResult, transmissionRiskLevel: ENRiskLevel = 8, completion: @escaping (Error?) -> Void) {
        manager.getDiagnosisKeys { temporaryExposureKeys, error in
//        manager.getTestDiagnosisKeys { temporaryExposureKeys, error in
            if let error = error {
                completion(error)
            } else {
                // In this sample app, transmissionRiskLevel isn't set for any of the diagnosis keys. However, it is at this point that an app could
                // use information accumulated in testResult to determine a transmissionRiskLevel for each diagnosis key.
                temporaryExposureKeys?.forEach { $0.transmissionRiskLevel = transmissionRiskLevel }
                Server.shared.postDiagnosisKeys(temporaryExposureKeys!) { error in
                    completion(error)
                }
            }
        }
    }
    
    // Includes today's key, requires com.apple.developer.exposure-notification-test entitlement
    func getAndPostTestDiagnosisKeys(completion: @escaping (Error?) -> Void) {
        manager.getTestDiagnosisKeys { temporaryExposureKeys, error in
            if let error = error {
                completion(error)
            } else {
                Server.shared.postDiagnosisKeys(temporaryExposureKeys!) { error in
                    completion(error)
                }
            }
        }
    }
    
    func showBluetoothOffUserNotificationIfNeeded() {
        let identifier = "bluetooth-off"
        if ENManager.authorizationStatus == .authorized && manager.exposureNotificationStatus == .bluetoothOff {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("USER_NOTIFICATION_BLUETOOTH_OFF_TITLE", comment: "User notification title")
            content.body = NSLocalizedString("USER_NOTIFICATION_BLUETOOTH_OFF_BODY", comment: "User notification")
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error showing error user notification: \(error)")
                    }
                }
            }
        } else {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }
}
