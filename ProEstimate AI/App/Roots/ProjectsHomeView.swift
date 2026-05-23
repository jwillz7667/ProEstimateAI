import SwiftUI

/// Root of the Projects tab. Hosts the home dashboard (greeting + hero CTA +
/// recent visions + active quotes). Owns the `projectsPath` NavigationStack
/// so any pushed destination (project detail, full project list, lawn map,
/// roof scouting, client detail) lives under this tab.
///
/// During the overhaul this delegates to the existing `DashboardView`
/// content. Task #4 replaces the body with the new home layout.
struct ProjectsHomeView: View {
    var body: some View {
        DashboardView()
    }
}
