import Testing
import Foundation
@testable import Nexus

/// Tests for the Termius-format CSV import (previously untested + untestable because
/// it wrote straight to the database; now a pure `parseImportCSV` is exercised).
@MainActor
struct CSVImportTests {

    @Test func basicImport() {
        let csv = """
        Group,Label,Address,Hostname,Protocol,Port,Username
        Lab,Switch1,x,10.0.0.1,ssh,2222,admin
        Lab,Router1,x,10.0.0.2,telnet,23,root
        """
        let (sessions, folders) = AppViewModel.parseImportCSV(csv, existingFolders: [])
        #expect(sessions.count == 2)
        #expect(folders.count == 1)               // "Lab" created exactly once
        #expect(sessions[0].host == "10.0.0.1")
        #expect(sessions[0].port == 2222)
        #expect(sessions[0].connectionType == .ssh)
        #expect(sessions[1].connectionType == .telnet)
        #expect(sessions.allSatisfy { $0.folderId == folders[0].id })
    }

    @Test func reusesExistingFolder() {
        var existing = Folder(); existing.name = "Lab"
        let csv = "header\nLab,S,x,10.0.0.1,ssh,22,u\n"
        let (sessions, folders) = AppViewModel.parseImportCSV(csv, existingFolders: [existing])
        #expect(sessions.count == 1)
        #expect(folders.isEmpty)                  // reused existing → no new folder
        #expect(sessions[0].folderId == existing.id)
    }

    @Test func skipsMalformedRows() {
        let csv = "header\nGroup,Label,x,host,ssh,22,user\nbad,row\n"
        let (sessions, _) = AppViewModel.parseImportCSV(csv, existingFolders: [])
        #expect(sessions.count == 1)              // only the valid 7-field row
    }

    @Test func skipsRowsWithEmptyHost() {
        let csv = "header\nGroup,Label,x,,ssh,22,user\n"
        let (sessions, _) = AppViewModel.parseImportCSV(csv, existingFolders: [])
        #expect(sessions.isEmpty)
    }

    @Test func quotedFieldsWithCommas() {
        let csv = "header\n\"My, Group\",\"Label, X\",x,10.0.0.1,ssh,22,user\n"
        let (sessions, folders) = AppViewModel.parseImportCSV(csv, existingFolders: [])
        #expect(sessions.count == 1)
        #expect(folders.first?.name == "My, Group")
        #expect(sessions.first?.name == "Label, X")
    }

    @Test func emptyAndHeaderOnly() {
        #expect(AppViewModel.parseImportCSV("", existingFolders: []).sessions.isEmpty)
        #expect(AppViewModel.parseImportCSV("only,a,header\n", existingFolders: []).sessions.isEmpty)
    }

    @Test func defaultsPortWhenMissing() {
        let csv = "header\nG,L,x,host,telnet,,user\n"   // empty port field
        let (sessions, _) = AppViewModel.parseImportCSV(csv, existingFolders: [])
        #expect(sessions.first?.port == 23)       // telnet default
    }

    @Test func malformedFileDoesNotCrash() {
        // Garbage / binary-ish content must be handled, not crash.
        let garbage = "\u{0}\u{1}\u{2},,,\n\"unterminated quote,,,,\n\n\t\t\t"
        let (sessions, folders) = AppViewModel.parseImportCSV(garbage, existingFolders: [])
        #expect(sessions.isEmpty || !sessions.isEmpty)   // just must not crash
        #expect(folders.isEmpty || !folders.isEmpty)
    }

    @Test func unknownProtocolDefaultsToSSH() {
        let csv = "header\nG,L,x,host,vnc,5900,user\n"
        let (sessions, _) = AppViewModel.parseImportCSV(csv, existingFolders: [])
        #expect(sessions.first?.connectionType == .ssh)
    }
}
