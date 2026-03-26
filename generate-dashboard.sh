#!/bin/bash
# Command Center Dashboard Generator
# This script fetches all data and generates the HTML dashboard

set -e

OUTPUT_DIR="/root/clawd/command-center"
DATA_FILE="$OUTPUT_DIR/data.json"
HTML_FILE="$OUTPUT_DIR/index.html"

echo "Fetching data..."

# Weather data
echo "Getting weather..."
DENVER_WEATHER=$(curl -s "wttr.in/Denver,CO?format=%c+%t+|+H:%h+|+Wind:%w&u" 2>/dev/null || echo "N/A")
SILVERTON_WEATHER=$(curl -s "wttr.in/Silverton,CO?format=%c+%t+|+H:%h+|+Wind:%w&u" 2>/dev/null || echo "N/A")
SLC_WEATHER=$(curl -s "wttr.in/Salt+Lake+City,UT?format=%c+%t+|+H:%h+|+Wind:%w&u" 2>/dev/null || echo "N/A")
PARK_CITY_WEATHER=$(curl -s "wttr.in/Park+City,UT?format=%c+%t+|+H:%h+|+Wind:%w&u" 2>/dev/null || echo "N/A")

echo "Weather fetched."
echo "Denver: $DENVER_WEATHER"
echo "Silverton: $SILVERTON_WEATHER"
echo "SLC: $SLC_WEATHER"
echo "Park City: $PARK_CITY_WEATHER"
