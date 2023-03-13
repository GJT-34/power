# Using a Script to Control GNOME's Power Profile Daemon and Screen Brightness Settings

This automatically changes GNOME's power profile daemon and screen brightness settings based on whether the laptop is plugged in or not, or based on whether the battery percentage has crossed the system's defined low power threshold. The daemon has up to three power levels: 'performance', 'balanced', and 'power saver', with associated tradeoffs of processing power and battery use. Screen brightness in this script is a percentage from 1 (lowest) to 100, with the brightest level obviously also using the most power.

I wanted a script that worked with the daemon without getting in its way and could do the following:
- If plugged in, including at boot, set the power profile to a desired level (in my case, at 'performance') and set the screen brightness to a desired (higher) level as well.
- If unplugged, including at boot, set the power profile to a desired level (in my case, at 'balanced') and set the screen brightness to a desired (lower) level as well. 
- If the battery percentage crosses the low battery level (provided that level is defined by the system), set the power profile to 'power-saver' (which the user can manually override through various desktop tools) and set the screen brightness to a desired (even lower) level as well.

The script has one prerequisite. In terminal, enter the following:
```
sudo apt install inotify-tools
```
# How To
- Create an empty file with the name 'power.sh' (no quotes) at a location of your choosing. I used /.local/bin in my home directory.
- Copy the contents of the script from this repository into the new file.
- Make any desired configuration changes to the script. 
  - You can choose which of the three power profiles you wish to use when the laptop is plugged in ('AC_PROFILE') or unplugged ('DC_PROFILE'). 
  - You can also set the screen brightness on a percentage scale of 1 (lowest) to 100 for when the laptop is plugged in ('AC_BRIGHTNSS_PRCNT'), unplugged ('DC_BRIGHTNSS_PRCNT'), and unplugged and below the low battery threshold ('DC_LOW_BAT_BRIGHTNSS_PRCNT').
- Save the file.
- Make the file executable. In GNOME, you can do this in a couple ways. For instance, in the file manager you can right click on the file, select Properties -> Permissions and check the box that says, "Allow executing file as program."

You can run the script in terminal (which allows you to see status messages) by navigating to the folder that holds the script and entering:
```
./power.sh
```
If it works, you can add the script as a startup program via GNOME's 'Startup Application Preferences'. If you have trouble finding it, press Alt + F2 and in the text box type 'gnome-session-properties' and hit enter.

A few final notes:
- ***When it starts, there is a delay of 30 seconds before the script initially takes action.*** This is to make sure that the system has fully booted up before the script goes to work.
- If you have multiple batteries or track battery life by time left and not by percentage, this script may not work as expected.
- Credit to [Kobus van Schoor](https://kobusvs.co.za/blog/power-profile-switching/) for the inspiration for this script.
