# Pwnagotchi: The Hybrid-Architecture Build

## Project Vision
A specialized Pwnagotchi implementation for the Raspberry Pi Zero 2 W (and Pi 3B) that solves the "Dependency Hell" of running legacy AI software on modern hardware. This project utilizes a "Split-Brain Microservice" architecture: running the hardware and packet injection natively on a Modern 64-bit Kernel, while isolating the legacy AI logic inside a 32-bit Docker container.

## The Roadmap (Current Goals)

**Phase 1: The Known-Good Baseline & UI Engine (Complete)**
* **Cross-Platform Image Builder:** Rewrote the deployment process into a custom Bash script utilizing a Docker build environment. This ensures seamless modification and compilation of the existing OS image on any Linux host system.
* Deploy on legacy Buster (32-bit) image.
* **Internal Wi-Fi Mastery:** Successfully patched and deployed Nexmon drivers on the internal BCM43439 chip, eliminating the need for external USB dongles.
* **Custom UI Engine:** Developed an autonomous, self-healing E-ink display driver (`waveshare4.py`) that tracks canvas dimensions and prevents ghosting.
* **Modular Dashboard:** Built a dynamic, hot-swappable layout system (`portrait_mode.py` and `face_only.py`) that instantly shifts core UI and third-party plugins without rebooting.

**Phase 2: The Microservice Split & Docker Transition (In Progress)**
* **The Host Layer:** Run `bettercap` natively on the host OS to manage the Nexmon Wi-Fi interface and expose its REST API.
* **The Brain Layer:** Containerize the Pwnagotchi AI and Python 3.7 environment into a 32-bit `linux/arm/v7` Docker image.
* **The Bridge:** Link the containerized AI to the host's Bettercap API over the Docker bridge network. Map hardware pipes (`/dev/spidev0.0`, `/dev/i2c-1`) via `--device` flags for E-Ink stability.

**Phase 3: The Trixie Evolution (Final Goal)**
* Move the host OS to Raspberry Pi OS Lite (Trixie/64-bit) for the Pi Zero 2 W.
* Run the native Bettercap service and the containerized AI brain side-by-side to maintain legacy TensorFlow compatibility without breaking modern system libraries.

## Hardware Stack
* **Host:** Raspberry Pi Zero 2 W / Pi 3B
* **Display:** Waveshare E-Ink Screen (V4)
* **Power:** PiSugar 3 Battery

---

## Credits & Lineage
This project wouldn't exist without the work of those who came before:
* **[aluminum-ice](https://github.com/aluminum-ice/pwnagotchi):** The base for this specific fork and its modern improvements.
* **[evilsocket](https://github.com/evilsocket/pwnagotchi):** The original creator of the Pwnagotchi project.

---

## ⚠️ Disclaimer
This is a personal learning project. Use at your own risk. While I aim to make Pwnagotchi "even better," things may break as I experiment with the core logic.
