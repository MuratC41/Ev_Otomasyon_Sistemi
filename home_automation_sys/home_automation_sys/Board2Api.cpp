/*MURAT ÇEVLİK 152120201067*/
#include "Board2Api.h"
#include <algorithm> // clamp
using namespace std;

Board2Api::Board2Api(SerialPort& p) : port(p) {}

bool Board2Api::txrx(uint8_t cmd, uint8_t& out, unsigned timeoutMs)
{
    if (!port.isOpen()) return false;

    // Clear stale bytes before request
    port.flushRx();

    if (!port.writeByte(cmd)) return false;

    uint8_t b = 0;
    if (!port.readByte(b, static_cast<DWORD>(timeoutMs))) return false;

    out = b;
    return true;
}

bool Board2Api::getCurtainStatus(float& outPercent)
{
    uint8_t raw = 0;
    if (!txrx(0x02, raw)) return false;

    // raw (0..63) → percent (0..100)
    outPercent = static_cast<float>((raw * 100 + 31) / 63);
    // +31 → düzgün yuvarlama için
    
    return true;
}


bool Board2Api::getOutdoorTemp(float& outC)
{
    // ASM mapping: 0x04 -> Temp_Value
    uint8_t v = 0;
    if (!txrx(0x04, v)) return false;
    outC = static_cast<float>(v);
    return true;
}

bool Board2Api::getOutdoorPressure(float& outHpa)
{
    // ASM mapping: 0x05 -> Press_Value_L
    //              0x06 -> Press_Value_H (ASM returns 10)
    uint8_t pL = 0, pH = 0;
    if (!txrx(0x05, pL)) return false;
    if (!txrx(0x06, pH)) return false;

    // e.g., pH=10, pL=0..31 => 1000..1031
    outHpa = static_cast<float>(static_cast<int>(pH) * 100 + static_cast<int>(pL));
    return true;
}

bool Board2Api::getLightIntensity(double& outLux)
{
    // ASM mapping: 0x08 -> LDR_Raw
    uint8_t v = 0;
    if (!txrx(0x08, v)) return false;
    outLux = static_cast<double>(v);
    return true;
}

bool Board2Api::getAll(Board2Status& out)
{
    float c = 0, t = 0, p = 0;
    double l = 0;

    if (!getCurtainStatus(c)) return false;
    if (!getOutdoorTemp(t)) return false;
    if (!getOutdoorPressure(p)) return false;
    if (!getLightIntensity(l)) return false;

    out.curtainPercent = c;
    out.outdoorTempC = t;
    out.outdoorPressHpa = p;
    out.lightLux = l;
    return true;
}

bool Board2Api::setCurtainStatus(float percent)
{
    if (!port.isOpen()) return false;

    // clamp 0..100
    percent = clamp(percent, 0.0f, 100.0f);

    // ASM UART set accepts only 6-bit payload in 11xxxxxx form.
    // Map 0..100% -> 0..63
    int raw6 = static_cast<int>(percent * 63.0f / 100.0f + 0.5f);
    if (raw6 < 0) raw6 = 0;
    if (raw6 > 63) raw6 = 63;

    uint8_t cmd = static_cast<uint8_t>(0xC0 | (raw6 & 0x3F));

    port.flushRx();
    return port.writeByte(cmd);
}
