//
//  CSVViewerApp.swift
//  CSVViewer
//
//  Created by Andrey on 25/09/2026.
//

import SwiftUI

@main
struct CSVViewerApp: App {
  @StateObject private var viewModel: CSVViewModel

  init() {
    _viewModel = StateObject(wrappedValue: AppContainer().makeCSVViewModel())
  }

  var body: some Scene {
    WindowGroup {
      ContentView(viewModel: viewModel)
    }
  }
}
