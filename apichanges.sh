#!/bin/bash

# Function to display help
show_help() {
    echo "Usage: $0 [options] [specification_path]"
    echo "Options:"
    echo "  -t, --today     Calculate differences for today (from the last commit yesterday to the latest current commit)"
    echo "  -y, --yesterday Calculate differences for yesterday (default)"
    echo "  -w, --week      Calculate differences for the last 7 days"
    echo "  -b, --branch    Specify branch for analysis (default: main)"
    echo "  -p, --path      Specify path to the specification file"
    echo "  -c, --clean     Remove all created files in the end"
    echo "  -u, --upload    Upload file to 0x0.st free file hoster and copy link to clipboard"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Default specification path: api.yaml"
    exit 0
}

# Set default parameters
PERIOD="yesterday"
SPEC_PATH="api.yaml"
BRANCH="main"
UPLOAD=false
CLEAN=false

# Process command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--today) PERIOD="today" ;;
        -y|--yesterday) PERIOD="yesterday" ;;
        -w|--week) PERIOD="week" ;;
        -b|--branch)
            BRANCH="$2"
            shift
            ;;
        -p|--path)
            SPEC_PATH="$2"
            shift
            ;;
        -u|--upload) UPLOAD=true ;;
        -c|--clean) CLEAN=true ;;
        -h|--help) show_help ;;
        -*) echo "Unknown option: $1" >&2; show_help ;;
        *)
            # If a positional argument is provided, use it as SPEC_PATH
            SPEC_PATH="$1"
            break
            ;;
    esac
    shift
done


# Function to check and install oasdiff
check_and_install_oasdiff() {
    if ! command -v oasdiff &> /dev/null; then
        echo "oasdiff utility not found. Installing..."
        curl -fsSL https://raw.githubusercontent.com/tufin/oasdiff/main/install.sh | sh

        # Check if installation was successful
        if ! command -v oasdiff &> /dev/null; then
            echo "Error: Failed to install oasdiff. Please install it manually."
            exit 1
        else
            echo "oasdiff successfully installed."
        fi
    else
        echo "oasdiff is already installed."
    fi
}

check_and_install_oasdiff

echo "Using specification path: $SPEC_PATH"
echo "Using branch: $BRANCH"

# Define dates based on the selected period
# Function to convert Unix timestamp to date in YYYY-MM-DD format
timestamp_to_date() {
    local timestamp=$1
    # Try with GNU date (Linux)
    date -d "@$timestamp" "+%Y-%m-%d" 2>/dev/null || \
    # Try with BSD date (macOS)
    date -r "$timestamp" "+%Y-%m-%d" 2>/dev/null || \
    # Try with busybox date (Alpine)
    date -D "%s" -d "$timestamp" "+%Y-%m-%d" 2>/dev/null || \
    # Fallback using Perl (should work everywhere)
    perl -e "print scalar(localtime($timestamp))" | awk '{print $5"-"$2"-"$3}'
}

# Get yesterday's date in YYYY-MM-DD format
get_yesterday() {
    local today_timestamp=$(date +%s)
    local yesterday_timestamp=$((today_timestamp - 86400))
    timestamp_to_date $yesterday_timestamp
}

# Get date from 7 days ago in YYYY-MM-DD format
get_week_ago() {
    local today_timestamp=$(date +%s)
    local week_ago_timestamp=$((today_timestamp - 604800))
    timestamp_to_date $week_ago_timestamp
}

# Modify specification version with period suffix
update_version() {
    local file="$1"
    local date_suffix="$2"

    if command -v sed &> /dev/null; then
        if sed --version 2>/dev/null | grep -q GNU; then
            # GNU sed (Linux)
            sed -i "s/\(version: [0-9.]*\)/\1-$date_suffix/" "$file"
        else
            # BSD sed (macOS)
            sed -i "" "s/\(version: [0-9.]*\)/\1-$date_suffix/" "$file"
        fi
    else
        # Backup option using awk
        local temp_file="${file}.tmp"
        awk -v date="$date_suffix" '{
            if ($0 ~ /version: [0-9.]+/) {
                print $0 "-" date
            } else {
                print $0
            }
        }' "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}


# Get required dates
TODAY=$(date "+%Y-%m-%d")
YESTERDAY=$(get_yesterday)
WEEK_AGO=$(get_week_ago)
TODAY_SHORT=$(date "+%Y%m%d")
YESTERDAY_SHORT=$(date -d "$YESTERDAY" "+%Y%m%d" 2>/dev/null || date -j -f "%Y-%m-%d" "$YESTERDAY" "+%Y%m%d" 2>/dev/null || echo "$YESTERDAY" | tr -d '-')
WEEK_AGO_SHORT=$(date -d "$WEEK_AGO" "+%Y%m%d" 2>/dev/null || date -j -f "%Y-%m-%d" "$WEEK_AGO" "+%Y%m%d" 2>/dev/null || echo "$WEEK_AGO" | tr -d '-')



case $PERIOD in
    "today")
        START_DATE="${YESTERDAY}T23:59:59"
        END_DATE="${TODAY}T23:59:59"
        START_DATE_SHORT="${YESTERDAY_SHORT}"
        END_DATE_SHORT="${TODAY_SHORT}"
        ;;
    "yesterday")
        START_DATE="${YESTERDAY}T00:00:00"
        END_DATE="${YESTERDAY}T23:59:59"
        START_DATE_SHORT="${YESTERDAY_SHORT}start"
        END_DATE_SHORT="${YESTERDAY_SHORT}end"
        ;;
    "week")
        START_DATE="${WEEK_AGO}T00:00:00"
        END_DATE="${TODAY}T23:59:59"
        START_DATE_SHORT="${WEEK_AGO_SHORT}"
        END_DATE_SHORT="${TODAY_SHORT}"
        ;;
esac

echo "Looking for commits in branch $BRANCH for $PERIOD ..."

# Make sure we have up-to-date information about the selected branch
git checkout $BRANCH
git pull origin $BRANCH --quiet

# 1. Find the earliest commit for the selected period in the selected branch
EARLIEST_COMMIT=$(git log origin/$BRANCH --after="$START_DATE" --before="$END_DATE" --format="%H" --reverse | head -n 1)
if [ -z "$EARLIEST_COMMIT" ]; then
    echo "No commits found in branch $BRANCH for the selected period"
    exit 1
fi
echo "Earliest commit in $BRANCH for the selected period: $EARLIEST_COMMIT"

# 2. Save the file from the earliest commit as v1.yaml
git show "$EARLIEST_COMMIT:$SPEC_PATH" > v1.yaml
if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve file $SPEC_PATH from commit $EARLIEST_COMMIT"
    exit 1
fi
echo "File v1.yaml saved"

# 3. Find the latest commit for the selected period in the selected branch
LATEST_COMMIT=$(git log origin/$BRANCH --after="$START_DATE" --before="$END_DATE" --format="%H" | head -n 1)
echo "Latest commit in $BRANCH for the selected period: $LATEST_COMMIT"

# Save the file from the latest commit as v2.yaml
git show "$LATEST_COMMIT:$SPEC_PATH" > v2.yaml
if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve file $SPEC_PATH from commit $LATEST_COMMIT"
    exit 1
fi
echo "File v2.yaml saved"

# Collect API changes
echo "Collecting API changes"
oasdiff summary v1.yaml v2.yaml > summary.yaml

update_version "v1.yaml" "$START_DATE_SHORT"
update_version "v2.yaml" "$END_DATE_SHORT"
echo "File versions updated with period suffix for understandable changelog"

if [ -f "oasdiff-levels.txt" ]; then
  oasdiff changelog v1.yaml v2.yaml -f html --severity-levels oasdiff-levels.txt > changelog.html
  oasdiff breaking v1.yaml v2.yaml -f singleline --severity-levels oasdiff-levels.txt > breaking.md
else
  oasdiff changelog v1.yaml v2.yaml -f html > changelog.html
  oasdiff breaking v1.yaml v2.yaml -f singleline > breaking.md
fi

echo "API changes collected."

cat summary.yaml
cat breaking.md

# Upload changelog.html if requested
if [ "$UPLOAD" = true ]; then
    upload_file "changelog.html"
    echo "Uploading changelog.html to 0x0.st..."
    LINK=$(curl -F "file=@changelog.html" https://0x0.st)
    echo "File available at: $LINK"
    echo "Link copied to clipboard (if xclip or pbcopy is installed)"

    # Try to copy the link to clipboard
    if command -v xclip >/dev/null 2>&1; then
        echo "$LINK" | xclip -selection clipboard
    elif command -v pbcopy >/dev/null 2>&1; then
        echo "$LINK" | pbcopy
    fi
fi

# Cleanup
if [ "$CLEAN" = true ]; then
    rm summary.yaml changelog.html breaking.md v1.yaml v2.yaml
fi