# Pwnagotchi

This is a fork of the [aluminum-ice pwnagotchi project](https://github.com/aluminum-ice/pwnagotchi). 

## 🎯 Project Intent
This repository serves as a personal learning environment and a "cut down" version of the Pwnagotchi OS. My goal is to dive deep into the underlying architecture—from the Ansible playbooks to the Packer build process—to understand exactly how this is built.

**Key focus areas:**
* **Optimization:** Stripping out bloat and unused community plugins to create a leaner image.
* **Specialization:** Tuning the OS for a specific hardware configuration.
* **Custom Logic:** Integrating personal scripts and custom plugins
* **Keeping AI:** Part of my fascination with this project is the AI. Watching the Pwnagotchi learn from its environment is a huge draw for me, and I intend to keep the "Brain" as the centerpiece of this build.

---

## 🛠 Targeted Hardware Configuration
*To keep the image lightweight, support is focused on:*
* **Host:** [Raspberry Pi Zero 2 W]
* **Display:** [Waveshare V4]
* **Power:** [PiSugar 3]
* **Plugins:** Minimalist set tailored to my daily use.

---

## 🚀 Current Roadmap & Progress
- [x] Forked repository and initialized environment.
- [ ] Successfully "baking" the original `.img` using Packer and QEMU.
- [ ] configure the pwnagotchi.yml to make custom build

---

## 📝 Credits & Lineage
This project wouldn't exist without the work of those who came before:
* **[aluminum-ice](https://github.com/aluminum-ice/pwnagotchi):** The base for this specific fork and its modern improvements.
* **[evilsocket](https://github.com/evilsocket/pwnagotchi):** The original creator of the Pwnagotchi project.

---

## ⚠️ Disclaimer
This is a personal learning project. Use at your own risk. While I aim to make Pwnagotchi "even better," things may break as I experiment with the core logic.
