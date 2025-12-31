#pragma once
#include <windows.h>
#include <string>
#include <cstdint>

class SerialPort {
public:
    SerialPort();
    ~SerialPort();

    // Non-copyable
    SerialPort(const SerialPort&) = delete;
    SerialPort& operator=(const SerialPort&) = delete;

    bool open(const std::string& comPort, int baudRate = 9600);
    void close();
    bool isOpen() const;

    bool writeByte(uint8_t b);

    // Reads a single byte with timeout; returns true if a byte was read.
    bool readByte(uint8_t& out, DWORD timeoutMs);

    // Optional: flush only RX
    void flushRx();

    std::string lastError() const;

private:
    HANDLE h_ = INVALID_HANDLE_VALUE;
    std::string lastError_;

    void setLastErrorFromWin32(const std::string& prefix);
};
