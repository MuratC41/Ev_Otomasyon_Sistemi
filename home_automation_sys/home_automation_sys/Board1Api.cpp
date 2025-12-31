/*MURAT ÇEVLÝK 152120201067*/
#include "Board1Api.h"
#include <cmath>

using namespace std;

Board1Api::Board1Api(SerialPort& port) : port_(port) {}

// Ýstenen sýcaklýðý okur
bool Board1Api::getDesired(float& outC)
{
    return getTemp(CMD_GET_DESIRED_H, CMD_GET_DESIRED_L, outC);
}

// Ortam sýcaklýðýný okur
bool Board1Api::getAmbient(float& outC)
{
    return getTemp(CMD_GET_AMBIENT_H, CMD_GET_AMBIENT_L, outC);
}

// Fan hýzýný okur (tek byte)
bool Board1Api::getFanSpeed(int& out)
{
    uint8_t b = 0;
    if (!getByte(CMD_GET_FAN_SPEED, b))
        return false;

    out = (int)b;
    return true;
}

// Ýstenen sýcaklýðý PIC tarafýna gönderir
bool Board1Api::setDesired(float tempC)
{
    // Mantýksýz deðer gelirse iptal et
    if (tempC != tempC)   // NaN kontrolü (öðrenci usulü)
        return false;

    // Güvenli aralýk (dokümana uygun)
    if (tempC < 10.0f) tempC = 10.0f;
    if (tempC > 50.0f) tempC = 50.0f;

    int intPart = (int)floor(tempC);                 // Tam kýsým
    int fracPart = (int)((tempC - intPart) * 10.0f);  // Ondalýk kýsým

    // 24.99 gibi durumlar için
    if (fracPart >= 10)
    {
        intPart++;
        fracPart = 0;
    }

    // PIC 6-bit kullandýðý için sýnýrlandýrýyoruz
    if (intPart < 0)  intPart = 0;
    if (intPart > 63) intPart = 63;

    if (fracPart < 0) fracPart = 0;
    if (fracPart > 9) fracPart = 9;

    uint8_t highByte = (uint8_t)(CMD_SET_HIGH | (intPart & 0x3F));
    uint8_t lowByte = (uint8_t)(CMD_SET_LOW | (fracPart & 0x3F));

    // Önce RX buffer temizlenir
    port_.flushRx();

    if (!port_.writeByte(highByte)) return false;
    if (!port_.writeByte(lowByte))  return false;

    // SET komutunda cevap yok
    return true;
}

// Tüm deðerleri tek seferde okur
bool Board1Api::getAll(Board1Status& st)
{
    if (!getDesired(st.desiredC))  return false;
    if (!getAmbient(st.ambientC))  return false;
    if (!getFanSpeed(st.fanSpeed)) return false;

    return true;
}

// UART üzerinden komut gönderip cevap alma
bool Board1Api::txrx(uint8_t cmd, uint8_t& out, DWORD timeoutMs, bool flushBefore)
{
    if (!port_.isOpen())
        return false;

    if (flushBefore)
        port_.flushRx();

    if (!port_.writeByte(cmd))
        return false;

    return port_.readByte(out, timeoutMs);
}

// Ýki byte ile sýcaklýk okuma (H + L)
bool Board1Api::getTemp(uint8_t cmdH, uint8_t cmdL, float& outC)
{
    uint8_t h = 0, l = 0;

    // Ýlk komutta buffer temizlenir
    if (!txrx(cmdH, h, 500, true))  return false;
    if (!txrx(cmdL, l, 500, false)) return false;

    outC = combineTemp(h, l);
    return true;
}

// Tek byte okuma (fan gibi)
bool Board1Api::getByte(uint8_t cmd, uint8_t& out)
{
    return txrx(cmd, out, 500, true);
}

// Gelen H ve L byte'larýný float sýcaklýða çevirir
float Board1Api::combineTemp(uint8_t h, uint8_t l)
{
    // L: ondalýk kýsým (0..9)
    return (float)h + ((float)l / 10.0f);
}
