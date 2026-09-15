import SwiftUI

@main
struct $(LDEDisplayName)App: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
				.preferredColorScheme(.dark)
				.background(Color(UIColor.systemBackground).ignoresSafeArea())
		}
	}
}
