import Foundation

struct AppSettings: Codable {
    var language: String = {
        Locale.current.language.languageCode?.identifier == "de" ? "de" : "en"
    }()
    var sshLegacyAlgorithms: Bool = true
    var terminalFontName: String = "Menlo"
    var terminalFontSize: Double = 13.0
    var defaultSSHPort: Int = 22
    var defaultTelnetPort: Int = 23
    var masterPasswordEnabled: Bool = false
}
