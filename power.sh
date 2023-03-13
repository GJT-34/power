#!/bin/bash

# This script makes power profile and associated screen brightness changes 
#  based on either a(n) (un)plugged(-in) event or battery percentage crossing
#  the low battery power threshold, provided that the user has not disabled
#  that threshold (via dconf-editor).

# Greg Till
# Derived from https://kobusvs.co.za/blog/power-profile-switching/
# Tested on Ubuntu

# README: Prerequisites and User-Definable Variables---------------------------

# Install the inotify-tools package (sudo apt install inotify-tools)

AC_PROFILE="performance"
DC_PROFILE="balanced"
# You can customize these variables. Other available option: "power-saver"
# Not all devices support performance mode. If unsupported, the script will use
#  balanced mode in its place.

AC_BRIGHTNSS_PRCNT=70
DC_BRIGHTNSS_PRCNT=35
DC_LOW_BAT_BRIGHTNSS_PRCNT=20
# Brightness figures are percentages that you can customize, from 1 (lowest) to 
#  100

# This script can be added as a startup application via:
#  GNOME Shell Activities -> Startup Application Preferences 
# -----------------------------------------------------------------------------

# Make sure system has completed booting before the script begins
echo Pausing for 30 seconds before starting
sleep 30

correct_for_unsupported_mode() {
	# if performance mode is unsupported, use balanced mode in its place
	local profile
	local all_profiles
	profile=$(echo "$1")
	all_profiles=$(get_all_profiles)
	if [[ "$profile" = "performance" ]] && \
	[[ "$all_profiles" = *performance* ]]; then
		profile="performance"
	else profile="balanced"
	fi
	echo "$profile"
}

get_low_bat_tf() {
	# get whether low battery threshold is to be used
	local low_bat_tf
	low_bat_tf=$(gsettings list-recursively org.gnome.settings-daemon.plugins.power \
	| grep power-saver-profile-on-low-battery | awk '{ print $3 }')
	# may get settings for root if run as superuser
	echo "$low_bat_tf"
}

get_low_bat_thrshld_prcnt() {
	# get the device's low battery threshold
	local filename
	local use_prcnt_for_policy
	local low_bat_thrshld_prcnt
	filename="/etc/UPower/UPower.conf"
	while read -r line; do
		if [[ "$line" = "UsePercentageForPolicy=true" ]]; then
			use_prcnt_for_policy=1
		elif [[ "${line:0:14}" = "PercentageLow=" ]]; then
			low_bat_thrshld_prcnt=${line#*=}
		fi
	done < $filename
	if [[ "$use_prcnt_for_policy" -ne 1 ]]; then
		low_bat_thrshld_prcnt=0
	fi
	echo "$low_bat_thrshld_prcnt"
}

get_all_profiles() {
	# get the list of all available power profiles 
	# it might exclude performance mode on some devices
	local all_profiles
	all_profiles=$(powerprofilesctl)
	echo "$all_profiles"
}

get_profile() {
	# get the current power profile
	# values are performance (not always), balanced, and power-saver
	local profile
	profile=$(powerprofilesctl get)
	echo "$profile"
}

set_profile() {
	# set power profile
	local profile
	profile=$(echo "$1")
	powerprofilesctl set "$profile"
}

get_brightnss_prcnt() {
	# get current brightness percentage
	local brightnss_prcnt
	brightnss_prcnt=$(gdbus call --session \
	--dest org.gnome.SettingsDaemon.Power \
	--object-path /org/gnome/SettingsDaemon/Power \
	--method org.freedesktop.DBus.Properties.Get \
	org.gnome.SettingsDaemon.Power.Screen Brightness \
	| awk -F[\<\>] '{print $2}')
	echo "$brightnss_prcnt"
}

set_brightnss_prcnt() {
	# set current brightness percentage
	local brightnss_prcnt
	brightnss_prcnt=$(echo "$1")
	gdbus call --session --dest org.gnome.SettingsDaemon.Power \
	--object-path /org/gnome/SettingsDaemon/Power \
	--method org.freedesktop.DBus.Properties.Set \
	org.gnome.SettingsDaemon.Power.Screen Brightness \
	"<int32 $brightnss_prcnt>"
	# the gdbus usage generates 1-2 "()" responses
}

get_bat_status() {
	# get current battery status
	# values are AC, DC, unknown
	sleep 3
	# After a change in battery status, /sys/class/power_supply/BAT*/status
	#  may initially report an incorrect status or report "Unknown", but 
	#  will quickly correct its response if given a brief pause to do so.
	local bat
	local bat_string
	local bat_status
	local counter
	bat=$(echo "$1")
	bat_string=$(tail "$bat/status")
	# Beyond 3 sec, result is accurate but can continue to say "Unknown"
	# Give it a little longer to update if needed
	if [[ "$bat_string" = "Unknown" ]]; then
		counter=0
		while [ "$counter" -le 5 ]; do
			sleep 1
			bat_string=$(tail "$bat/status")
			if [[ "$bat_string" != "Unknown" ]]; then
				break
			else
				((counter++))
			fi
		done
	fi
	if [[ "$bat_string" = "Discharging" ]]; then
		bat_status="DC"
	elif [[ "$bat_string" = "Charging" ]] || \
	[[ "$bat_string" = "Full" ]]; then
		bat_status="AC"
	else
		bat_status="unknown"
	fi	
	echo "$bat_status"
}

get_bat_prcnt() {
	# get current battery percentage
	local bat
	local bat_prcnt
	bat=$(echo "$1")
	bat_prcnt=$(tail "$bat/capacity")
	echo "$bat_prcnt"
}

DC_PROFILE=$(correct_for_unsupported_mode "$DC_PROFILE")
AC_PROFILE=$(correct_for_unsupported_mode "$AC_PROFILE")

LOW_BAT_TF=$(get_low_bat_tf)
if [[ "$LOW_BAT_TF" = "true" ]]; then
	LOW_BAT_THRSHLD_PRCNT=$(get_low_bat_thrshld_prcnt)
else
	LOW_BAT_THRSHLD_PRCNT=0
fi

BAT=$(echo /sys/class/power_supply/BAT*)

PRYR2CRNT_BAT_STATUS="N/A"
PRYR2CRNT_BAT_PRCNT=0
NEW_PROFILE="N/A"
NEW_BRIGHTNSS_PRCNT="N/A"
CHANGES=0

# Start the main decisioning loop
# Loop is restarted when inotifywait detects a change in battery status or 
#  battery percentage, at the end of the script
while true; do

	LOW_BAT_TF=$(get_low_bat_tf)
	if [[ "$LOW_BAT_TF" = "true" ]]; then
		LOW_BAT_THRSHLD_PRCNT=$(get_low_bat_thrshld_prcnt)
	else
		LOW_BAT_THRSHLD_PRCNT=0
	fi
	
	CRNT_PROFILE=$(get_profile) 	
	CRNT_BRIGHTNSS_PRCNT=$(get_brightnss_prcnt)
	CRNT2NEW_BAT_STATUS=$(get_bat_status "$BAT")
	CRNT2NEW_BAT_PRCNT=$(get_bat_prcnt "$BAT")
	NOW="$(date +'%Y-%m-%d %r')"	
	
	printf "[%s]" "$NOW"
	printf " LOW_BAT_THRSHLD_PRCNT=%s" "$LOW_BAT_THRSHLD_PRCNT"
	printf " PRYR2CRNT_BAT_STATUS=%s" "$PRYR2CRNT_BAT_STATUS"
	printf " PRYR2CRNT_BAT_PRCNT=%s" "$PRYR2CRNT_BAT_PRCNT"
	printf " CRNT_PROFILE=%s" "$CRNT_PROFILE"
	printf " CRNT_BRIGHTNSS_PRCNT=%s" "$CRNT_BRIGHTNSS_PRCNT"
	printf " CRNT2NEW_BAT_STATUS=%s" "$CRNT2NEW_BAT_STATUS"
	printf " CRNT2NEW_BAT_PRCNT=%s" "$CRNT2NEW_BAT_PRCNT"	 				
	
	# Determine whether to continue with changing profile
	if [[ "$CRNT2NEW_BAT_STATUS" = "AC" ]] && \
	[[ "$CRNT2NEW_BAT_STATUS" != "$PRYR2CRNT_BAT_STATUS" ]]; then
	# User has just plugged in or the script started while plugged in
		CHANGES=1
	elif [[ "$CRNT2NEW_BAT_STATUS" = "DC" ]]; then
		if [[ "$CRNT2NEW_BAT_STATUS" != "$PRYR2CRNT_BAT_STATUS" ]]; \
		then
		# User has just unplugged or the script started while unplugged
			CHANGES=2
		elif [[ "$CRNT2NEW_BAT_PRCNT" -le "$LOW_BAT_THRSHLD_PRCNT" ]] \
		&& [[ "$PRYR2CRNT_BAT_PRCNT" -gt "$LOW_BAT_THRSHLD_PRCNT" ]]; \
		then
		# While on DC power, battery percentage has dropped under low
		#  battery threshold since last change event
			CHANGES=3
		else
			CHANGES=-1
		fi	
	else
		CHANGES=-1
	fi
	
	# Determine new profile and brightness values
	if [[ "$CHANGES" -ge 1 ]]; then
		if [[ "$CRNT2NEW_BAT_STATUS" = "AC" ]]; then
			NEW_PROFILE=$AC_PROFILE
			NEW_BRIGHTNSS_PRCNT=$AC_BRIGHTNSS_PRCNT
		elif [[ "$CRNT2NEW_BAT_STATUS" = "DC" ]] && \
		[[ "$CRNT2NEW_BAT_PRCNT" -gt "$LOW_BAT_THRSHLD_PRCNT" ]]; then
			NEW_PROFILE=$DC_PROFILE
			NEW_BRIGHTNSS_PRCNT=$DC_BRIGHTNSS_PRCNT
		elif [[ "$CRNT2NEW_BAT_STATUS" = "DC" ]] && \
		[[ "$CRNT2NEW_BAT_PRCNT" -le "$LOW_BAT_THRSHLD_PRCNT" ]]; then
			NEW_PROFILE="power-saver"
			NEW_BRIGHTNSS_PRCNT=$DC_LOW_BAT_BRIGHTNSS_PRCNT
		else
			CHANGES=-2
		fi
	fi		
		
	if [[ "$CHANGES" -ge 1 ]]; then
		printf " NEW_PROFILE=%s" "$NEW_PROFILE"
		printf " NEW_BRIGHTNSS_PRCNT=%s" "$NEW_BRIGHTNSS_PRCNT"
	fi
	printf " CHANGES=%s\n" "$CHANGES"
		
	# Apply the new profile and screen brightness values, if needed
	if [[ "$CHANGES" -ge 1 ]]; then
		if [[ "$NEW_PROFILE" != "$CRNT_PROFILE" ]] && \
		[[ "$NEW_BRIGHTNSS_PRCNT" -ne "$CRNT_BRIGHTNSS_PRCNT" ]]; then
			set_profile "$NEW_PROFILE"
			set_brightnss_prcnt "$NEW_BRIGHTNSS_PRCNT"
		elif [[ "$NEW_PROFILE" != "$CRNT_PROFILE" ]] && \
		[[ "$NEW_BRIGHTNSS_PRCNT" -eq "$CRNT_BRIGHTNSS_PRCNT" ]]; then
			set_profile "$NEW_PROFILE"
		elif [[ "$NEW_PROFILE" = "$CRNT_PROFILE" ]] && \
		[[ "$CRNT_BRIGHTNSS_PRCNT" -ne "$NEW_BRIGHTNSS_PRCNT" ]]; then
			set_brightnss_prcnt "$NEW_BRIGHTNSS_PRCNT"
		elif [[ "$PRYR2CRNT_BAT_STATUS" != "N/A" ]]; then
			CHANGES=-3
		fi
		PRYR2CRNT_BAT_STATUS=$CRNT2NEW_BAT_STATUS
		PRYR2CRNT_BAT_PRCNT=$CRNT2NEW_BAT_PRCNT
		CRNT_PROFILE=$NEW_PROFILE
		CRNT_BRIGHTNSS_PRCNT=$NEW_BRIGHTNSS_PRCNT
	fi		

	NEW_PROFILE="N/A"
	NEW_BRIGHTNSS_PRCNT="N/A"
	CHANGES=0
	
	# Wait for the next power change event
	inotifywait -qq "$BAT/status" "$BAT/capacity" 

done
