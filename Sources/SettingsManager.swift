//
//  SettingsManager.swift
//  LifetimeTracker
//
//  Created by Thanh Duc Do on 23.08.18.
//  Copyright © 2018 LifetimeTracker. All rights reserved.
//

import UIKit

struct SettingsManager {

    // On iPhone, this has no effect if the alert has preferredStyle: .actionSheet.
    // On iPad, this creates a root-less popover which mimics the appearance of an actionSheet
    // without requiring a sourceView or barButton.
    private static func createRootlessPopover(centeredOn view: UIView, alert: UIAlertController) {
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
    }

	static func showSettingsActionSheet(on viewController: UIViewController, completionHandler: @escaping (HideOption) -> Void) {
        let alert = UIAlertController(title: "Settings", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Hide LifetimeTracker", style: .default, handler: { (action: UIAlertAction) in
            let alert = UIAlertController(title: "Hide until ...", message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "more issues are detected", style: .default, handler: { (action: UIAlertAction) in
                completionHandler(.untilMoreIssue)
            }))
            alert.addAction(UIAlertAction(title: "new issue types are detected", style: .default, handler: { (action: UIAlertAction) in
                completionHandler(.untilNewIssueType)
            }))
            alert.addAction(UIAlertAction(title: "the app was restarted", style: .default, handler: { (action: UIAlertAction) in
                completionHandler(.always)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction) in
                completionHandler(.none)
            }))
            createRootlessPopover(centeredOn: viewController.view, alert: alert)
            viewController.present(alert, animated: true, completion: nil)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction) in
            completionHandler(.none)
        }))

        createRootlessPopover(centeredOn: viewController.view, alert: alert)

        viewController.present(alert, animated: true, completion: nil)
    }
}
