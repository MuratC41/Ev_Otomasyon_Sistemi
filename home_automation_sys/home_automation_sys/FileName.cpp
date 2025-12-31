#include <windows.h>
#include <iostream>

int main() {
    HANDLE hSerial;
    LPCWSTR portName = L"\\\\.\\COM11";

     hSerial = CreateFileW(
        portName,
        GENERIC_READ | GENERIC_WRITE,
        0,
        0,
        OPEN_EXISTING,
        0,
        0
    );


    if (hSerial == INVALID_HANDLE_VALUE) {
        std::cerr << "COM port acilamadi\n";
        return 1;
    }

    DCB dcbSerialParams = { 0 };
    dcbSerialParams.DCBlength = sizeof(dcbSerialParams);

    GetCommState(hSerial, &dcbSerialParams);
    dcbSerialParams.BaudRate = CBR_9600;
    dcbSerialParams.ByteSize = 8;
    dcbSerialParams.StopBits = ONESTOPBIT;
    dcbSerialParams.Parity = NOPARITY;
    SetCommState(hSerial, &dcbSerialParams);

    COMMTIMEOUTS timeouts = { 0 };
    timeouts.ReadIntervalTimeout = 50;
    timeouts.ReadTotalTimeoutConstant = 50;
    timeouts.ReadTotalTimeoutMultiplier = 10;
    SetCommTimeouts(hSerial, &timeouts);

    char ch;
    DWORD bytesRead, bytesWritten;

    std::cout << "UART Echo Test Basladi...\n";

    while (true) {
        ReadFile(hSerial, &ch, 1, &bytesRead, NULL);
        if (bytesRead == 1) {
            std::cout << "PIC -> PC: " << ch << std::endl;

            WriteFile(hSerial, &ch, 1, &bytesWritten, NULL);
        }
    }

    CloseHandle(hSerial);
    return 0;
}
