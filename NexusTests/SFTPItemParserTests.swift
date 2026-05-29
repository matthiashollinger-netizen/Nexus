import Testing
@testable import Nexus

struct SFTPItemParserTests {

    private let service = SFTPService.shared

    // MARK: - Parse ls -la lines

    @Test func parseLsLineDirectory() async {
        let line = "drwxr-xr-x  2 admin  staff   4096 May 29 10:00 configs"
        let item = await service.parseLsLine(line, basePath: "/home/admin/")
        #expect(item != nil)
        #expect(item?.name == "configs")
        #expect(item?.isDirectory == true)
        #expect(item?.isSymlink == false)
        #expect(item?.permissions == "rwxr-xr-x")
        #expect(item?.owner == "admin")
        #expect(item?.group == "staff")
        #expect(item?.size == 4096)
        #expect(item?.path == "/home/admin/configs")
    }

    @Test func parseLsLineFile() async {
        let line = "-rw-r--r--  1 root  root   12345 May 15 08:30 syslog"
        let item = await service.parseLsLine(line, basePath: "/var/log/")
        #expect(item != nil)
        #expect(item?.name == "syslog")
        #expect(item?.isDirectory == false)
        #expect(item?.isSymlink == false)
        #expect(item?.permissions == "rw-r--r--")
        #expect(item?.size == 12345)
        #expect(item?.path == "/var/log/syslog")
    }

    // MARK: - Symlink parsing

    @Test func parseSymlink() async {
        let line = "lrwxrwxrwx  1 admin  wheel    11 May 29 09:00 link -> /etc/target"
        let item = await service.parseLsLine(line, basePath: "/home/admin/")
        #expect(item != nil)
        #expect(item?.name == "link")
        #expect(item?.isSymlink == true)
        #expect(item?.isDirectory == false)
        // Name should not include "-> /etc/target"
        #expect(item?.name.contains("->") == false)
    }

    @Test func parseSymlinkToDir() async {
        let line = "lrwxrwxrwx  1 root  root     7 Jan  1 2024 local -> usr/local"
        let item = await service.parseLsLine(line, basePath: "/")
        #expect(item != nil)
        #expect(item?.isSymlink == true)
        #expect(item?.name == "local")
    }

    // MARK: - Hidden file

    @Test func parseHiddenFile() async {
        let line = "-rw-------  1 user  user    512 May 20 12:00 .bash_history"
        let item = await service.parseLsLine(line, basePath: "/home/user/")
        #expect(item != nil)
        #expect(item?.name == ".bash_history")
        #expect(item?.name.hasPrefix(".") == true)
    }

    @Test func parseHiddenDirectory() async {
        let line = "drwxr-xr-x  5 user  user   4096 May 28 09:00 .config"
        let item = await service.parseLsLine(line, basePath: "/home/user/")
        #expect(item != nil)
        #expect(item?.name == ".config")
        #expect(item?.isDirectory == true)
    }

    // MARK: - File with spaces in name

    @Test func parseFileWithSpaces() async {
        let line = "-rw-r--r--  1 user  user   1024 May 29 14:00 my file name.txt"
        let item = await service.parseLsLine(line, basePath: "/docs/")
        #expect(item != nil)
        #expect(item?.name == "my file name.txt")
    }

    // MARK: - Parse full ls output

    @Test func parseLsOutput() async {
        let output = """
        total 32
        drwxr-xr-x  4 user  staff   128 May 29 10:00 .
        drwxr-xr-x 10 user  staff   320 May 29 09:00 ..
        -rw-r--r--  1 user  staff  1234 May 20 08:00 README.md
        drwxr-xr-x  2 user  staff    64 May 22 15:00 scripts
        lrwxrwxrwx  1 user  staff     6 May 28 11:00 latest -> v2.0.0
        -rw-------  1 user  staff  5678 May 29 10:30 config.yaml
        """
        let items = await service.parseLsOutput(output, basePath: "/projects/nexus/")

        // Should not include . and ..
        #expect(!items.contains { $0.name == "." })
        #expect(!items.contains { $0.name == ".." })

        // Should include all others
        #expect(items.count == 4)
        #expect(items.contains { $0.name == "README.md" })
        #expect(items.contains { $0.name == "scripts" })
        #expect(items.contains { $0.name == "latest" })
        #expect(items.contains { $0.name == "config.yaml" })

        let scriptsItem = items.first { $0.name == "scripts" }
        #expect(scriptsItem?.isDirectory == true)

        let latestItem = items.first { $0.name == "latest" }
        #expect(latestItem?.isSymlink == true)
    }

    // MARK: - Path construction

    @Test func pathConstructionWithTrailingSlash() async {
        let line = "-rw-r--r--  1 root  root  100 May 29 10:00 file.txt"
        let item = await service.parseLsLine(line, basePath: "/etc/")
        #expect(item?.path == "/etc/file.txt")
    }

    @Test func pathConstructionWithoutTrailingSlash() async {
        let line = "-rw-r--r--  1 root  root  100 May 29 10:00 file.txt"
        let item = await service.parseLsLine(line, basePath: "/etc")
        // parseLsOutput normalizes the base path by adding "/"
        let output = "-rw-r--r--  1 root  root  100 May 29 10:00 file.txt"
        let items = await service.parseLsOutput(output, basePath: "/etc")
        #expect(items.first?.path == "/etc/file.txt")
    }

    // MARK: - Permissions parsing

    @Test func permissionsStripping() async {
        let line = "drwxrwxrwx  2 user  group  4096 May 29 12:00 shared"
        let item = await service.parseLsLine(line, basePath: "/tmp/")
        // permissions should strip the type char 'd'
        #expect(item?.permissions == "rwxrwxrwx")
    }

    @Test func executableFilePermissions() async {
        let line = "-rwxr-xr-x  1 root  root  8192 May 10 06:00 startup.sh"
        let item = await service.parseLsLine(line, basePath: "/usr/local/bin/")
        #expect(item?.permissions == "rwxr-xr-x")
        #expect(item?.isDirectory == false)
    }

    // MARK: - Large file sizes

    @Test func largeFileSize() async {
        let line = "-rw-r--r--  1 user  user  1073741824 May 01 00:00 backup.tar.gz"
        let item = await service.parseLsLine(line, basePath: "/backups/")
        #expect(item?.size == 1_073_741_824)
    }

    @Test func zeroByteFile() async {
        let line = "-rw-r--r--  1 user  user  0 May 29 10:00 empty.txt"
        let item = await service.parseLsLine(line, basePath: "/tmp/")
        #expect(item?.size == 0)
    }

    // MARK: - Malformed / insufficient fields

    @Test func malformedLineReturnsNil() async {
        let line = "drwx  2 user"  // Too few fields
        let item = await service.parseLsLine(line, basePath: "/")
        #expect(item == nil)
    }

    @Test func emptyLineReturnsNil() async {
        let item = await service.parseLsLine("", basePath: "/")
        #expect(item == nil)
    }

    // MARK: - Filter hidden files

    @Test func filterHiddenFiles() async {
        let output = """
        total 16
        -rw-r--r--  1 user  user  100 May 29 10:00 visible.txt
        -rw-r--r--  1 user  user  200 May 29 10:00 .hidden
        drwxr-xr-x  2 user  user   64 May 29 10:00 .ssh
        drwxr-xr-x  2 user  user   64 May 29 10:00 public
        """
        let items = await service.parseLsOutput(output, basePath: "/home/user/")
        let hidden = items.filter { $0.name.hasPrefix(".") }
        let visible = items.filter { !$0.name.hasPrefix(".") }

        #expect(hidden.count == 2)
        #expect(visible.count == 2)
    }
}
