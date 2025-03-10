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
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Default specification path: api.yaml"
    exit 0
}

# Set default parameters
PERIOD="yesterday"
SPEC_PATH="api.yaml"
BRANCH="main"

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

# Get required dates
TODAY=$(date "+%Y-%m-%d")
YESTERDAY=$(get_yesterday)
WEEK_AGO=$(get_week_ago)

case $PERIOD in
    "today")
        START_DATE="${YESTERDAY}T23:59:59"
        END_DATE="${TODAY}T23:59:59"
        PERIOD_DESC="today (from the last commit yesterday to the latest current commit)"
        ;;
    "yesterday")
        START_DATE="${YESTERDAY}T00:00:00"
        END_DATE="${YESTERDAY}T23:59:59"
        PERIOD_DESC="yesterday"
        ;;
    "week")
        START_DATE="${WEEK_AGO}T00:00:00"
        END_DATE="${TODAY}T23:59:59"
        PERIOD_DESC="for the last 7 days"
        ;;
esac

echo "Looking for commits in branch $BRANCH $PERIOD_DESC..."

# Make sure we have up-to-date information about the selected branch
git fetch origin $BRANCH --quiet

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
oasdiff changelog v1.yaml v2.yaml -f html > diff.html
oasdiff breaking v1.yaml v2.yaml --lang singleline > breaking.md
echo "API changes collected."