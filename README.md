# Pwnagotchi: The Hybrid-Architecture Build
📌 Project Vision

A specialized Pwnagotchi implementation for the Raspberry Pi Zero 2 W (and Pi 3B) that solves the "Dependency Hell" of running legacy AI software on modern hardware. This project utilizes a Containerized Brain on top of a Modern Host Kernel to achieve maximum stability and hardware performance.

🏗️ The Roadmap (Current Goals)

    Phase 1: The Known-Good Baseline (Current)

        Deploy on Raspberry Pi 3B using a legacy Buster (32-bit) image.

        Utilize the TL-WN722N v1 (Atheros AR9271) USB dongle for native monitor mode (bypassing Nexmon complexity).

        Verify AI logic and E-Ink screen stability.

    Phase 2: The Docker Transition

        Containerize the Pwnagotchi AI and Python 3.7 environment into a 32-bit Docker image.

        Ensure all hardware pipes (SPI for screen, GPIO for buttons) are mapped via --privileged flags.

    Phase 3: The Trixie Evolution (Final Goal)

        Move the host OS to Raspberry Pi OS Lite (Trixie/64-bit) for the Pi Zero 2 W.

        Install modern Nexmon 6.12+ drivers on the host for stable internal Wi-Fi monitoring.

        Run the "Phase 2" Docker container on this modern host to maintain AI compatibility without breaking system libraries.

🔌 Hardware Stack

    Host: Raspberry Pi Zero 2 W / Pi 3B

    Onboard WiFi: BCM43439 (Nexmon patched on Trixie)

    External WiFi (Backup): TP-Link TL-WN722N v1

    Display: Waveshare E-Ink Screen (V3/V4)

---

## 📝 Credits & Lineage
This project wouldn't exist without the work of those who came before:
* **[aluminum-ice](https://github.com/aluminum-ice/pwnagotchi):** The base for this specific fork and its modern improvements.
* **[evilsocket](https://github.com/evilsocket/pwnagotchi):** The original creator of the Pwnagotchi project.

---

## ⚠️ Disclaimer
This is a personal learning project. Use at your own risk. While I aim to make Pwnagotchi "even better," things may break as I experiment with the core logic.
