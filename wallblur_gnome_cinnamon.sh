#!/bin/bash


### ---- Global variables ----

### Find if cinnamon or gnome
desktop="gnome"
if grep -q innamon <<<"$XDG_CURRENT_DESKTOP"; then
	desktop="cinnamon"
fi
package=org.$desktop.desktop.background # DE-specific

### Screen resolution
resolution=$(echo -n $(xrandr | grep '*') | awk '{print $1;}')

### Never changing
cache_dir=$HOME/.cache/wallblur
last_wallpaper_file_path=$cache_dir/last_wallpaper_path

### Current wallpaper info (also populated by settle_new_wallpaper)
last_wallpaper_path=""
if [ -f "$last_wallpaper_file_path" ]; then
	last_wallpaper_path=$(<$last_wallpaper_file_path)
	echo Found old wallpaper $last_wallpaper_path
fi
basefilename=$(basename -- "$last_wallpaper_path")
extension="${basefilename##*.}"
filename="${basefilename%.*}"

### Will be populated/changed after the first loop iteration
prev_state="" # This shouldn't be neither blurred nor unblurred


### ---- Helper functions ----

### Called when a new wallpaper is detected
### It uses (the global) last_wallpaper_path to populate everything
settle_new_wallpaper() {
	### Remove old cache dir and recreate it
	if [ -d "$cache_dir" ]; then
		echo " * Cleaning existing cache..."
		rm -r "$cache_dir"/*
	fi
	mkdir -p $cache_dir

	### Save the new uri to a file (to be checked upon restart of the pc)
	echo $last_wallpaper_path > $last_wallpaper_file_path

	### File info
	basefilename=$(basename -- "$last_wallpaper_path")
	extension="${basefilename##*.}"
	filename="${basefilename%.*}"
}

### usage: isMinimized <windowId>
### returns status 0 if and only if window with given id is minimized
is_minimized() {
	xprop -id "$1" | grep -Fq 'window state: Iconic'
}

### (uses is_minimized)
number_of_unminimized_windows_in_current_workspace() {
	count=0
	### The wmctrl command returns unminimized windows, ignoring sticky
	### because the DE has some sticky by default.
	### For reference, $(wmctrl -l | cut -f1 -d' ') includes sticky
	for id in $(wmctrl -l | grep -vE '^0x\w* -1' | cut -f1 -d' '); do
		is_minimized "$id" || ((count++))
	done
	return $count
}

gen_blurred_seq () {
	### Resize to screen resolution
	local tmp=""$cache_dir"/tmp."$extension""
	convert -resize $resolution "$last_wallpaper_path" $tmp

	### Generate incrementally blurred images
	for i in $(seq 0 1 5); do
		blurred_wallpaper=""$cache_dir"/"$filename""$i"."$extension""
		### TODO: Linux mint default images are very large and it's slow -> Subsample
		convert -blur 0x$i $tmp "$blurred_wallpaper"
		echo " > Generating... $(basename $blurred_wallpaper)"
	done
}

do_blur () {
	for i in $(seq 5); do
		blurred_wallpaper=""$cache_dir"/"$filename""$i"."$extension""
		gsettings set $package picture-uri file://"$blurred_wallpaper"

	done
}

do_unblur () {
	for i in $(seq 5 -1 0); do
		blurred_wallpaper=""$cache_dir"/"$filename""$i"."$extension""
		gsettings set $package picture-uri file://"$blurred_wallpaper"

	done
}


### ---- Main execution ----

echo "Cache dir: $cache_dir"
echo "Desktop Environment: $desktop"

first_time=true

### Main loop
while :; do
	### The gsettings command returns the path to the current wallpaper (with file:// at the start
	### and wrapped in '' quotes)
	### Note that it doesn't work for slideshows, for which it returns an xml containing all the paths
	curr_wallpaper_path="$(gsettings get $package picture-uri)"
	curr_wallpaper_path=$(echo -n "$curr_wallpaper_path" | tail -c +9 | head -c -1) # Remove file:// and quotes

	### Check if the wallpaper has actually changed (-> the uri is outside our cache_dir)
	if [ ! "$curr_wallpaper_path" = "$last_wallpaper_path" ] && [[ ! "$curr_wallpaper_path" == "$cache_dir/"* ]]; then
		echo "* The wallpaper changed"
		last_wallpaper_path=$curr_wallpaper_path
		settle_new_wallpaper
		gen_blurred_seq
		prev_state="" # Reset
		continue # So that it rechecks the current wallpaper before changing
	fi

	### Find if there are unminimized windows
	number_of_unminimized_windows_in_current_workspace
	num_windows=$?

	### Blur/Unblur
	if [ "$num_windows" = "0" ]; then
		if [ "$prev_state" != "unblurred" ]; then
			echo " ! Un-blurring"
			do_unblur
			prev_state="unblurred"
		fi
	else
		if [ "$prev_state" != "blurred" ]; then
			echo " ! Blurring"
			do_blur
			prev_state="blurred"
		fi
	fi

	sleep 0.3
done
