
import json
from datetime import datetime, timezone

# Data from previous steps
current_ratings_raw = """
COLORADO:
  Front Range: Low
  Vail & Summit County: Low
  Sawatch: Low
  Aspen: Low
  Gunnison: Low
  Grand Mesa: Low
  North San Juan: Low
  South San Juan: Low

UTAH:
  Salt Lake: Moderate
  Ogden: No Rating
  Provo: No Rating
  Uintas: No Rating
  Skyline: No Rating
  Logan: No Rating
  Moab: No Rating
  Abajos: No Rating

CALIFORNIA:
  Tahoe: No Rating
  Eastern Sierra: Moderate
  Shasta: Low
"""

previous_ratings_json = """
{
  "date": "2026-04-04",
  "ratings": {
    "colorado": {
      "front-range": "Moderate",
      "vail-summit": "Moderate",
      "sawatch": "Moderate",
      "aspen": "Moderate",
      "gunnison": "Low",
      "grand-mesa": "Low",
      "north-san-juan": "Moderate",
      "south-san-juan": "Low"
    },
    "utah": {
      "salt-lake": "No Rating"
    },
    "california": {
      "eastern-sierra": "Moderate",
      "shasta": "No Rating"
    }
  }
}
"""

storm_watch_summary = "Front Range: slight_chance light snow_showers expected. Vail & Summit County: slight_chance light snow_showers expected. Sawatch: slight_chance light snow_showers expected. Aspen: slight_chance light snow_showers expected. Gunnison: slight_chance light snow_showers expected. Grand Mesa: slight_chance light snow_showers expected. North San Juan: slight_chance light snow_showers expected. South San Juan: Expecting 2 inches of snow in the next 48 hours."

# Helper Functions
def parse_current_ratings(raw_text):
    ratings = {"colorado": {}, "utah": {}, "california": {}}
    current_state = None
    for line in raw_text.strip().split('\n'):
        line = line.strip()
        if not line:
            continue
        if line.endswith(':'):
            state_name = line[:-1].lower()
            if state_name in ratings:
                current_state = state_name
        elif current_state and ':' in line:
            zone, rating = line.split(':', 1)
            key = zone.strip().lower().replace(' & ', '-').replace(' ', '-')
            ratings[current_state][key] = rating.strip()
    return ratings

def get_change_arrow(current, previous):
    if not previous or current == previous:
        return ""
    levels = ["No Rating", "Low", "Moderate", "Considerable", "High", "Extreme"]
    try:
        current_idx = levels.index(current)
        prev_idx = levels.index(previous)
        if current_idx > prev_idx:
            return "🔺"
        elif current_idx < prev_idx:
            return "🔻"
        else:
            return ""
    except ValueError:
        return ""

def format_rating(rating):
    emojis = {"Low": "🟢", "Moderate": "🟡", "Considerable": "🟠", "High": "🔴", "Extreme": "⚫️", "No Rating": "⚪️"}
    return f"{emojis.get(rating, '⚪️')} {rating}"

# Main logic
today_str = datetime.now(timezone.utc).strftime('%A, %B %d, %Y')
current_ratings = parse_current_ratings(current_ratings_raw)
previous_ratings = json.loads(previous_ratings_json)['ratings']

# Colorado
co_brief = "\\nCOLORADO:\\n"
co_zones = ["Front Range", "Vail & Summit County", "Sawatch", "Aspen", "Gunnison", "Grand Mesa", "North San Juan", "South San Juan"]
for zone in co_zones:
    key = zone.lower().replace(' & ', '-').replace(' ', '-')
    current = current_ratings.get("colorado", {}).get(key, "No Rating")
    previous = previous_ratings.get("colorado", {}).get(key, "No Rating")
    arrow = get_change_arrow(current, previous)
    co_brief += f"- {zone}: {format_rating(current)} {arrow}\\n"

# Utah
ut_brief = "\\nUTAH:\\n"
ut_zones = ["Salt Lake", "Ogden", "Provo", "Uintas", "Skyline", "Logan", "Moab", "Abajos"]
for zone in ut_zones:
    key = zone.lower().replace(' ', '-')
    current = current_ratings.get("utah", {}).get(key, "No Rating")
    previous = previous_ratings.get("utah", {}).get(key, "No Rating")
    arrow = get_change_arrow(current, previous)
    ut_brief += f"- {zone}: {format_rating(current)} {arrow}\\n"

# California
ca_brief = "\\nCALIFORNIA:\\n"
ca_zones = ["Tahoe", "Eastern Sierra", "Shasta"]
for zone in ca_zones:
    key = zone.lower().replace(' ', '-')
    current = current_ratings.get("california", {}).get(key, "No Rating")
    previous = previous_ratings.get("california", {}).get(key, "No Rating")
    arrow = get_change_arrow(current, previous)
    ca_brief += f"- {zone}: {format_rating(current)} {arrow}\\n"

# Assemble Brief
brief = f"""
☀️ SNOWLINE MORNING BRIEF - {today_str}

⚠️ AVY DANGER:
{co_brief.strip()}
{ut_brief.strip()}
{ca_brief.strip()}

🚨 SPECIAL ADVISORIES:
None today.

⚠️ AVY PROBLEMS TO WATCH:
Wet loose avalanches will be the primary concern as temperatures warm. Wind slabs may still be found on high-elevation, north-facing slopes.

🌨️ STORM WATCH:
{storm_watch_summary}

📢 SOCIAL WORTHY:
- Significant warming trend this week will increase wet avalanche danger. Good content for an educational post.
- South San Juan expecting a small refresh.
"""

# Output new JSON for storage
new_json = {
    "date": datetime.now(timezone.utc).strftime('%Y-%m-%d'),
    "ratings": current_ratings
}
print("--- NEW RATINGS JSON ---")
print(json.dumps(new_json, indent=2))
print("--- MORNING BRIEF ---")
print(brief.strip())
