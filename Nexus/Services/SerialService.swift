import Foundation
import IOKit
import IOKit.serial

/// Manages a serial/COM port connection via POSIX termios.
final class SerialService {
    private var fd: Int32 = -1
    private var readThread: Thread?
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((SerialState) -> Void)?

    enum SerialState {
        case connected, disconnected, error(String)
    }

    func connect(port: String, baudRate: Int, dataBits: Int = 8, stopBits: String = "1", parity: String = "none", flowControl: String = "none") {
        guard !port.isEmpty else {
            onStateChange?(.error(String(localized: "serial.error.no_port")))
            return
        }

        let fileFD = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fileFD >= 0 else {
            let reason = String(cString: strerror(errno))
            onStateChange?(.error(String(format: String(localized: "serial.error.cannot_open"), port, reason)))
            return
        }

        // Exclusive access
        if ioctl(fileFD, TIOCEXCL) == -1 {
            Darwin.close(fileFD)
            onStateChange?(.error(String(format: String(localized: "serial.error.exclusive"), port)))
            return
        }

        // Remove O_NONBLOCK after opening
        if fcntl(fileFD, F_SETFL, 0) == -1 {
            Darwin.close(fileFD)
            onStateChange?(.error(String(localized: "serial.error.config")))
            return
        }

        var options = termios()
        tcgetattr(fileFD, &options)

        // Baud rate
        let speed = baudRateConstant(baudRate)
        cfsetispeed(&options, speed)
        cfsetospeed(&options, speed)

        // Raw mode
        cfmakeraw(&options)

        // Data bits
        options.c_cflag &= ~tcflag_t(CSIZE)
        switch dataBits {
        case 5: options.c_cflag |= tcflag_t(CS5)
        case 6: options.c_cflag |= tcflag_t(CS6)
        case 7: options.c_cflag |= tcflag_t(CS7)
        default: options.c_cflag |= tcflag_t(CS8)
        }

        // Stop bits
        if stopBits == "2" {
            options.c_cflag |= tcflag_t(CSTOPB)
        } else {
            options.c_cflag &= ~tcflag_t(CSTOPB)
        }

        // Parity
        switch parity.lowercased() {
        case "even":
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag &= ~tcflag_t(PARODD)
        case "odd":
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag |= tcflag_t(PARODD)
        default:
            options.c_cflag &= ~tcflag_t(PARENB)
        }

        // Flow control
        if flowControl.lowercased() == "hardware" {
            options.c_cflag |= tcflag_t(CRTSCTS)
        } else {
            options.c_cflag &= ~tcflag_t(CRTSCTS)
        }

        options.c_cflag |= tcflag_t(CREAD | CLOCAL)

        tcsetattr(fileFD, TCSANOW, &options)

        self.fd = fileFD
        onStateChange?(.connected)
        startReading()
    }

    func send(_ bytes: [UInt8]) {
        guard fd >= 0 else { return }
        bytes.withUnsafeBytes { ptr in
            _ = Darwin.write(fd, ptr.baseAddress, ptr.count)
        }
    }

    func disconnect() {
        readThread?.cancel()
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        onStateChange?(.disconnected)
    }

    func availablePorts() -> [String] {
        var portList: [String] = []
        guard let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) else { return portList }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else { return portList }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                portList.append(path)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return portList.sorted()
    }

    // MARK: - Private

    private func startReading() {
        let localFD = fd
        let thread = Thread {
            var buf = [UInt8](repeating: 0, count: 1024)
            while true {
                if Thread.current.isCancelled { break }
                let n = Darwin.read(localFD, &buf, buf.count)
                if n > 0 {
                    let bytes = Array(buf.prefix(n))
                    DispatchQueue.main.async { [weak self] in self?.onReceive?(bytes) }
                } else if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
                    break
                }
            }
        }
        thread.start()
        readThread = thread
    }

    private func baudRateConstant(_ rate: Int) -> speed_t {
        switch rate {
        case 300:    return speed_t(B300)
        case 600:    return speed_t(B600)
        case 1200:   return speed_t(B1200)
        case 2400:   return speed_t(B2400)
        case 4800:   return speed_t(B4800)
        case 9600:   return speed_t(B9600)
        case 19200:  return speed_t(B19200)
        case 38400:  return speed_t(B38400)
        case 57600:  return speed_t(B57600)
        case 115200: return speed_t(B115200)
        case 230400: return speed_t(B230400)
        default:     return speed_t(B9600)
        }
    }
}
