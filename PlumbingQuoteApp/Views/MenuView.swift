import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authVM.currentTechnician?.fullName ?? "Technician")
                            .font(.headline)
                        Text(authVM.currentTechnician?.email ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink(destination: QuoteHistoryView()) {
                        Label("Quote History", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationLink(destination: AnalyticsDashboardView()) {
                        Label("Analytics", systemImage: "chart.bar")
                    }

                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await authVM.signOut()
                            dismiss()
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Menu")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    MenuView()
        .environmentObject(AuthViewModel())
}
