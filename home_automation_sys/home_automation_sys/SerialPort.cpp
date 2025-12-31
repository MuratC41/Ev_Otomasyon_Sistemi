/*MURAT ÇEVLÝK 152120201067*/
#include "SerialPort.h"
#include <sstream>

using namespace std;

SerialPort::SerialPort() = default;
SerialPort::~SerialPort()
{
    close();
}

// COM port açma
bool SerialPort::open(const string& comPort, int baudRate)
{
    close();
    lastError_.clear();

    // COM10 ve üzeri için Windows özel formatý
    string full = comPort;
    if (comPort.rfind("\\\\.\\", 0) != 0)
        full = "\\\\.\\" + comPort;

    h_ = CreateFileA(
        full.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );

    if (h_ == INVALID_HANDLE_VALUE)
    {
        setLastErrorFromWin32("CreateFile");
        return false;
    }

    // Buffer boyutlarý
    SetupComm(h_, 4096, 4096);

    // Okuma / yazma zaman aþýmý ayarlarý
    COMMTIMEOUTS t{};
    t.ReadIntervalTimeout = 1;
    t.ReadTotalTimeoutConstant = 1;
    t.ReadTotalTimeoutMultiplier = 0;
    t.WriteTotalTimeoutConstant = 100;
    t.WriteTotalTimeoutMultiplier = 0;
    SetCommTimeouts(h_, &t);

    // UART ayarlarý
    DCB dcb{};
    dcb.DCBlength = sizeof(DCB);
    GetCommState(h_, &dcb);

    dcb.BaudRate = baudRate;
    dcb.ByteSize = 8;
    dcb.Parity = NOPARITY;
    dcb.StopBits = ONESTOPBIT;
    dcb.fBinary = TRUE;

    dcb.fOutxCtsFlow = FALSE;
    dcb.fOutxDsrFlow = FALSE;
    dcb.fOutX = FALSE;
    dcb.fInX = FALSE;

    dcb.fDtrControl = DTR_CONTROL_ENABLE;
    dcb.fRtsControl = RTS_CONTROL_ENABLE;

    SetCommState(h_, &dcb);

    return true;   // Port baþarýyla açýldý
}

// Portu kapatýr
void SerialPort::close()
{
    if (h_ != INVALID_HANDLE_VALUE)
    {
        CloseHandle(h_);
        h_ = INVALID_HANDLE_VALUE;
    }
}

// Port açýk mý kontrolü
bool SerialPort::isOpen() const
{
    return h_ != INVALID_HANDLE_VALUE;
}

// UART üzerinden tek byte gönderir
bool SerialPort::writeByte(uint8_t b)
{
    if (!isOpen())
    {
        lastError_ = "Port is not open";
        return false;
    }

    DWORD written = 0;
    if (!WriteFile(h_, &b, 1, &written, nullptr) || written != 1)
    {
        setLastErrorFromWin32("WriteFile");
        return false;
    }
    return true;
}

// UART üzerinden tek byte okur (timeout ile)
bool SerialPort::readByte(uint8_t& out, DWORD timeoutMs)
{
    DWORD start = GetTickCount();

    while (GetTickCount() - start < timeoutMs)
    {
        COMSTAT stat{};
        DWORD errors = 0;
        ClearCommError(h_, &errors, &stat);

        if (stat.cbInQue > 0)
        {
            DWORD read = 0;
            if (ReadFile(h_, &out, 1, &read, nullptr) && read == 1)
                return true;
        }
        Sleep(1);
    }

    lastError_ = "Read timeout";
    return false;
}

// RX buffer temizleme
void SerialPort::flushRx()
{
    if (!isOpen()) return;
    PurgeComm(h_, PURGE_RXCLEAR);
}

// Son hata mesajýný döndürür
string SerialPort::lastError() const
{
    return lastError_;
}

// Windows hata kodunu string hâline getirir
void SerialPort::setLastErrorFromWin32(const string& prefix)
{
    DWORD err = GetLastError();
    ostringstream oss;
    oss << prefix << " failed, Win32 error=" << err;
    lastError_ = oss.str();
}
