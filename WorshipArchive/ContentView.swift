import SwiftUI

struct ContentView: View {
    @State private var selection: AppDestination = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView { destination in
                    selection = destination
                }
            }
            .tabItem {
                Label(AppDestination.home.title, systemImage: AppDestination.home.systemImage)
            }
            .tag(AppDestination.home)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label(AppDestination.search.title, systemImage: AppDestination.search.systemImage)
            }
            .tag(AppDestination.search)

            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label(AppDestination.library.title, systemImage: AppDestination.library.systemImage)
            }
            .tag(AppDestination.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(AppDestination.settings.title, systemImage: AppDestination.settings.systemImage)
            }
            .tag(AppDestination.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView()
}
