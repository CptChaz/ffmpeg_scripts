#
# Author: [Cpt. Chaz]
# Created: [05/13/24]
# Updated: [03/08/25]
# Description: This script is designed to remove incompatible subtitle streams using ffmpeg, particularly when re-muxing from .mkv to .mp4 file containers.
# The script first checks to make sure ffmpeg is installed. Then it checks the working directory and asks the user which file to remove the subs from.
# Once user selection is made, the script does the rest. The script will make a backup copy of the orginal file first. If ffmpeg fails, the backup is restored.
# If successful, the new file is given the original filename and the input file is deleted. Works on mkv and mp4 containers. Currently the script removes the following streams:
#   webvtt, dvd_sub, hdmv_pgs_subtitle, ass, bmp - these can be adjusted by modifying the user config area.
# 
# Tip: On linux systems, create an alias to make executing the script easier. For example:  
#  -->  alias fix_subs='bash -c '\''/your/path/here/remove_subs.sh *.*'\'''
# Then, once alias "fix_subs" is created, navigate to directory with file(s) that you wish to remove subs from, and simply type "fix_subs". Script will execute from there.
# Status: Tested
#
# Credits:
# - This script was created with the help of ChatGPT, an OpenAI language model.
#




#!/usr/bin/env bash
shopt -s nullglob

# -----------------------------
# USER CONFIG - adjust video extensions and subtitle formats. (only .mkv and .mp4 have been tested)
undesirable_subs=("webvtt" "dvd_sub" "hdmv_pgs_subtitle" "ass" "bmp")
video_files=( *.mkv *.mp4 )
# -----------------------------

echo "Starting script..."

# 1) SELECT FILE
count=${#video_files[@]}
if [[ $count -eq 0 ]]; then
  echo "No video files found. Exiting."
  exit 1
elif [[ $count -eq 1 ]]; then
  chosen_file="${video_files[0]}"
  echo "Single file found: $chosen_file"
else
  echo "Multiple video files found:"
  for i in "${!video_files[@]}"; do
    echo "$((i+1))). ${video_files[i]}"
  done
  while true; do
    read -p "Enter the number of the file you want to process: " file_num
    if [[ $file_num =~ ^[0-9]+$ ]] && (( file_num >= 1 && file_num <= count )); then
      chosen_file="${video_files[$((file_num-1))]}"
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
fi
echo " "

# 2) CHECK FOR FFMPEG
echo "Checking if ffmpeg is installed..."
if ! command -v ffmpeg &>/dev/null; then
  echo "Error: ffmpeg is not installed."
  exit 1
fi
echo "ffmpeg found."
echo " "

# 3) BACKUP & BASIC VARS
extension="${chosen_file##*.}"
backup_file="${chosen_file}.bak"

echo "Creating backup of '${chosen_file}' as '${backup_file}'..."
cp -f "$chosen_file" "$backup_file" || {
  echo "Failed to create backup. Exiting."
  exit 1
}
echo "Backup created."
echo " "

# 4) BUILD EXCLUSION LIST
# We'll parse ffprobe line-by-line, collecting index/codec_name/codec_type,
# then "commit" the last stream once we see a new index or reach EOF.

echo "Detecting undesirable subtitles with ffprobe..."
map_options=""
current_index=""
current_codec=""
current_type=""

commit_stream() {
  # Called when we complete one stream block
  # If it's a subtitle with an undesirable codec, we exclude it
  echo "Committing stream: index=$current_index, codec=$current_codec, type=$current_type"
  if [[ "$current_type" == "subtitle" && -n "$current_index" ]]; then
    for bad in "${undesirable_subs[@]}"; do
      if [[ "$current_codec" == "$bad" ]]; then
        map_options+=" -map -0:${current_index}"
        echo "-> Excluding subtitle stream #$current_index ($current_codec)"
        break
      fi
    done
  fi
  current_index=""
  current_codec=""
  current_type=""
}

# Parse ffprobe
while IFS= read -r line; do
  # e.g. "index=2", "codec_name=webvtt", "codec_type=subtitle"
  if [[ "$line" =~ ^index=([0-9]+)$ ]]; then
    # New stream => commit the previous one first
    if [[ -n "$current_index" ]]; then
      commit_stream
    fi
    current_index="${BASH_REMATCH[1]}"

  elif [[ "$line" =~ ^codec_name=(.*)$ ]]; then
    current_codec="${BASH_REMATCH[1]}"

  elif [[ "$line" == "codec_type=subtitle" ]]; then
    current_type="subtitle"
  fi
done < <(
  ffprobe -v error \
          -show_entries stream=index,codec_type,codec_name \
          -of default=noprint_wrappers=1 \
          "$chosen_file"
)
# Commit the final stream block after the loop
if [[ -n "$current_index" ]]; then
  commit_stream
fi

echo "Final map_options: '$map_options'"
echo " "

# 5) RUN FFMPEG
output_file="output.${extension}"
echo "Running ffmpeg to remove undesired subtitles..."
echo "ffmpeg -i \"$chosen_file\" -map 0 $map_options -c copy \"$output_file\""
ffmpeg -i "$chosen_file" -map 0 $map_options -c copy "$output_file"

echo " "

# 6) CHECK SUCCESS / RENAME
if [[ -f "$output_file" && -s "$output_file" ]]; then
  echo "ffmpeg succeeded. Removing backup and renaming output..."
  rm -f "$backup_file"
  mv -f "$output_file" "$chosen_file"
  echo "Subtitles removed successfully (if any matched)."
else
  echo "ffmpeg failed or output file is empty. Restoring backup..."
  rm -f "$output_file"
  mv -f "$backup_file" "$chosen_file"
fi

echo "Done."
