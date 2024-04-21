#!/bin/bash

# Check if an API key is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <API_KEY>"
    exit 1
fi

# Assign API key from first script argument
API_KEY="$1"

# Array to store monitor names and IDs
monitor_array=()

# Function to check if monitor already exists in the array
monitor_exists() {
    local monitor=$1
    for existing_monitor in "${monitor_array[@]}"; do
        if [[ $existing_monitor == *"$monitor"* ]]; then
            return 0
        fi
    done
    return 1
}

# Fetch monitors from all pages
offset=0
while : ; do
    # Get list of monitors with offset
    response=$(curl -s "https://api.uptimerobot.com/v2/getMonitors" -d "api_key=$API_KEY&format=json&logs=0&response_times=0&offset=$offset")

    # Check if API request was successful
    if [[ $(echo "$response" | jq -r '.stat') == "ok" ]]; then
        # Extract monitor names and IDs
        monitors=$(echo "$response" | jq -r '.monitors[] | "\(.friendly_name): \(.id)"' 2>/dev/null)

        # Split monitor names and IDs into an array
        if [[ -n $monitors ]]; then
            IFS=$'\n' read -rd '' -a monitors_array <<< "$monitors"

            # Add unique monitors to the array
            for monitor in "${monitors_array[@]}"; do
                if ! monitor_exists "$monitor"; then
                    monitor_array+=("$monitor")
                fi
            done
        fi

        # Check if there are more monitors to fetch
        total_monitors=$(echo "$response" | jq -r '.pagination.total')
        offset=$((offset + 50))

        # Break the loop if all monitors have been fetched
        if [[ ${#monitor_array[@]} -ge $total_monitors ]]; then
            break
        fi
    else
        echo "Failed to retrieve monitors"
        exit 1
    fi
done

# Display monitor names and IDs
echo "Monitors:"
for monitor in "${monitor_array[@]}"; do
    echo "$monitor"
done
