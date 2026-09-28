//
//  CSVViewerApp.swift
//  CSVViewer
//
//  Created by Andrey on 25/09/2026.
//

import SwiftUI

@main
struct CSVViewerApp: App {
  @State private var viewModel: CSVViewModel

  init() {
    _viewModel = State(initialValue: AppContainer().makeCSVViewModel())
  }

  var body: some Scene {
    WindowGroup {
      ContentView(viewModel: viewModel)
    }
  }
}
