#!/bin/bash
# Command Center Dashboard Refresh Script
# Updates everything hourly (weather, email, calendar, avy, snow forecasts)
source "$(dirname "$0")/.env" 2>/dev/null || true

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BACKCOUNTRY_CSV="/root/clawd/memory/SNOTEL_backcountry_master.csv"

echo "🍟 Dashboard refresh (hourly)"
echo "Time: $(TZ='America/Denver' date '+%Y-%m-%d %H:%M %Z')"

# Load existing data
if [ -f data_inject.json ]; then
    cp data_inject.json data_inject.json.bak
fi

python3 << PYEOF
import json
import subprocess
import csv
import urllib.request
from datetime import datetime, timedelta

def sh(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip()

# Load existing data or create new
try:
    with open('data_inject.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

# ============================================
# 1. WEATHER
# ============================================
print("🌤️ Fetching weather...")

def get_weather_openmeteo(lat, lon, name):
    try:
        url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,relative_humidity_2m,weather_code&temperature_unit=fahrenheit"
        with urllib.request.urlopen(url, timeout=10) as response:
            api_data = json.loads(response.read())
            current = api_data.get('current', {})
            temp = current.get('temperature_2m', '?')
            humidity = current.get('relative_humidity_2m', '?')
            code = current.get('weather_code', 0)
            icons = {0: '☀️', 1: '🌤️', 2: '⛅', 3: '☁️', 45: '🌫️', 48: '🌫️',
                     51: '🌧️', 53: '🌧️', 55: '🌧️', 61: '🌧️', 63: '🌧️', 65: '🌧️',
                     71: '🌨️', 73: '🌨️', 75: '🌨️', 77: '🌨️', 80: '🌧️', 81: '🌧️',
                     82: '🌧️', 85: '🌨️', 86: '🌨️', 95: '⛈️', 96: '⛈️', 99: '⛈️'}
            return {"location": name, "icon": icons.get(code, '🌡️'), "temp": f"{temp}°F", "humidity": f"H:{humidity}%"}
    except:
        return {"location": name, "icon": "?", "temp": "N/A", "humidity": ""}

data['weather'] = [
    get_weather_openmeteo(39.7392, -104.9903, "Denver, CO"),
    get_weather_openmeteo(37.8117, -107.6644, "Silverton, CO"),
    get_weather_openmeteo(40.7608, -111.8910, "Salt Lake City, UT"),
    get_weather_openmeteo(40.6461, -111.4980, "Park City, UT")
]
print(f"   Got weather for {len(data['weather'])} locations")

# ============================================
# 2. EMAIL
# ============================================
print("📧 Fetching email...")
emails_raw = sh('gog gmail search "in:inbox is:unread -category:promotions -category:social -category:updates -from:noreply -from:no-reply" --max 10 --json 2>/dev/null')
try:
    emails_data = json.loads(emails_raw)
    threads = emails_data.get('threads') or []
    data['emails'] = [{"from": t.get('from', 'Unknown'), "subject": t.get('subject', 'No subject'), "date": t.get('date', '')} for t in threads[:10]]
except:
    data['emails'] = []
print(f"   Found {len(data.get('emails', []))} emails")

# ============================================
# 3. CALENDAR
# ============================================
print("📅 Fetching calendar...")
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
# 4. AVALANCHE DANGER (with CAIC polygon matching)
# ============================================
print("⚠️ Fetching avy danger ratings...")

def point_in_polygon(x, y, polygon):
    """Ray casting algorithm for point-in-polygon check"""
    n = len(polygon)
    inside = False
    p1x, p1y = polygon[0]
    for i in range(1, n + 1):
        p2x, p2y = polygon[i % n]
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xinters:
                        inside = not inside
        p1x, p1y = p2x, p2y
    return inside

def get_polygon_coords(geometry):
    """Extract coordinate list from polygon/multipolygon geometry"""
    if geometry['type'] == 'Polygon':
        return [geometry['coordinates'][0]]
    elif geometry['type'] == 'MultiPolygon':
        return [poly[0] for poly in geometry['coordinates']]
    return []

try:
    avy_url = "https://api.avalanche.org/v2/public/products/map-layer"
    avy_req = urllib.request.Request(avy_url, headers={'User-Agent': 'TSL-CommandCenter/1.0'})
    with urllib.request.urlopen(avy_req, timeout=20) as avy_response:
        avy_api = json.loads(avy_response.read())
    
    danger_map = {-1: ("No Rating", "no-rating"), 0: ("No Rating", "no-rating"), 
                  1: ("Low", "low"), 2: ("Moderate", "moderate"), 
                  3: ("Considerable", "considerable"), 4: ("High", "high"), 5: ("Extreme", "extreme")}
    
    # Separate features by center
    caic_features = []
    zones_by_center = {}
    
    for feature in avy_api.get('features', []):
        props = feature.get('properties', {})
        center = props.get('center_id', '')
        name = props.get('name', '')
        danger = props.get('danger_level', 0)
        rating, rating_class = danger_map.get(danger, ("No Rating", "no-rating"))
        
        if center == 'CAIC':
            caic_features.append(feature)
        else:
            if center not in zones_by_center:
                zones_by_center[center] = {}
            zones_by_center[center][name] = {"zone": name, "rating": rating, "ratingClass": rating_class}
    
    # COLORADO - Point-in-polygon matching for CAIC zones
    # Zone coordinates from backcountry master DB
    caic_zones = {
        "Front Range": (39.8, -105.7),
        "Vail & Summit County": (39.55, -106.2),
        "Aspen": (39.1576, -106.8201),
        "Gunnison": (38.7, -106.9),
        "Grand Mesa": (39.02, -108.2),
        "Sawatch": (39.0, -106.5),
        "Northern San Juan": (37.9, -107.7),
        "Southern San Juan": (37.4, -106.6),
        "Steamboat & Flat Tops": (40.45, -106.8)
    }
    
    colorado = []
    for zone_name, (lat, lon) in caic_zones.items():
        zone_rating = "No Rating"
        zone_class = "no-rating"
        
        # Check each CAIC polygon
        for feature in caic_features:
            geometry = feature.get('geometry', {})
            danger = feature.get('properties', {}).get('danger_level', 0)
            
            try:
                polygons = get_polygon_coords(geometry)
                for poly in polygons:
                    if point_in_polygon(lon, lat, poly):
                        zone_rating, zone_class = danger_map.get(danger, ("No Rating", "no-rating"))
                        break
                if zone_rating != "No Rating":
                    break
            except:
                continue
        
        colorado.append({"zone": zone_name, "rating": zone_rating, "ratingClass": zone_class})
        print(f"   CO: {zone_name} → {zone_rating}")
    
    # UTAH (UAC) - Direct zone name matching
    uac = zones_by_center.get('UAC', {})
    utah_zones = ["Salt Lake", "Ogden", "Provo", "Uintas", "Skyline", "Logan", "Moab", "Abajos"]
    utah = [uac.get(z, {"zone": z, "rating": "No Rating", "ratingClass": "no-rating"}) for z in utah_zones]
    print(f"   Utah: {len(utah)} zones")
    
    # CALIFORNIA - Direct zone name matching
    sac = zones_by_center.get('SAC', {})
    esac = zones_by_center.get('ESAC', {})
    tahoe = sac.get("Central Sierra Nevada", {"zone": "Tahoe", "rating": "No Rating", "ratingClass": "no-rating"})
    tahoe["zone"] = "Tahoe"
    east_sierra = esac.get("Eastside Region", {"zone": "Eastern Sierra", "rating": "No Rating", "ratingClass": "no-rating"})
    east_sierra["zone"] = "Eastern Sierra"
    california = [tahoe, east_sierra, {"zone": "Shasta", "rating": "Low", "ratingClass": "low"}]
    print(f"   California: {len(california)} zones")
    
    data['avyDanger'] = {"colorado": colorado, "utah": utah, "california": california}
    
except Exception as e:
    print(f"   Avy data error: {e}")
    import traceback
    traceback.print_exc()

# ============================================
# 5. SNOW FORECASTS (NWS)
# ============================================
print("🏔️ Fetching snow forecasts from NWS...")

RESORTS = {
    "Arapahoe Basin": (39.6324, -105.871),
    "Copper Mountain": (39.4817, -106.15),
    "Winter Park": (39.8864, -105.7625),
    "Steamboat": (40.4537, -106.7587),
    "Brighton": (40.5981, -111.5831),
    "Alta": (40.5784, -111.6328)
}

def get_nws_snow(lat, lon):
    try:
        points_url = f"https://api.weather.gov/points/{lat},{lon}"
        req = urllib.request.Request(points_url, headers={'User-Agent': 'TSL-CommandCenter/1.0'})
        with urllib.request.urlopen(req, timeout=15) as response:
            points_data = json.loads(response.read())
        grid_url = points_data['properties']['forecastGridData']
        req = urllib.request.Request(grid_url, headers={'User-Agent': 'TSL-CommandCenter/1.0'})
        with urllib.request.urlopen(req, timeout=15) as response:
            grid_data = json.loads(response.read())
        snow_values = grid_data['properties'].get('snowfallAmount', {}).get('values', [])
        daily_snow = {}
        for sv in snow_values:
            time_str = sv['validTime'].split('/')[0]
            dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
            day_key = dt.strftime('%a')
            mm = sv['value'] or 0
            inches = mm / 25.4
            if day_key not in daily_snow:
                daily_snow[day_key] = 0
            daily_snow[day_key] += inches
        snow_days = []
        for day, inches in daily_snow.items():
            if inches >= 0.5:
                rounded = round(inches)
                if rounded > 0:
                    snow_days.append(f"{day}: {rounded}\"")
        return ' | '.join(snow_days[:4]) if snow_days else 'Dry'
    except Exception as e:
        return 'N/A'

snow_data = []
for resort, (lat, lon) in RESORTS.items():
    forecast = get_nws_snow(lat, lon)
    snow_data.append({"resort": resort, "snow24": 0, "snow48": 0, "forecast": forecast})
    print(f"   {resort}: {forecast}")
data['snow'] = snow_data

# ============================================
# UPDATE TIMESTAMP
# ============================================
mst_time = subprocess.run(['date', '+%b %d, %Y at %I:%M %p %Z'], env={'TZ': 'America/Denver'}, capture_output=True, text=True).stdout.strip()
data['lastUpdated'] = mst_time

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
git commit -m "Dashboard refresh - $(TZ='America/Denver' date '+%Y-%m-%d %H:%M')"
git push origin main 2>&1

echo "✅ Dashboard updated!"
