/*MURAT ÇEVLÝK 152120201067*/
#include "SerialPort.h"
#include "Board1Api.h"
#include "Board2Api.h"

#include <iostream>
#include <string>
#include <thread>
#include <chrono>
#include <atomic>

using namespace std;

// ---------- yardýmcý fonksiyonlar ----------

// cin hataya düþtüðünde temizlemek için
static void clearCin()
{
    cin.clear();
    cin.ignore(1024, '\n');
}

// Kullanýcýdan string satýr okumak için
static string readLine(const string& prompt)
{
    cout << prompt;
    string s;
    getline(cin, s);
    return s;
}

// ---------- ana menü ----------
static void printMainMenu()
{
    cout << "\n=== HOME AUTOMATION PC APP ===\n"
        << "1) Board #1 - Air Conditioner\n"
        << "2) Board #2 - Curtain Control\n"
        << "0) Exit\n"
        << "Select: ";
}

// ---------- Board #1 menüsü ----------
static void printBoard1Menu()
{
    cout << "\n=== BOARD #1 - Air Conditioner PC App ===\n"
        << "1) Read Desired Temperature\n"
        << "2) Read Ambient Temperature\n"
        << "3) Read Fan Speed\n"
        << "4) Read All (Desired/Ambient/Fan)\n"
        << "5) Set Desired Temperature\n"
        << "6) Monitor Mode (periodic read)\n"
        << "0) Back\n"
        << "Select: ";
}

// ---------- Board #2 menüsü ----------
static void printBoard2Menu()
{
    cout << "\n=== BOARD #2 - Curtain Control PC App ===\n"
        << "1) Read Curtain Status\n"
        << "2) Read Outdoor Temperature\n"
        << "3) Read Outdoor Pressure\n"
        << "4) Read Light Intensity\n"
        << "5) Read All (Curtain/Temp/Press/Light)\n"
        << "6) Set Curtain Status\n"
        << "7) Monitor Mode (periodic read)\n"
        << "0) Back\n"
        << "Select: ";
}

// ---------- Board #1 iþlemleri ----------
static void runBoard1(Board1Api& api, SerialPort& port)
{
    while (true)
    {
        printBoard1Menu();

        int choice = -1;
        if (!(cin >> choice)) { clearCin(); continue; }
        clearCin();

        if (choice == 0) break;

        if (choice == 1)
        {
            float d = 0;
            if (api.getDesired(d)) cout << "Desired = " << d << " C\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 2)
        {
            float a = 0;
            if (api.getAmbient(a)) cout << "Ambient = " << a << " C\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 3)
        {
            int f = 0;
            if (api.getFanSpeed(f)) cout << "FanSpeed(raw) = " << f << "\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 4)
        {
            Board1Status st;
            if (api.getAll(st))
            {
                cout << "Desired = " << st.desiredC << " C | "
                    << "Ambient = " << st.ambientC << " C | "
                    << "FanSpeed(raw) = " << st.fanSpeed << "\n";
            }
            else
            {
                cout << "Error: " << port.lastError() << "\n";
            }
        }
        else if (choice == 5)
        {
            cout << "Enter Desired Temperature (C): ";
            float t = 0;
            if (!(cin >> t))
            {
                clearCin();
                cout << "Invalid input.\n";
                continue;
            }
            clearCin();

            if (api.setDesired(t)) cout << "Set desired temperature sent.\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 6)
        {
            cout << "Monitor interval ms (e.g., 500): ";
            int ms = 500;
            if (!(cin >> ms)) { clearCin(); ms = 500; }
            clearCin();
            if (ms < 100) ms = 100;

            cout << "Monitoring. Press ENTER to stop.\n";

            atomic<bool> stop(false);
            thread stopper([&stop]()
                {
                    string line;
                    getline(cin, line);
                    stop.store(true);
                });

            while (!stop.load())
            {
                Board1Status st;
                if (api.getAll(st))
                {
                    cout << "Desired=" << st.desiredC
                        << " | Ambient=" << st.ambientC
                        << " | Fan=" << st.fanSpeed << "\n";
                }
                else
                {
                    cout << "Error: " << port.lastError() << "\n";
                }
                this_thread::sleep_for(chrono::milliseconds(ms));
            }

            if (stopper.joinable()) stopper.join();
            cout << "Monitor stopped.\n";
        }
        else
        {
            cout << "Unknown selection.\n";
        }
    }
}

// ---------- Board #2 iþlemleri ----------
static void runBoard2(Board2Api& api, SerialPort& port)
{
    while (true)
    {
        printBoard2Menu();

        int choice = -1;
        if (!(cin >> choice)) { clearCin(); continue; }
        clearCin();

        if (choice == 0) break;

        if (choice == 1)
        {
            float c = 0;
            if (api.getCurtainStatus(c)) cout << "Curtain = ~" << c << " %\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 2)
        {
            float t = 0;
            if (api.getOutdoorTemp(t)) cout << "Outdoor Temp = " << t << " C\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 3)
        {
            float p = 0;
            if (api.getOutdoorPressure(p)) cout << "Outdoor Press = " << p << " hPa\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 4)
        {
            double l = 0;
            if (api.getLightIntensity(l)) cout << "Light = " << l << " Lux\n";
            else cout << "Error: " << port.lastError() << "\n";
        }
        else if (choice == 5)
        {
            Board2Status st;
            if (api.getAll(st))
            {
                cout << "Curtain= ~" << st.curtainPercent << " % | "
                    << "Temp=" << st.outdoorTempC << " C | "
                    << "Press=" << st.outdoorPressHpa << " hPa | "
                    << "Light=" << st.lightLux << " Lux\n";
            }
            else
            {
                cout << "Error: " << port.lastError() << "\n";
            }
        }
        else if (choice == 6)
        {
            cout << "Enter Curtain Status (% 0..100): ";
            float pct = 0;
            if (!(cin >> pct))
            {
                clearCin();
                cout << "Invalid input.\n";
                continue;
            }
            clearCin();

            if (api.setCurtainStatus(pct))
            {
                cout << "Set curtain status sent.\n";
                cout << "Note: 0..100 degeri UART tarafinda 0..63'e cevrilir.\n";
            }
            else
            {
                cout << "Error: " << port.lastError() << "\n";
            }
        }
        else if (choice == 7)
        {
            cout << "Monitor interval ms (e.g., 500): ";
            int ms = 500;
            if (!(cin >> ms)) { clearCin(); ms = 500; }
            clearCin();
            if (ms < 100) ms = 100;

            cout << "Monitoring... Press ENTER to stop.\n";

            atomic<bool> stop(false);
            thread stopper([&stop]()
                {
                    string line;
                    getline(cin, line);
                    stop.store(true);
                });

            while (!stop.load())
            {
                Board2Status st;
                if (api.getAll(st))
                {
                    cout << "Curtain= ~" << st.curtainPercent
                        << " | Temp=" << st.outdoorTempC
                        << " | Press=" << st.outdoorPressHpa
                        << " | Light=" << st.lightLux << "\n";
                }
                else
                {
                    cout << "Error: " << port.lastError() << "\n";
                }
                this_thread::sleep_for(chrono::milliseconds(ms));
            }

            if (stopper.joinable()) stopper.join();
            cout << "Monitor stopped.\n";
        }
        else
        {
            cout << "Unknown selection.\n";
        }
    }
}

int main(int argc, char** argv)
{
    while (true)
    {
        printMainMenu();

        int sel = -1;
        if (!(cin >> sel)) { clearCin(); continue; }
        clearCin();

        if (sel == 0) break;

        if (sel != 1 && sel != 2)
        {
            cout << "Unknown selection.\n";
            continue;
        }

        string com = readLine("Enter COM port (COM10): ");
        if (com.empty())
        {
            cout << "No COM port entered.\n";
            continue;
        }

        SerialPort port;
        if (!port.open(com, 9600))
        {
            cout << "Failed to open port: " << port.lastError() << "\n";
            continue;
        }

        cout << "Connected to " << com << " @ 9600.\n";

        if (sel == 1)
        {
            Board1Api api(port);
            runBoard1(api, port);
        }
        else
        {
            Board2Api api(port);
            runBoard2(api, port);
        }

        port.close();
        cout << "Port closed.\n";
    }

    cout << "Bye.\n";
    return 0;
}
