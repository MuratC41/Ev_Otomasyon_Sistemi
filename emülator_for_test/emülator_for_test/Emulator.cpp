#include "Emulator.h"
#include "SerialPort.h"

#include <iostream>
#include <chrono>
#include <thread>
#include <cstdlib>

// ----------------- Dahili simülasyon durumları -----------------

// Board1 (dokümana göre): sıcaklık = tam + ondalık (0..9)
struct Board1State
{
    int desiredInt = 24;   // 10..50
    int desiredFrac = 0;   // 0..9

    int ambientInt = 26;   // Simüle edilen ortam sıcaklığı
    int ambientFrac = 3;

    int fanRps = 5;        // Simüle edilen fan hızı

    void tick()
    {
        // Ortam sıcaklığı 22.0 .. 32.0 arası gezsin
        static int dir = 1;
        int amb10 = ambientInt * 10 + ambientFrac;
        amb10 += dir;

        if (amb10 >= 320) dir = -1;
        if (amb10 <= 220) dir = 1;

        ambientInt = amb10 / 10;
        ambientFrac = amb10 % 10;

        // Fan hızı, istenen ve ortam sıcaklığı farkına göre ayarlansın
        int des10 = desiredInt * 10 + desiredFrac;
        int diff10 = amb10 - des10;

        int base = 3;
        int computed = base + (diff10 < 0 ? -diff10 : diff10) / 5;

        if (computed < 0)  computed = 0;
        if (computed > 20) computed = 20;

        fanRps = computed;
    }
};

// Board2 (Spec - doküman mantığı)
struct Board2StateSpec
{
    int curtainInt = 45;   // 0..100
    int curtainFrac = 0;

    int tempInt = 27;      // 20..35
    int tempFrac = 5;

    int pressH = 10;       // 1000'ler
    int pressL = 13;       // 0..31

    int lightInt = 120;    // 0..255
    int lightFrac = 0;

    void tick()
    {
        tempFrac = (tempFrac + 1) % 10;
        if (tempFrac == 0)
        {
            tempInt++;
            if (tempInt > 35) tempInt = 20;
        }

        pressL++;
        if (pressL > 31) pressL = 0;

        lightInt++;
        if (lightInt > 255) lightInt = 0;
    }
};

// Board2 (ASM davranışına göre)
struct Board2StateAsm
{
    int curtain = 50;  // 0..100
    int temp = 28;     // 20..35
    int pressH = 10;
    int pressL = 12;
    int ldr = 100;     // 0..255

    void tick()
    {
        temp++;
        if (temp > 35) temp = 20;

        pressL++;
        if (pressL > 31) pressL = 0;

        ldr += 3;
        if (ldr > 255) ldr = 0;
    }
};

// ----------------- Emulator -----------------

Emulator::Emulator(SerialPort& port) : port_(port) {}

void Emulator::run(Mode m)
{
    switch (m)
    {
    case Mode::Board1_Spec: runBoard1Spec(); break;
    case Mode::Board2_Spec: runBoard2Spec(); break;
    case Mode::Board2_ASM:  runBoard2Asm();  break;
    default:                runBoard1Spec(); break;
    }
}

// Değeri verilen aralıkta tutmak için
int Emulator::clampi(int v, int lo, int hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// UART set komutlarını ayırt etmek için
bool Emulator::isSetLow(uint8_t b) { return (b & 0xC0) == 0x80; } // 10xxxxxx
bool Emulator::isSetHigh(uint8_t b) { return (b & 0xC0) == 0xC0; } // 11xxxxxx

// 6-bit veri kısmını ayıklar
uint8_t Emulator::payload6(uint8_t b)
{
    return (uint8_t)(b & 0x3F);
}

void Emulator::sleepMs(int ms)
{
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

// ----------------- Board1 Spec Emulator -----------------
void Emulator::runBoard1Spec()
{
    Board1State st;
    std::cout << "[EMU] Board1 (Spec) running.\n";

    while (true)
    {
        uint8_t cmd = 0;
        bool got = port_.readByte(cmd, 50);

        if (!got)
        {
            st.tick();
            continue;
        }

        // SET komutları (istenen sıcaklık)
        if (isSetLow(cmd))
        {
            st.desiredFrac = clampi((int)payload6(cmd), 0, 9);
            continue;
        }
        if (isSetHigh(cmd))
        {
            st.desiredInt = clampi((int)payload6(cmd), 10, 50);
            continue;
        }

        uint8_t resp = 0;
        switch (cmd)
        {
        case 0x01: resp = (uint8_t)st.desiredFrac; break;
        case 0x02: resp = (uint8_t)st.desiredInt;  break;
        case 0x03: resp = (uint8_t)st.ambientFrac; break;
        case 0x04: resp = (uint8_t)st.ambientInt;  break;
        case 0x05: resp = (uint8_t)st.fanRps;      break;
        default:   continue;
        }

        port_.writeByte(resp);
    }
}

// ----------------- Board2 Spec Emulator -----------------
void Emulator::runBoard2Spec()
{
    Board2StateSpec st;
    std::cout << "[EMU] Board2 (Spec) running.\n";

    while (true)
    {
        uint8_t cmd = 0;
        bool got = port_.readByte(cmd, 50);

        if (!got)
        {
            st.tick();
            continue;
        }

        // SET komutları (perde)
        if (isSetLow(cmd))
        {
            st.curtainFrac = clampi((int)payload6(cmd), 0, 9);
            continue;
        }
        if (isSetHigh(cmd))
        {
            st.curtainInt = clampi((int)payload6(cmd), 0, 100);
            continue;
        }

        uint8_t resp = 0;
        switch (cmd)
        {
        case 0x01: resp = (uint8_t)st.curtainFrac; break;
        case 0x02: resp = (uint8_t)st.curtainInt;  break;
        case 0x03: resp = (uint8_t)st.tempFrac;    break;
        case 0x04: resp = (uint8_t)st.tempInt;     break;
        case 0x05: resp = (uint8_t)st.pressL;      break;
        case 0x06: resp = (uint8_t)st.pressH;      break;
        case 0x07: resp = (uint8_t)st.lightFrac;   break;
        case 0x08: resp = (uint8_t)st.lightInt;    break;
        default:   continue;
        }

        port_.writeByte(resp);
    }
}

// ----------------- Board2 ASM Emulator -----------------
void Emulator::runBoard2Asm()
{
    Board2StateAsm st;
    std::cout << "[EMU] Board2 (ASM) running.\n";

    while (true)
    {
        uint8_t cmd = 0;
        bool got = port_.readByte(cmd, 50);

        if (!got)
        {
            st.tick();
            continue;
        }

        // ASM tarafında sadece 11xxxxxx set kabul edilir
        if (isSetHigh(cmd))
        {
            int raw6 = (int)payload6(cmd);
            int scaled = (raw6 * 100 + 31) / 63;   // %0..100'e çevirme
            st.curtain = clampi(scaled, 0, 100);
            continue;
        }

        uint8_t resp = 0;
        switch (cmd)
        {
        case 0x02: resp = (uint8_t)st.curtain; break;
        case 0x04: resp = (uint8_t)st.temp;    break;
        case 0x05: resp = (uint8_t)st.pressL;  break;
        case 0x06: resp = (uint8_t)st.pressH;  break;
        case 0x08: resp = (uint8_t)st.ldr;     break;
        default:   continue;
        }

        port_.writeByte(resp);
    }
}
