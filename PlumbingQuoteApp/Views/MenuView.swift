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
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    NavigationLink(destination: QuoteHistoryView()) {
                        Label("Quote History", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(AppTheme.text)
                    }

                    NavigationLink(destination: AnalyticsDashboardView()) {
                        Label("Analytics", systemImage: "chart.bar")
                            .foregroundStyle(AppTheme.text)
                    }

                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                            .foregroundStyle(AppTheme.text)
                    }
                }
                .listRowBackground(AppTheme.surface)

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
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .tint(AppTheme.muted)
            .navigationTitle("Menu")
            .toolbarBackground(AppTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
