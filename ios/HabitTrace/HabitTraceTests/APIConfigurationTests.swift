import AuthenticationServices
import Foundation
import Testing
@testable import HabitTrace

/// Base-URL resolution must keep real devices on an HTTPS origin that App
/// Transport Security accepts while leaving simulator loopback development
/// untouched.
struct APIConfigurationTests {
    private let render = "https://habittrace-api.onrender.com"

    @Test func environmentVariableWinsOverBundledValue() {
        let url = APIConfiguration.resolve(
            environmentValue: "https://env.example.com",
            bundledValue: "https://plist.example.com",
            isSimulator: true
        )
        #expect(url.absoluteString == "https://env.example.com")
    }

    @Test func blankEnvironmentFallsThroughToBundledValue() {
        let url = APIConfiguration.resolve(
            environmentValue: "  \n",
            bundledValue: " \(render)\n",
            isSimulator: false
        )
        #expect(url.absoluteString == render)
    }

    @Test func nothingConfiguredUsesLocalBackendOnSimulator() {
        let url = APIConfiguration.resolve(environmentValue: nil, bundledValue: nil, isSimulator: true)
        #expect(url == APIConfiguration.localDevelopmentURL)
    }

    @Test func nothingConfiguredUsesProductionOnDevice() {
        let url = APIConfiguration.resolve(environmentValue: nil, bundledValue: nil, isSimulator: false)
        #expect(url == APIConfiguration.productionURL)
    }

    @Test(arguments: ["http://127.0.0.1:8001", "http://localhost:8001", "http://[::1]:8001"])
    func simulatorKeepsLoopbackURLs(raw: String) {
        let url = APIConfiguration.resolve(environmentValue: nil, bundledValue: raw, isSimulator: true)
        #expect(url.absoluteString == raw)
    }

    @Test(arguments: ["http://127.0.0.1:8001", "http://localhost:8001"])
    func deviceReplacesLoopbackWithProduction(raw: String) {
        let url = APIConfiguration.resolve(environmentValue: nil, bundledValue: raw, isSimulator: false)
        #expect(url == APIConfiguration.productionURL)
    }

    @Test(arguments: [true, false])
    func cleartextRemoteHostIsUpgradedToHTTPS(isSimulator: Bool) {
        let url = APIConfiguration.resolve(
            environmentValue: nil,
            bundledValue: "http://habittrace-api.onrender.com",
            isSimulator: isSimulator
        )
        #expect(url.absoluteString == render)
    }

    @Test func upgradePreservesNonDefaultPortAndPath() {
        let url = APIConfiguration.normalize(URL(string: "http://10.0.0.5:8001/api")!, isSimulator: false)
        #expect(url.absoluteString == "https://10.0.0.5:8001/api")
    }

    @Test func upgradeDropsExplicitPort80() {
        let url = APIConfiguration.normalize(URL(string: "http://api.example.com:80")!, isSimulator: false)
        #expect(url.absoluteString == "https://api.example.com")
    }

    @Test func httpsURLsAreLeftUnchanged() {
        let url = APIConfiguration.normalize(URL(string: "\(render)/")!, isSimulator: false)
        #expect(url.absoluteString == "\(render)/")
    }

    @Test func productionURLIsSecure() {
        #expect(APIConfiguration.productionURL.scheme == "https")
        #expect(APIConfiguration.isLoopback(APIConfiguration.productionURL) == false)
        #expect(APIConfiguration.isLoopback(APIConfiguration.localDevelopmentURL))
    }

    @Test func requestsAreBuiltAgainstTheResolvedBase() throws {
        // Whatever the simulator resolves to, every API request must inherit
        // it rather than carry its own scheme or host.
        let request = try APIClient().makeRequest(.get, path: "tasks", accessToken: "token")
        let url = try #require(request.url)
        #expect(url.scheme == APIConfiguration.baseURL.scheme)
        #expect(url.host() == APIConfiguration.baseURL.host())
        #expect(url.path() == APIConfiguration.baseURL.appending(path: "tasks").path())
    }
}

/// Pure helpers behind the native Google sign-in and deep-link flows.
struct AuthCallbackTests {
    @Test func callbackURLsUseTheRegisteredScheme() throws {
        let schemes = try #require(
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])?
                .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )
        #expect(schemes.contains(AuthManager.authCallbackURL.scheme ?? ""))
        #expect(schemes.contains(AuthManager.passwordResetURL.scheme ?? ""))
    }

    @Test func dismissingTheGoogleSheetIsACancellation() {
        #expect(AuthManager.isUserCancellation(ASWebAuthenticationSessionError(.canceledLogin)))
        #expect(AuthManager.isUserCancellation(URLError(.cancelled)) == false)
        #expect(AuthManager.isUserCancellation(ASWebAuthenticationSessionError(.presentationContextNotProvided)) == false)
    }

    @Test func recoveryLinksAreDistinguishedFromSignInCallbacks() {
        #expect(AuthManager.isPasswordRecoveryLink(URL(string: "habittrace://reset-password?code=abc")!))
        #expect(AuthManager.isPasswordRecoveryLink(URL(string: "habittrace://auth-callback#type=recovery")!))
        #expect(AuthManager.isPasswordRecoveryLink(URL(string: "habittrace://auth-callback?code=abc")!) == false)
    }
}
