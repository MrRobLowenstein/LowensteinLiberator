# LowensteinLiberator
Liberate your Löwenstein prismaLINE PAP device to its full potential.

Like many hardware manufacturers, Löwenstein uses questionable practices where their PrismaLINE sleep apnea therapy device range all use the same hardware, only the software running on them differs. The most expensive devices have full software capabilities while getting regressively limited when moving towards the bottom of the range.

PrismaLINE devices (Type WM 100 TD) include 20C, 20A, CR, 25S, 25S-C, 25ST, 25ST-C, 30ST up to the prismaLAB titration device.

Using this script you can unlock your device to be able to use all available therapy modes for this range. Essentially you can turn a 20C to a prismaLAB device during a software update.

The scripts only enable the built-in service mode during an update installation. This mode is used by technicians during troubleshooting, device testing and repairs. The actual firmware installed during the update isn't modified in any way and nothing is done that isn't supported by the device already from the factory.

## DISCLAIMER:
This repo is only for academic and educational purposes. Use this only for your personally purchased device, do not use for your prescribed unit. You will void your warranty and any liability from the manufacturer. Be mindful and use what is provided only at your own risk. I'm not responsible if you brick your device or if you compromise your therapy.

This script has only been tested with version 5.07.0002 (2023-0310-1825-Eyra) on a 20A device. It should work with any model from this range, but use it at your own risk. If you have an older firmware version it's recommended to first update it with the stock firmware update to version 5.07.0002 and only then install the modified unlocking firmware.

If you have a newer firmware version on your device already the behavior is unknown, but I would gladly test it if you are able to provide the firmware package for that version.

Changing the device type resets it to factory defaults, starting it with region and time setting selection like a brand new device. Operating hours and statistics are erased.

## Procedure:

- Download the script for your platform (macOS/Linux or Windows).
- Procure firmware version 5.07.0002 (2023-0310-1825-Eyra). It's freely available online.
- Use the script to modify the firmware package. The script produces two modified zip files. Phase 1 is the first modified package installation for firmware unlock, phase 2 is when you change the device type in the service menu and phase 3 is a package install for returning the device to regular operating mode.

The scripts only use commands available to a regular OS installation and should work without any additional tools.

Running the script:
On macOS/Linux:
```
./make_service_packages.sh <stock .zip> [output_dir]
```
output_dir is optional and defaults to "./service_packages".

Don't forget to make the script executable with: ```chmod +x make_service_packages.sh```

On Windows:
```
.\make_service_packages.ps1 .\Update_weinmann_respiratory_device.zip [output_dir]
```
Output directory is optional and defaults to .\service_packages.

On Windows running scripts is restricted by default. You can allow the script to run for one time by running it with cmd.exe, assuming here you have downloaded the script to your Downloads folder:
```powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\Downloads\make_service_packages.ps1" <path to zip file>```

### Phase 1
- Format a FAT32 SD card and copy the phase 1 zip package to the root of the card.
- Insert the card into your device. When a window appears asking if you want to update your device, tap on 'start update'.
- Once the update has completed and the screen turns black, remove the SD card and the device reboots.
### Phase 2:
- The device boots into developer mode. Tap on "Versions, types".
- From the "Device type" popup menu select the device type you'd like to switch to. The type including the most modes is "Titration HUL".
- Tap the close button.
### Phase 3:
- Insert SD card with phase 3 zip package copied to the root of the card.
- Go into "Developing things" menu, tap on "misc" and move to tab 1.
- Tap on "SW update from SD card" and tap "Yes".
- Remove the SD card once the device starts rebooting at the end of the installation.
- After starting up it's back in regular mode and all therapy modes for that particular device type are available.
