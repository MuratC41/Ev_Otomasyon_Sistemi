/*MURAT ÇEVLÝK 152120201067*/
#pragma once
#include <windows.h>
#include <cstdint>
#include <string>

using namespace std;

/*
    SerialPort:
    Windows üzerinde COM port (UART) haberleþmesini
    gerçekleþtirmek için kullanýlan sýnýf
*/
class SerialPort
{
private:
    HANDLE h_ = INVALID_HANDLE_VALUE; // Açýlan COM port handle'ý
    string lastError_;                // Son oluþan hata mesajý

    // Windows API'den gelen hata kodunu string'e çevirir
    void setLastErrorFromWin32(const string& prefix);

public:
    SerialPort();
    ~SerialPort();
    
    // Kopyalanmasý istenmiyor (tek port, tek sahip)
    SerialPort(const SerialPort&) = delete;
    SerialPort& operator=(const SerialPort&) = delete;
    
    // COM port açma (örnek: "COM10")
    bool open(const string& comPort, int baudRate = 9600);

    // Portu kapatýr
    void close();

    // Port açýk mý kontrolü
    bool isOpen() const;

    // UART üzerinden tek byte gönderir
    bool writeByte(uint8_t b);

    // UART üzerinden tek byte okur (timeout ile)
    bool readByte(uint8_t& out, DWORD timeoutMs);

    // Sadece RX buffer'ýný temizler
    void flushRx();

    // Son hata mesajýný döndürür
    string lastError() const;
};
