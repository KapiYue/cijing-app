import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var api: SupabaseAPI
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        ZStack {
            PaperBackground()
            Circle().fill(CiJingTheme.lightGreen).frame(width: 360, height: 360).blur(radius: 2).offset(x: 150, y: -300)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 70)
                    HStack(spacing: 13) {
                        Text("鲸").font(.system(size: 32, weight: .bold, design: .serif)).foregroundStyle(.white)
                            .frame(width: 58, height: 58).background(CiJingTheme.green, in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading) {
                            Text("词鲸背单词").font(.system(size: 35, weight: .bold, design: .rounded))
                            Text("READ TO REMEMBER").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(CiJingTheme.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isSignUp ? "建立你的真实阅读词库" : "欢迎回来")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("在 Chrome 里遇见，在词鲸背单词里真正掌握。")
                            .foregroundStyle(CiJingTheme.secondary)
                    }
                    VStack(spacing: 14) {
                        AuthField(title: "邮箱", icon: "envelope", text: $email, secure: false)
                        AuthField(title: "密码", icon: "lock", text: $password, secure: true)
                        if let successMessage { Text(successMessage).font(.footnote).foregroundStyle(CiJingTheme.green).frame(maxWidth: .infinity, alignment: .leading) }
                        if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(CiJingTheme.danger).frame(maxWidth: .infinity, alignment: .leading) }
                        Button(api.isAuthenticating ? "连接中…" : (isSignUp ? "创建账号" : "登录")) { Task { await authenticate() } }
                            .buttonStyle(PrimaryButtonStyle()).disabled(api.isAuthenticating)
                        Button(isSignUp ? "已有账号？登录" : "第一次使用？创建账号") { errorMessage = nil; successMessage = nil; isSignUp.toggle() }
                            .font(.subheadline.bold()).foregroundStyle(CiJingTheme.green)
                    }.cijingCard()
                    Text("邮箱账号会在浏览器扩展与 iOS App 之间安全同步；后续启用邮箱验证时，无需更换账号。")
                        .font(.system(size: 13)).foregroundStyle(CiJingTheme.secondary).padding(.horizontal, 5)
                }.padding(24)
            }
        }
    }

    private func authenticate() async {
        do {
            let mode: AuthenticationMode = isSignUp ? .signUp : .signIn
            let credentials = try AuthCredentialRules.validate(email: email, password: password, mode: mode)
            email = credentials.email
            errorMessage = nil
            successMessage = nil
            if isSignUp {
                let result = try await api.signUp(email: credentials.email, password: credentials.password)
                if result == .emailConfirmationRequired {
                    successMessage = "注册成功，请打开验证邮件完成确认后再登录。"
                    password = ""
                    isSignUp = false
                }
            } else {
                try await api.signIn(email: credentials.email, password: credentials.password)
            }
        }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AuthField: View {
    let title, icon: String; @Binding var text: String; let secure: Bool
    var body: some View {
        HStack { Image(systemName: icon).foregroundStyle(CiJingTheme.green).frame(width: 24)
            Group {
                if secure {
                    SecureField(title, text: $text).textContentType(.password)
                } else {
                    TextField(title, text: $text)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                }
            }
        }.padding(14).background(CiJingTheme.paper.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }
}
