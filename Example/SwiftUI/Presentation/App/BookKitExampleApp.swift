//
//  BookKitExampleApp.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 15/10/25.
//

import SwiftUI

@main
struct BookKitExampleApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init () {
        RealmHelper().applyMigrations()
        print("----------------------------------------------------------------")
        print("Documents path: \(FileHelper.shared.getDocumentsDirectory().path)")
        print("----------------------------------------------------------------")
        print("Temp. path: \(FileHelper.shared.getTempFolder().path)")
        print("----------------------------------------------------------------")
        FileHelper.shared.clearTempSubfolder()
    }

    var body: some Scene {
        WindowGroup {
            MainViewBuilder().build()
        }
    }
}
