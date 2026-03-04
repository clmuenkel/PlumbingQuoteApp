import SwiftUI

struct LoginView: View {
    private enum Field {
        case email
        case password
    }

    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: contentSpacing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Welcome back")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.text)

                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(AppTheme.text)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .padding(12)
                            .background(AppTheme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        SecureField("Password", text: $password)
                            .foregroundStyle(AppTheme.text)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                                Task { await authVM.signIn(email: email, password: password) }
                            }
                            .padding(12)
                            .background(AppTheme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(16)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 1)

                    if let error = authVM.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        focusedField = nil
                        Task { await authVM.signIn(email: email, password: password) }
                    } label: {
                        HStack {
                            if authVM.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 54 : 48)
                        .background(AppTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(authVM.isLoading)
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(contentPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.bg)
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

    private var contentPadding: CGFloat {
        isCompactWidth ? 16 : 24
    }

    private var contentSpacing: CGFloat {
        isCompactWidth ? 16 : 20
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
