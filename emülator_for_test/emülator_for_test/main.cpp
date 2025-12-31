#include "SerialPort.h"
#include "Emulator.h"
#include <iostream>
#include <string>

int main(int argc, char** argv)
{
    // Kullaným:
    // Emulator.exe board1 COM11 9600
    // Emulator.exe board2spec COM11 9600
    // Emulator.exe board2asm COM11 9600

    if (argc < 3) {
        std::cout << "Usage: Emulator.exe <board1|board2spec|board2asm> <COMx> [baud]\n";
        return 1;
    }

    std::string mode = argv[1];
    std::string com = argv[2];
    int baud = (argc >= 4) ? std::stoi(argv[3]) : 9600;

    SerialPort port;
    if (!port.open(com, baud)) {
        std::cout << "Open failed: " << port.lastError() << "\n";
        return 1;
    }

    Emulator emu(port);

    if (mode == "board1") {
        emu.run(Emulator::Mode::Board1_Spec);
    }
    else if (mode == "board2spec") {
        emu.run(Emulator::Mode::Board2_Spec);
    }
    else if (mode == "board2asm") {
        emu.run(Emulator::Mode::Board2_ASM);
    }
    else {
        std::cout << "Unknown mode.\n";
        return 1;
    }

    return 0;
}
