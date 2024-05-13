#
# Author: [Cpt. Chaz]
# Created: [05/13/24]
# Updated: --
# Description: This script is designed to remove incompatible subtitle streams using ffmpeg, particularly when re-muxing from .mkv to .mp4 file containers.
# The script first checks to make sure ffmpeg is installed. Then it checks the working directory and asks the user which file to remove the subs from.
# Once user selection is made, the script does the rest. The script will make a backup copy of the orginal file first. If ffmpeg fails, the backup is restored.
# If successful, the new file is given the original filename and the input file is deleted. Works on mkv and mp4 containers. Currently the script removes the following streams:
#    dvd_sub, srt, subrip, ass, bmp - these can be adjusted by modifying the section below "Iterate over the streams"
# 
# Tip: On linux systems, create an alias to make executing the script easier. For example:  
#  -->  alias fix_subs='bash -c '\''/your/path/here/remove_subs.sh *.*'\'''
# Then, once alias "fix_subs" is created, navigate to directory with file(s) that you wish to remove subs from, and simply type "fix_subs". Script will execute from there.
# Status: Tested
#
# Credits:
# - This script was created with the help of ChatGPT, an OpenAI language model.
#
#!/bin/bash

# Function to list video files and ask for user input if multiple files are found
choose_file() {
  local files=(*.mp4 *.mkv)  # Modify this line if you need to add more video formats
  local count=${#files[@]}
  
  if [ "$count" -eq 0 ]; then
    echo "No video files found in the directory."
    exit 1
  elif [ "$count" -eq 1 ]; then
    echo "One file found: ${files[0]}"
    chosen_file="${files[0]}"
  else
    echo "Multiple video files found:"
    for i in "${!files[@]}"; do
      echo "$((i+1)): ${files[i]}"
    done
    
    while true; do
      read -p "Enter the number of the file you want to process: " file_num
      
      # Validate user input
      if [[ $file_num =~ ^[0-9]+$ ]] && [ "$file_num" -ge 1 ] && [ "$file_num" -le "$count" ]; then
        chosen_file="${files[$((file_num-1))]}"
        break
      else
        echo "Invalid selection. Please try again."
      fi
    done
  fi
}

# Initial checks and setup
echo "Starting the script..."
choose_file

# Check if ffmpeg is installed
echo "Checking to make sure ffmpeg is installed"
if ! [ -x "$(command -v ffmpeg)" ]; then
  echo 'Error: ffmpeg is not installed.' >&2
  exit 1
fi
echo " "

# Check if the chosen file exists
echo "Checking if the chosen file exists..."
if [ ! -f "$chosen_file" ]; then
  echo "Error: the chosen file does not exist." >&2
  exit 1
fi
echo " "

# Create a backup of the chosen file
echo "Creating a backup of the chosen file..."
backup_file="$chosen_file.bak"
cp "$chosen_file" "$backup_file"
echo "Backup file created as $backup_file"
echo " "

# Copy the file name of the chosen file
echo "Copying the chosen file name"
file_name=$(basename "$chosen_file")
echo " "

# Set the output file name
echo "Setting the output file name"
if [[ $file_name == *.mkv ]]; then
  output_file="output.mkv"
else
  output_file="output.mp4"
fi
echo " "

# Use ffmpeg to list the streams in the chosen file
echo "Using ffmpeg to list the streams in the chosen file"
streams=$(ffmpeg -i "$file_name" 2>&1 | grep "Stream #")

# Initialize an empty array to store the stream indices
stream_indices=()

# Iterate over the streams
echo "Iterating over the streams"
while read -r line; do
  if [[ $line =~ "dvd_sub" || $line =~ "srt" || $line =~ "subrip" || $line =~ "ass" || $line =~ "bmp" ]]; then
     stream_index=$(echo "$line" | grep -oP "(?<=\#)[^:]*")
     stream_indices+=("$stream_index")
  fi
done <<< "$streams"

# Initialize the map options string
map_options=""
echo " "

# Iterate over the stream indices
echo "Iterating over the stream indices"
for stream_index in "${stream_indices[@]}"; do
    map_options+="-map -$stream_index? "
done
echo "Adding the stream index to the map options string and excluding it from the output file"
echo " "
echo $map_options

# Use ffmpeg to remove the unwanted subtitle streams from the chosen file and create a new output file
echo "Finally time to remove the actual sub streams from the file itself"
ffmpeg -hide_banner -loglevel info -i "$file_name" -strict -2 -max_muxing_queue_size 10240 $map_options -c copy "$output_file"

echo " "
echo "Incompatible subtitles removed. Output file saved as $output_file"
echo " "

# Check if the output file exists
echo "Now time to make sure the output file exists, and delete the backup if so"
echo " "
if [ -e "$output_file" ]; then
    rm *.bak
    
    # Rename $output_file with $file_name
    mv "$output_file" "$file_name"
else
    echo "Looks like the ffmpeg command failed. Restoring backup file"
    mv "$backup_file" "$output_file"
    rm output.mkv
fi

