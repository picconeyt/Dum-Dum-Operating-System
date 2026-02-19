# **The Dum Dum Operating System | DDOS** 

### **Copyright © Bocca Gigante Production 2022, 2026** #### The Dum Dum Operating System, or **DDOS**, is a lightweight project designed to breathe new life into those dusty i386 home computers from the early 2000s. While most modern OSs have abandoned "legacy" hardware, DDOS embraces it, aiming to bring modern perks like Wi-Fi to ancient silicon.

#### This project is currently in its early stages. I’ve successfully transitioned to **16-bit Unreal Mode**, allowing the high-level kernel to punch through standard memory limits while staying lean. It is my prized possession and a deep dive into squeezing every ounce of performance out of classic hardware.

---

## **Feature Overview** - [x] **16-bit Unreal Mode** kernel entry

* [x] High-level kernel foundation
* [x] Basic Command Line Interface (CLI)
* [x] Bootloader & Core System Initialization
* [ ] **EXT-4 Support** (In progress)
* [ ] **HDD & USB Driver Stack**
* [ ] **Wi-Fi Support** (The "Modern Perk" goal)
* [ ] **GUI** (To be launched via the `start` command)
* [ ] **Installer** for permanent hardware deployment

---

## **Short-Term Roadmap**

* **Extreme RAM Optimization:** Stripping the kernel to the bare essentials to run on the lowest specs possible, while also keeping it usable
* **Utility Expansion:** Adding a suite of essential CLI commands for system management.
* **Filesystem Implementation:** Moving from "boot only" to a functional storage-based system.

---

## **Compiling Instructions** > *Note: If you're on Windows, you'll need a UNIX-like environment such as Cygwin or WSL to compile the source code.* ### **1. Clone the Repository** Run the following command in your terminal:

```bash
git clone https://github.com/picconeyt/Dum-Dum-Operating-System.git

```

### **2. Build the OS** Navigate to the repository directory and compile with:

```bash
./build.sh
```


### **3. (Optional) flash to USB:

```bash
./write.sh
```

---
