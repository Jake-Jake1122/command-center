#!/bin/bash
# Command Center Dashboard Updater
# Fetches all data sources and regenerates the dashboard HTML

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/index.html"
TEMPLATE_FILE="$SCRIPT_DIR/template.html"
DATA_FILE="$SCRIPT_DIR/data.json"
WORKSPACE="/root/clawd"

echo "🍟 Updating Command Center Dashboard..."
echo "Time: $(date '+%Y-%m-%d %H:%M %Z')"

# ============================================
# 1. WEATHER DATA
# ============================================
echo "📡 Fetching weather..."

fetch_weather() {
    local location="$1"
    local display_name="$2"
    # Get current conditions + forecast
    local current=$(curl -s "wttr.in/${location}?format=%c|%t|%h|%w&u" 2>/dev/null | head -1)
    local forecast=$(curl -s "wttr.in/${location}?format=%c+%t&1&u" 2>/dev/null | tail -1)
    echo "${display_name}|${current}|${forecast}"
}

WEATHER_DENVER=$(fetch_weather "Denver,CO" "Denver, CO")
WEATHER_SILVERTON=$(fetch_weather "Silverton,CO" "Silverton, CO")
WEATHER_SLC=$(fetch_weather "Salt+Lake+City,UT" "Salt Lake City, UT")
WEATHER_PARK_CITY=$(fetch_weather "Park+City,UT" "Park City, UT")

echo "  Denver: $WEATHER_DENVER"
echo "  Silverton: $WEATHER_SILVERTON"
echo "  SLC: $WEATHER_SLC"
echo "  Park City: $WEATHER_PARK_CITY"

# ============================================
# 2. CALENDAR DATA (next 7 days)
# ============================================
echo "📅 Fetching calendar..."

FROM_DATE=$(date -u +%Y-%m-%dT00:00:00Z)
TO_DATE=$(date -u -d "+8 days" +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v+8d +%Y-%m-%dT00:00:00Z)

CALENDAR_JSON=$(gog calendar events primary --from "$FROM_DATE" --to "$TO_DATE" --json 2>/dev/null || echo "[]")

echo "  Found $(echo "$CALENDAR_JSON" | jq 'length' 2>/dev/null || echo 0) events"

# ============================================
# 3. EMAIL DATA (needs reply)
# ============================================
echo "📧 Fetching emails needing reply..."

# Search for emails in inbox that are unread and might need reply
# Excluding newsletters, notifications, etc.
EMAILS_JSON=$(gog gmail search "in:inbox is:unread -category:promotions -category:social -category:updates -from:noreply -from:no-reply" --max 10 --json 2>/dev/null || echo "[]")

echo "  Found $(echo "$EMAILS_JSON" | jq 'length' 2>/dev/null || echo 0) emails"

# ============================================
# 4. TASKS FROM HEARTBEAT.MD
# ============================================
echo "☑️ Parsing tasks from HEARTBEAT.md..."

HEARTBEAT_FILE="$WORKSPACE/HEARTBEAT.md"
TASKS_BUGS=""
TASKS_TODO=""

if [ -f "$HEARTBEAT_FILE" ]; then
    # Extract pending items (unchecked checkboxes)
    TASKS_TODO=$(grep -E '^\s*-\s*\[\s*\]' "$HEARTBEAT_FILE" | sed 's/^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]*//' | head -10)
fi

echo "  Loaded tasks"

# ============================================
# 5. CRON OUTPUTS
# ============================================
echo "📋 Loading cron outputs..."

CRON_BRIEF_FILE="$WORKSPACE/command-center/cron-brief.txt"
CRON_DIGEST_FILE="$WORKSPACE/command-center/cron-digest.txt"

CRON_BRIEF=""
CRON_DIGEST=""

[ -f "$CRON_BRIEF_FILE" ] && CRON_BRIEF=$(cat "$CRON_BRIEF_FILE")
[ -f "$CRON_DIGEST_FILE" ] && CRON_DIGEST=$(cat "$CRON_DIGEST_FILE")

echo "  Loaded cron outputs"

# ============================================
# 6. SNOTEL DATA
# ============================================
echo "🔍 Loading SNOTEL mappings..."

SNOTEL_RESORTS_FILE="$WORKSPACE/memory/SNOTEL_resorts_master.csv"
SNOTEL_BACKCOUNTRY_FILE="$WORKSPACE/memory/SNOTEL_backcountry_master.csv"

SNOTEL_DATA="[]"

if [ -f "$SNOTEL_RESORTS_FILE" ]; then
    # Convert CSV to JSON array (simplified)
    SNOTEL_DATA=$(tail -n +2 "$SNOTEL_RESORTS_FILE" | head -100 | awk -F',' '{
        gsub(/"/, "\\\"", $1);
        gsub(/"/, "\\\"", $0);
        print "{\"name\":\"" $1 "\",\"lat\":\"" $2 "\",\"lon\":\"" $3 "\",\"snotelStation\":\"" $4 "\",\"snotelName\":\"" $5 "\",\"source\":\"" $6 "\"}"
    }' | jq -s '.' 2>/dev/null || echo "[]")
fi

echo "  Loaded SNOTEL data"

# ============================================
# 7. SNOW CONDITIONS
# ============================================
echo "🏔️ Loading snow conditions..."

# For now, we'll use placeholder data - this can be enhanced with actual API calls
# The daily digest cron already has this data
SNOW_DATA='[
  {"resort": "Arapahoe Basin", "snow24": 0, "snow48": 0, "forecast": "Dry"},
  {"resort": "Copper Mountain", "snow24": 0, "snow48": 0, "forecast": "Dry"},
  {"resort": "Winter Park", "snow24": 0, "snow48": 0, "forecast": "Dry"},
  {"resort": "Brighton", "snow24": 0, "snow48": 0, "forecast": "Dry"},
  {"resort": "Alta", "snow24": 0, "snow48": 0, "forecast": "Dry"}
]'

echo "  Loaded snow conditions"

# ============================================
# BUILD JSON DATA OBJECT
# ============================================
echo "🔨 Building data object..."

LAST_UPDATED=$(date '+%b %d, %Y at %I:%M %p %Z')

# Build weather array
parse_weather() {
    local raw="$1"
    local location=$(echo "$raw" | cut -d'|' -f1)
    local icon=$(echo "$raw" | cut -d'|' -f2)
    local temp=$(echo "$raw" | cut -d'|' -f3)
    local humidity=$(echo "$raw" | cut -d'|' -f4)
    echo "{\"location\":\"$location\",\"icon\":\"$icon\",\"temp\":\"$temp\",\"high\":\"-\",\"low\":\"-\",\"humidity\":\"$humidity\",\"forecast\":\"\"}"
}

WEATHER_JSON="[
$(parse_weather "$WEATHER_DENVER"),
$(parse_weather "$WEATHER_SILVERTON"),
$(parse_weather "$WEATHER_SLC"),
$(parse_weather "$WEATHER_PARK_CITY")
]"

# Build calendar JSON from gog output
CALENDAR_FORMATTED=$(echo "$CALENDAR_JSON" | jq '[.[] | {
    day: (.start.dateTime // .start.date | split("T")[0] | split("-")[2]),
    month: (.start.dateTime // .start.date | split("T")[0] | split("-")[1] | if . == "01" then "JAN" elif . == "02" then "FEB" elif . == "03" then "MAR" elif . == "04" then "APR" elif . == "05" then "MAY" elif . == "06" then "JUN" elif . == "07" then "JUL" elif . == "08" then "AUG" elif . == "09" then "SEP" elif . == "10" then "OCT" elif . == "11" then "NOV" else "DEC" end),
    title: .summary,
    time: (if .start.dateTime then (.start.dateTime | split("T")[1] | split("-")[0] | split(":")[0:2] | join(":")) else "All day" end)
}][0:10]' 2>/dev/null || echo "[]")

# Build emails JSON from gog output
EMAILS_FORMATTED=$(echo "$EMAILS_JSON" | jq '[.[] | {
    from: (.from // "Unknown"),
    subject: (.subject // "No subject"),
    date: (.date // ""),
    urgent: false
}][0:10]' 2>/dev/null || echo "[]")

# Build tasks JSON
TASKS_JSON="{\"bugs\":[],\"todos\":["
FIRST=true
while IFS= read -r line; do
    [ -z "$line" ] && continue
    line=$(echo "$line" | sed 's/"/\\"/g' | sed 's/\*\*//g')
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        TASKS_JSON+=","
    fi
    TASKS_JSON+="{\"text\":\"$line\",\"priority\":\"medium\"}"
done <<< "$TASKS_TODO"
TASKS_JSON+="]}"

# Escape cron outputs for JSON
CRON_BRIEF_ESC=$(echo "$CRON_BRIEF" | jq -Rs '.' 2>/dev/null || echo '""')
CRON_DIGEST_ESC=$(echo "$CRON_DIGEST" | jq -Rs '.' 2>/dev/null || echo '""')

# Build final data object
DATA_OBJ=$(cat <<DATAJSON
{
  "lastUpdated": "$LAST_UPDATED",
  "weather": $WEATHER_JSON,
  "snow": $SNOW_DATA,
  "calendar": $CALENDAR_FORMATTED,
  "emails": $EMAILS_FORMATTED,
  "tasks": $TASKS_JSON,
  "cronBrief": $CRON_BRIEF_ESC,
  "cronDigest": $CRON_DIGEST_ESC,
  "snotelData": $SNOTEL_DATA
}
DATAJSON
)

# Save data to file
echo "$DATA_OBJ" > "$DATA_FILE"

# ============================================
# INJECT DATA INTO HTML
# ============================================
echo "💉 Injecting data into HTML..."

# Read template and replace placeholder
if [ -f "$OUTPUT_FILE" ]; then
    # Replace the DASHBOARD_DATA object in the HTML
    # Using a temp file to handle the replacement
    
    # Extract everything before and after the DASHBOARD_DATA declaration
    python3 << PYTHON
import re
import json

with open('$OUTPUT_FILE', 'r') as f:
    html = f.read()

data = '''$DATA_OBJ'''

# Replace the DASHBOARD_DATA object
pattern = r'const DASHBOARD_DATA = \{[^;]*\};'
replacement = f'const DASHBOARD_DATA = {data};'
html = re.sub(pattern, replacement, html, flags=re.DOTALL)

with open('$OUTPUT_FILE', 'w') as f:
    f.write(html)

print("Data injected successfully")
PYTHON
fi

echo ""
echo "✅ Dashboard updated successfully!"
echo "   File: $OUTPUT_FILE"
echo "   Time: $LAST_UPDATED"
