#!/bin/bash
# Command Center Dashboard Refresh Script
source "$(dirname "$0")/.env" 2>/dev/null || true
# Usage: ./refresh-dashboard.sh [hourly|full]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-full}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

echo "🍟 Dashboard refresh: $MODE"
echo "Time: $(TZ='America/Denver' date '+%Y-%m-%d %H:%M %Z')"

# Load existing data
if [ -f data_inject.json ]; then
    cp data_inject.json data_inject.json.bak
fi

python3 << PYEOF
import json
import subprocess
import csv
from datetime import datetime

def sh(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip()

# Load existing data or create new
try:
    with open('data_inject.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

mode = "$MODE"
print(f"Mode: {mode}")

# ============================================
# HOURLY: Email + Calendar only
# ============================================
if mode in ['hourly', 'full']:
    print("📧 Fetching email...")
    # Get unread emails that might need reply
    emails_raw = sh('gog gmail search "in:inbox is:unread -category:promotions -category:social -category:updates -from:noreply -from:no-reply" --max 10 --json 2>/dev/null')
    try:
        emails_data = json.loads(emails_raw)
        threads = emails_data.get('threads') or []
        data['emails'] = [{"from": t.get('from', 'Unknown'), "subject": t.get('subject', 'No subject'), "date": t.get('date', '')} for t in threads[:10]]
    except:
        data['emails'] = []
    print(f"   Found {len(data.get('emails', []))} emails")

    print("📅 Fetching calendar...")
    from datetime import datetime, timedelta
    now = datetime.utcnow()
    from_date = now.strftime('%Y-%m-%dT00:00:00Z')
    to_date = (now + timedelta(days=8)).strftime('%Y-%m-%dT00:00:00Z')
    cal_raw = sh(f'gog calendar events primary --from {from_date} --to {to_date} --json 2>/dev/null')
    try:
        cal_data = json.loads(cal_raw)
        events = cal_data.get('events') or []
        month_map = {'01':'JAN','02':'FEB','03':'MAR','04':'APR','05':'MAY','06':'JUN',
                     '07':'JUL','08':'AUG','09':'SEP','10':'OCT','11':'NOV','12':'DEC'}
        data['calendar'] = []
        for e in events[:10]:
            start = e.get('start', {})
            dt = start.get('dateTime') or start.get('date', '')
            parts = dt.split('T')[0].split('-')
            data['calendar'].append({
                "day": parts[2].lstrip('0') if len(parts) > 2 else "?",
                "month": month_map.get(parts[1], "???") if len(parts) > 1 else "???",
                "title": e.get('summary', 'Untitled'),
                "time": dt.split('T')[1][:5] if 'T' in dt else 'All day'
            })
    except:
        pass
    print(f"   Found {len(data.get('calendar', []))} events")

# ============================================
# FULL: Everything else (weather, snow, avy, etc.)
# ============================================
if mode == 'full':
    print("🌤️ Fetching weather...")
    def get_weather(location, display):
        raw = sh(f'curl -s "wttr.in/{location}?format=%c|%t|H:%h&u"')
        parts = raw.split('|')
        return {
            "location": display,
            "icon": parts[0].strip() if len(parts) > 0 else "?",
            "temp": parts[1].strip() if len(parts) > 1 else "?",
            "humidity": parts[2].strip() if len(parts) > 2 else ""
        }
    
    data['weather'] = [
        get_weather("Denver,CO", "Denver, CO"),
        get_weather("Silverton,CO", "Silverton, CO"),
        get_weather("Salt+Lake+City,UT", "Salt Lake City, UT"),
        get_weather("Park+City,UT", "Park City, UT")
    ]
    
    print("🏔️ Setting snow conditions...")
    data['snow'] = [
        {"resort": "Arapahoe Basin", "snow24": 0, "snow48": 0, "forecast": "Dry"},
        {"resort": "Copper Mountain", "snow24": 0, "snow48": 0, "forecast": "Dry"},
        {"resort": "Winter Park", "snow24": 0, "snow48": 0, "forecast": "Dry"},
        {"resort": "Brighton", "snow24": 0, "snow48": 0, "forecast": "Dry"},
        {"resort": "Alta", "snow24": 0, "snow48": 0, "forecast": "Dry"}
    ]

# Update timestamp
data['lastUpdated'] = datetime.now().strftime("%b %d, %Y at %I:%M %p MST")

# Save data
with open('data_inject.json', 'w') as f:
    json.dump(data, f)

print("✅ Data updated")
PYEOF

# Inject into HTML
python3 << 'PYEOF'
import json

with open('index.html', 'r') as f:
    html = f.read()

with open('data_inject.json', 'r') as f:
    data = json.load(f)

data_str = json.dumps(data)

start_marker = 'const DASHBOARD_DATA = '
start_idx = html.find(start_marker) + len(start_marker)

depth = 0
end_idx = start_idx
for i, c in enumerate(html[start_idx:], start_idx):
    if c == '{': depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            end_idx = i + 1
            break

semi_idx = html.find(';', end_idx)
new_html = html[:start_idx] + data_str + html[semi_idx:]

with open('index.html', 'w') as f:
    f.write(new_html)

print("✅ HTML injected")
PYEOF

# Push to GitHub
echo "📤 Pushing to GitHub..."
git add -A
git diff --cached --quiet && echo "No changes to push" && exit 0
git commit -m "Dashboard refresh: $MODE - $(TZ='America/Denver' date '+%Y-%m-%d %H:%M')"
git push origin main 2>&1

echo "✅ Dashboard updated!"
