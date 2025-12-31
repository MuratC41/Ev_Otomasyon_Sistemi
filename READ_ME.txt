***MURAT ÇEVLİK 152120201067***
HOME AUTOMATION PC APP - README

Bu projede iki farklı board (Board1 ve Board2) PC üzerinden
UART (COM port) kullanılarak kontrol edilmektedir.
Gerçek donanım olmadan test edebilmek için bir Emulator yazılmıştır.


EMULATOR NASIL CALISTIRILIR

Emulator ayrı bir konsol uygulamasıdır ve komut satırından çalıştırılır.

Kullanım:
Emulator.exe <mod> <COMx> [baud]

Modlar:
- board1      : Board1 (Air Conditioner) emülasyonu
- board2spec  : Board2 (doküman mantığı)
- board2asm   : Board2 (ASM koduna birebir)

Örnek:
Emulator.exe board1 COM11 9600
Emulator.exe board2asm COM11 9600

Emulator çalışınca seçilen COM portu dinlemeye başlar.


PC UYGULAMASI (ANA MENU)

PC uygulaması çalıştırıldığında ana menü açılır.
Buradan Board1 veya Board2 seçilir.

Ana Menü:
1) Board #1 - Air Conditioner
2) Board #2 - Curtain Control
0) Exit

Seçimden sonra COM port bilgisi girilir (örn: COM10).


BOARD1 (AIR CONDITIONER)

Board1 menüsünden:
- İstenen sıcaklık okunur
- Ortam sıcaklığı okunur
- Fan hızı okunur
- Sıcaklık ayarlanır
- Monitor mode ile sürekli okuma yapılır


BOARD2 (CURTAIN CONTROL)

Board2 menüsünden:
- Perde durumu (%)
- Dış sıcaklık
- Basınç
- Işık şiddeti
okunabilir ve perde durumu ayarlanabilir.

Not:
Board2 ASM tarafında 6-bit (0..63) veri kullandığı için
PC tarafında 0..100 % değeri otomatik dönüştürülmektedir.


CALISMA MANTIGI

1) Emulator bir COM portta çalıştırılır
2) PC App diğer COM portu açar
3) PC App komut gönderir
4) Emulator gerçek board gibi cevap verir

Bu sayede gerçek donanım olmadan test yapılır.
