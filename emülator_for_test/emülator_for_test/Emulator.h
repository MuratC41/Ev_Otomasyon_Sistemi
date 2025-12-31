#pragma once
#include <string>
#include <cstdint>

class SerialPort;

class Emulator {
public:
    enum class Mode {
        Board1_Spec,     // Board1 doküman tablosu mantığı
        Board2_Spec,     // Board2 doküman tablosu mantığı (0x01..0x08 low/high)
        Board2_ASM       // Board2 senin ASM davranışı (0x02/0x04/0x05/0x06/0x08 + 0xC0|payload set)
    };

    explicit Emulator(SerialPort& port);

    // Tek fonksiyonla çalıştırmak istersen:
    void run(Mode m);

    // İstersen ayrı ayrı da çağırabilirsin:
    void runBoard1Spec();
    void runBoard2Spec();
    void runBoard2Asm();

private:
    SerialPort& port_;

    // yardımcılar
    static int clampi(int v, int lo, int hi);
    static bool isSetLow(uint8_t b);     // 10xxxxxx
    static bool isSetHigh(uint8_t b);    // 11xxxxxx
    static uint8_t payload6(uint8_t b);  // xxxxxx

    void sleepMs(int ms);
};
