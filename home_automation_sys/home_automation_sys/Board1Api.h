/*MURAT ÇEVLÝK 152120201067*/
#include "SerialPort.h"
#include <cstdint>

using namespace std;

/*
    Board1Status:
    Board #1 (Air Conditioner) için
    tüm deðerleri tek seferde tutmak amacýyla kullanýlan yapý
*/
struct Board1Status
{
    float desiredC = 0.0f;   // Kullanýcýnýn istediði sýcaklýk (°C)
    float ambientC = 0.0f;   // Ortam sýcaklýðý (°C)
    int fanSpeed = 0;        // Fan hýzý (PIC tarafýnda sayýlan ham deðer)
};

/*
    Board1Api:
    PC uygulamasýnýn Board #1 ile UART üzerinden
    haberleþmesini saðlayan sýnýf
*/
class Board1Api
{
private:
    SerialPort& port_;   // UART haberleþmesi için kullanýlan SerialPort referansý

    // ===== UART KOMUTLARI (ASM tarafýna göre) =====

    // Okuma (GET) komutlarý
    static constexpr uint8_t CMD_GET_DESIRED_L = 0x01;   // Ýstenen sýcaklýk - ondalýk kýsým
    static constexpr uint8_t CMD_GET_DESIRED_H = 0x02;   // Ýstenen sýcaklýk - tam kýsým
    static constexpr uint8_t CMD_GET_AMBIENT_L = 0x03;   // Ortam sýcaklýðý - ondalýk kýsým
    static constexpr uint8_t CMD_GET_AMBIENT_H = 0x04;   // Ortam sýcaklýðý - tam kýsým
    static constexpr uint8_t CMD_GET_FAN_SPEED = 0x05;   // Fan hýzý

    // Yazma (SET) komutlarý
    // Not: PIC tarafýnda bit7 = 1 ise SET komutu olarak algýlanýr
    static constexpr uint8_t CMD_SET_FLAG = 0x80;   // 1000 0000
    static constexpr uint8_t CMD_SET_HIGH = 0xC0;   // 1100 0000 -> tam kýsým
    static constexpr uint8_t CMD_SET_LOW = 0x80;   // 1000 0000 -> ondalýk kýsým

    /*
        Verilen iki komut ile (H ve L) sýcaklýk okur
        H: tam kýsým
        L: ondalýk kýsým
    */
    bool getTemp(uint8_t cmdH, uint8_t cmdL, float& outC);

    /*
        Tek byte veri okuma fonksiyonu
        Fan hýzý gibi tek byte dönen deðerler için kullanýlýr
    */
    bool getByte(uint8_t cmd, uint8_t& out);

    /*
        UART üzerinden komut gönderip cevap alma iþlemini yapar
        - flushBefore: önce RX buffer temizlensin mi?
        - timeoutMs: cevap için beklenecek süre
    */
    bool txrx(uint8_t cmd, uint8_t& out, DWORD timeoutMs = 500, bool flushBefore = true);

    /*
        PIC'ten gelen H ve L byte'larýný birleþtirip
        float sýcaklýk deðerine çevirir
    */
    static float combineTemp(uint8_t h, uint8_t l);

public:
    // Constructor: Dýþarýdan bir SerialPort nesnesi alýr
    explicit Board1Api(SerialPort& port);

    // Ýstenen sýcaklýðý okur
    bool getDesired(float& outC);

    // Ortam sýcaklýðýný okur
    bool getAmbient(float& outC);

    // Fan hýzýný okur
    bool getFanSpeed(int& out);

    // Ýstenen sýcaklýðý PIC'e gönderir
    bool setDesired(float tempC);

    // Tüm deðerleri tek seferde okur
    bool getAll(Board1Status& st);
};
