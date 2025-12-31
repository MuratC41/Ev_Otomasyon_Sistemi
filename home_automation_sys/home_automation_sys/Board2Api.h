/*MURAT ÇEVLÝK 152120201067*/
#include <cstdint>
#include "SerialPort.h"

using namespace std;

/*
    Board2Status:
    Board #2 (Curtain Control) için
    okunan tüm deðerleri tek yapýda toplamak amacýyla kullanýlýr
*/
struct Board2Status
{
    float  curtainPercent;     // Perde durumu (%0..100)
    float  outdoorTempC;       // Dýþ ortam sýcaklýðý (°C)
    float  outdoorPressHpa;    // Dýþ ortam basýncý (hPa)
    double lightLux;           // Iþýk þiddeti (ham byte, Lux olarak gösteriliyor)
};

/*
    Board2Api:
    PC tarafýnýn Board #2 ile UART üzerinden
    haberleþmesini saðlayan sýnýf
*/
class Board2Api
{
private:
    SerialPort& port;   // UART haberleþmesi için kullanýlan port
    
    // UART üzerinden komut gönderip 1 byte cevap alýr
    bool txrx(uint8_t cmd, uint8_t& out, unsigned timeoutMs = 200);

public:
    explicit Board2Api(SerialPort& p);

    // Perde durumunu okur (board 0..63 gönderir, PC tarafýnda %0..100'e çevrilir)
    bool getCurtainStatus(float& outPercent);

    // Dýþ ortam sýcaklýðýný okur
    bool getOutdoorTemp(float& outC);

    // Dýþ ortam basýncýný okur
    bool getOutdoorPressure(float& outHpa);

    // Iþýk þiddetini okur
    bool getLightIntensity(double& outLux);

    // Tüm deðerleri tek seferde okur
    bool getAll(Board2Status& out);

    /*
        Perde durumunu ayarlamak için kullanýlýr
        Not: ASM tarafý sadece 6-bit (0..63) kabul ettiði için
        0..100 aralýðý PC tarafýnda bu aralýða çevrilir
    */
    bool setCurtainStatus(float percent);
};
