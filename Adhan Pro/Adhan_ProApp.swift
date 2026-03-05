//
//  Adhan_ProApp.swift
//  Adhan Pro
//
//  Created by Anas Khan on 05/03/26.
//

import SwiftUI
import CoreData

@main
struct Adhan_ProApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
