#!/bin/bash

# Folder to scan
folder_to_scan="/volume2/sonarr"
# Destination folder for extracted files
destination_folder="/volume1/Series"

# Function to recursively process files in a directory
process_directory() {
  if [ -d "$1" ]; then
    # Extract series title from the source folder name (only once per directory)
    source_folder_name=$(basename "$1")

    # Check if there are any .rar files in the current directory
    if ls "$1"/*.rar &>/dev/null; then 

      # Clear processed_files before processing a new folder
      processed_files=()

      # Process all rar files in the current directory at once, considering processed_files
      if [[ ${#processed_files[@]} -eq 0 ]] || compgen -G "$1"/*.rar | grep -v -F "${processed_files[@]}" &>/dev/null; then
          # Find the first occurrence of any stopping pattern (allow any whitespace before patterns)
        match=$(grep -ioE '\s*(19|20)[0-9]{2}|\s*[SsEe][0-9]{2}' <<< "$source_folder_name" | head -n 1)

        if [ -n "$match" ]; then
            # Find the position of the space BEFORE the match
            end_pos=$(grep -boE '\s*(19|20)[0-9]{2}|\s*[SsEe][0-9]{2}' <<< "$source_folder_name" | head -n 1 | cut -d: -f1)

            # Extract the series title using substring and remove trailing space, hyphen, or period
            series_title="${source_folder_name:0:$end_pos}" 
            series_title="${series_title%[-. ]}" # Clean up the title directly here
        else
            # Handle cases where no match is found
            echo "Warning: Could not extract series title from '$source_folder_name'. Using the full folder name."
            series_title="$source_folder_name"
        fi

        # Create the series folder in the destination if it doesn't exist (only once per directory)
        if find "$1" -type f -name "*.rar" | grep -q '.'; then
          series_folder="$destination_folder/$series_title"
          mkdir -p "$series_folder"
        fi

        # Handle multi-part archives first and track processed files
        processed_files=()
        for rar_file in "$1"/*.part[0-9]*.rar; do
          if [[ ! " ${processed_files[*]} " =~ " $rar_file " ]]; then # Skip already processed files
            # Find all parts of the archive
            archive_parts=($(ls "${rar_file%.*[0-9].rar}".part*.rar 2>/dev/null | sort -V))
            if [ ${#archive_parts[@]} -gt 1 ]; then
              # Extract to the destination folder
              unrar e -o+ "${archive_parts[0]}" "$destination_folder"
              # Delete all parts of the archive
              rm "${archive_parts[@]}" 2>/dev/null
              # Add processed files to the list
              processed_files+=("${archive_parts[@]}")
            fi
          fi
        done

        # Handle single-part archives, skipping already processed files
        for rar_file in "$1"/*.rar; do
          if [[ ! "$rar_file" =~ .part[0-9]+.rar$ && ! " ${processed_files[*]} " =~ " $rar_file " ]]; then
            unrar e -o+ "$rar_file" "$destination_folder"
          fi
        done

        # Move files containing series_title from destination_folder root to series_folder (only once per directory)
        for root_file in "$destination_folder"/*; do
          if [[ -f "$root_file" && "$root_file" == *"$series_title"* ]]; then
            mv "$root_file" "$series_folder"
          fi
        done
      fi

    else
      echo "No .rar files found in $1" 
    fi

    # Don't think we need subdir of subdir, but maybe when downloading full season....
    # Recursively process subdirectories
    for subdir in "$1"/*/; do
        if [[ "${subdir##*/}" == @* ]]; then
            continue 
        fi

      process_directory "$subdir"

      # Delete empty directories source
      delete_empty_directories "$subdir"
    done
  fi
}

# Function to recursively delete non-extracted files (only .rar files now)
delete_non_extracted_files() {
    shopt -s dotglob nullglob # Include hidden files and handle empty patterns
  for file in "$1"/*; do
    if [[ "$file" == *.rar ]]; then
      # Delete rar files
      echo "Attempting to remove RAR file: $file"  # Add debugging statement
      rm "$file" 2>/dev/null
      if [ $? -ne 0 ]; then
            echo "Failed to remove RAR file: $file"  # Add error message
        fi
    fi
  done
  shopt -u dotglob nullglob # Reset shell options
}

# Function to recursively delete empty directories
delete_empty_directories() {
    shopt -s dotglob nullglob # Include hidden files and handle empty patterns
    for item in "$1"/*; do
        if [ -d "$item" ] && [[ ! -L "$item" ]]; then # Skip symbolic links
            # Skip directories starting with '@'
            if [[ "${item##*/}" == @* ]]; then
                continue 
            fi
            delete_empty_directories "$item"
            if [ -z "$(ls -A "$item")" ]; then
                echo "Attempting to remove directory: $item"
                rmdir "$item" 2>/dev/null
                if [ $? -ne 0 ]; then
                    echo "Failed to remove directory: $item"
                fi
            fi
        fi
    done
    shopt -u dotglob nullglob # Reset shell options
}

# Check if the source and destination folders exist
if [ ! -d "$folder_to_scan" ]; then
  echo "Error: Source folder '$folder_to_scan' does not exist."
  exit 1
fi

if [ ! -d "$destination_folder" ]; then
  echo "Error: Destination folder '$destination_folder' does not exist."
  exit 1
fi

process_directory "$folder_to_scan"

# Delete empty directories destination
delete_empty_directories "$folder_to_scan"

# Delete empty directories destination
delete_empty_directories "$destination_folder"