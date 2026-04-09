#!/bin/bash
# Command Center Dashboard Refresh Script
# Updates everything hourly (weather, email, calendar, avy, snow, storm watch, social worthy, digest, advisories)
# Does NOT touch: tasks, reminders, riddle (user-controlled)
source "$(dirname "$0")/.env" 2>/dev/null || true

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GITHUB_TOKEN="${GITHUB_TOKEN:-}"

echo "🍟 Dashboard refresh (hourly)"
echo "Time: $(TZ='America/Denver' date '+%Y-%m-%d %H:%M %Z')"

# Load existing data
if [ -f data_inject.json ]; then
    cp data_inject.json data_inject.json.bak
fi

python3 -u << 'PYEOF'
import json
import subprocess
import csv
import math
from datetime import datetime, timedelta, timezone

def sh(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip()

def curl_json(url, timeout=15):
    """Helper to run curl and parse JSON output."""
    cmd = ['curl', '-s', '-L', '--max-time', str(timeout), '-A', 'TSL-CommandCenter/1.0', url]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        # print(f"      curl error for {url}: {result.stderr}")
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        # print(f"      JSON decode error for {url}")
        return None

# Load existing data (preserve user-controlled fields)
try:
    with open('data_inject.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

# Preserve user-controlled fields
preserved_tasks = data.get('tasks', {})
preserved_reminders = data.get('reminders', [])
preserved_riddle = data.get('dailyRiddle', {})

# ============================================
# 1. WEATHER
# ============================================
print("🌤️ Fetching weather...")

def get_weather_nws(lat, lon, name, retries=3):
    print(f"   Fetching NWS weather for {name}...")
    try:
        points_url = f"https://api.weather.gov/points/{lat},{lon}"
        points_data = curl_json(points_url)
        if not points_data:
            return {"location": name, "icon": "?", "temp": "N/A", "humidity": ""}
        
        forecast_url = points_data.get('properties', {}).get('forecast')
        if not forecast_url:
            return {"location": name, "icon": "?", "temp": "N/A", "humidity": ""}

        forecast_data = curl_json(forecast_url)
        if not forecast_data:
            return {"location": name, "icon": "?", "temp": "N/A", "humidity": ""}

        current_period = forecast_data.get('properties', {}).get('periods', [{}])[0]
        temp = current_period.get('temperature', '?')
        short_forecast = current_period.get('shortForecast', '').lower()
        
        icon = '🌡️'
        if 'sun' in short_forecast or 'clear' in short_forecast: icon = '☀️'
        elif 'partly cloudy' in short_forecast: icon = '🌤️'
        elif 'mostly cloudy' in short_forecast: icon = '⛅'
        elif 'cloudy' in short_forecast: icon = '☁️'
        elif 'rain' in short_forecast or 'showers' in short_forecast: icon = '🌧️'
        elif 'snow' in short_forecast: icon = '🌨️'
        elif 'thunderstorm' in short_forecast: icon = '⛈️'
        elif 'fog' in short_forecast: icon = '🌫️'

        return {"location": name, "icon": icon, "temp": f"{temp}°F", "humidity": ""}
    except Exception as e:
        print(f"      Error in get_weather_nws for {name}: {e}")
        return {"location": name, "icon": "?", "temp": "N/A", "humidity": ""}

data['weather'] = [
    get_weather_nws(39.7392, -104.9903, "Denver, CO"),
    get_weather_nws(37.8117, -107.6644, "Silverton, CO"),
    get_weather_nws(40.7608, -111.8910, "Salt Lake City, UT"),
    get_weather_nws(40.6461, -111.4980, "Park City, UT")
]
print(f"   Weather fetched for {len(data['weather'])} locations using NWS.")

# ============================================
# 2. EMAIL
# ============================================
print("📧 Fetching email...")
total_unread_raw = sh('gog gmail search "in:inbox is:unread" --max 100 --json 2>/dev/null')
try:
    total_data = json.loads(total_unread_raw)
    unread_count = len(total_data.get('threads') or [])
except:
    unread_count = 0
important_raw = sh('gog gmail search "in:inbox is:unread -from:noreply -from:no-reply -from:notifications -from:notify -from:mailer -from:donotreply" --max 10 --json 2>/dev/null')
important_emails = []
try:
    imp_data = json.loads(important_raw)
    for t in (imp_data.get('threads') or [])[:5]:
        sender = t.get('from', 'Unknown').split('<')[0].strip().strip('"')
        important_emails.append({
            "from": sender[:30], "subject": t.get('subject', 'No subject')[:60], "date": t.get('date', '')
        })
except: pass
data['emails'] = {"unreadCount": unread_count, "important": important_emails}
print(f"   📬 {unread_count} unread total, {len(important_emails)} potentially important")

# ============================================
# 3. CALENDAR
# ============================================
print("📅 Fetching calendar...")
now_utc = datetime.now(timezone.utc)
mst_offset = timezone(timedelta(hours=-6))
now_mst = now_utc.astimezone(mst_offset)
today_mst = now_mst.strftime('%Y-%m-%d')
from_date = f"{today_mst}T00:00:00-06:00"
to_date = (now_mst + timedelta(days=8)).strftime('%Y-%m-%dT23:59:59-06:00')
cal_raw = sh(f'gog calendar events primary --from {from_date} --to {to_date} --json 2>/dev/null')
data['calendar'] = []
try:
    cal_data = json.loads(cal_raw)
    month_map = {'01':'JAN','02':'FEB','03':'MAR','04':'APR','05':'MAY','06':'JUN','07':'JUL','08':'AUG','09':'SEP','10':'OCT','11':'NOV','12':'DEC'}
    for e in (cal_data.get('events') or [])[:10]:
        start = e.get('start', {})
        dt = start.get('dateTime') or start.get('date', '')
        parts = dt.split('T')[0].split('-')
        data['calendar'].append({
            "day": parts[2].lstrip('0') if len(parts) > 2 else "?",
            "month": month_map.get(parts[1], "???") if len(parts) > 1 else "???",
            "title": e.get('summary', 'Untitled'),
            "time": dt.split('T')[1][:5] if 'T' in dt else 'All day'
        })
except: pass
print(f"   Found {len(data.get('calendar', []))} events")

# ============================================
# 4. AVALANCHE DANGER
# ============================================
print("⚠️ Fetching avy danger ratings...")
avy_data = {}
try:
    avy_api = curl_json("https://api.avalanche.org/v2/public/products/map-layer", timeout=20)
    if not avy_api: raise Exception("Failed to fetch avy data")
    
    danger_map = {-1:("No Rating","no-rating"), 0:("No Rating","no-rating"), 1:("Low","low"), 2:("Moderate","moderate"), 3:("Considerable","considerable"), 4:("High","high"), 5:("Extreme","extreme")}
    zones_by_center = {}
    caic_features = [f for f in avy_api.get('features', []) if f.get('properties', {}).get('center_id') == 'CAIC']
    for f in avy_api.get('features', []):
        props = f.get('properties', {})
        center = props.get('center_id')
        if center != 'CAIC' and center:
            if center not in zones_by_center: zones_by_center[center] = {}
            rating, r_class = danger_map.get(props.get('danger_level', 0), ("No Rating", "no-rating"))
            zones_by_center[center][props.get('name')] = {"zone": props.get('name'), "rating": rating, "ratingClass": r_class, "danger_level": props.get('danger_level', 0)}

    def point_in_polygon(x, y, polygon):
        n, inside = len(polygon), False
        p1x, p1y = polygon[0]
        for i in range(1, n + 1):
            p2x, p2y = polygon[i % n]
            if y > min(p1y, p2y) and y <= max(p1y, p2y) and x <= max(p1x, p2x):
                if p1y != p2y: xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                if p1x == p2x or x <= xinters: inside = not inside
            p1x, p1y = p2x, p2y
        return inside
    
    caic_zones = {"Front Range":(39.8,-105.7), "Vail & Summit County":(39.55,-106.2), "Aspen":(39.1576,-106.8201), "Gunnison":(38.7,-106.9), "Grand Mesa":(39.02,-108.2), "Sawatch":(39.0,-106.5), "Northern San Juan":(37.9,-107.7), "Southern San Juan":(37.4,-106.6), "Steamboat & Flat Tops":(40.45,-106.8)}
    colorado = []
    for z_name, (lat, lon) in caic_zones.items():
        rating, r_class, danger_level = "No Rating", "no-rating", 0
        for f in caic_features:
            geom = f.get('geometry', {})
            polygons = [geom['coordinates'][0]] if geom.get('type') == 'Polygon' else [p[0] for p in geom.get('coordinates', [])]
            for poly in polygons:
                if point_in_polygon(lon, lat, poly):
                    danger_level = f.get('properties', {}).get('danger_level', 0)
                    rating, r_class = danger_map.get(danger_level, ("No Rating", "no-rating"))
                    break
            if rating != "No Rating": break
        colorado.append({"zone": z_name, "rating": rating, "ratingClass": r_class, "danger_level": danger_level})

    uac = zones_by_center.get('UAC', {})
    utah = [uac.get(z, {"zone":z, "rating":"No Rating", "ratingClass":"no-rating", "danger_level":0}) for z in ["Salt Lake","Ogden","Provo","Uintas","Skyline","Logan","Moab","Abajos"]]
    sac, esac = zones_by_center.get('SAC', {}), zones_by_center.get('ESAC', {})
    tahoe = sac.get("Central Sierra Nevada", {"zone":"Tahoe", "rating":"No Rating", "ratingClass":"no-rating", "danger_level":0}); tahoe["zone"] = "Tahoe"
    e_sierra = esac.get("Eastside Region", {"zone":"Eastern Sierra", "rating":"No Rating", "ratingClass":"no-rating", "danger_level":0}); e_sierra["zone"] = "Eastern Sierra"
    california = [tahoe, e_sierra, {"zone":"Shasta", "rating":"Low", "ratingClass":"low", "danger_level":1}]
    avy_data = {"colorado": colorado, "utah": utah, "california": california}
    data['avyDanger'] = avy_data
    print(f"   CO: {len(colorado)} zones, Utah: {len(utah)} zones, CA: {len(california)} zones")
except Exception as e:
    print(f"   Avy data error: {e}")

# ============================================
# 5. SNOW FORECASTS (NWS) + STORM WATCH
# ============================================
print("🏔️ Fetching snow forecasts from NWS...")
RESORTS = {"Arapahoe Basin":(39.6324,-105.871,"CO"), "Copper Mountain":(39.4817,-106.15,"CO"), "Winter Park":(39.8864,-105.7625,"CO"), "Steamboat":(40.4537,-106.7587,"CO"), "Brighton":(40.5981,-111.5831,"UT"), "Alta":(40.5784,-111.6328,"UT")}

def get_nws_snow_detailed(lat, lon):
    try:
        points_data = curl_json(f"https://api.weather.gov/points/{lat},{lon}")
        if not points_data: return {}
        grid_data = curl_json(points_data['properties']['forecastGridData'])
        if not grid_data: return {}
        snow_values = grid_data['properties'].get('snowfallAmount', {}).get('values', [])
        daily_snow = {}
        for sv in snow_values:
            dt = datetime.fromisoformat(sv['validTime'].split('/')[0].replace('Z', '+00:00'))
            day_key = dt.strftime('%a')
            inches = (sv['value'] or 0) / 25.4
            if day_key not in daily_snow: daily_snow[day_key] = 0
            daily_snow[day_key] += inches
        return daily_snow
    except: return {}

snow_data, co_totals, ut_totals = [], {}, {}
for resort, (lat, lon, state) in RESORTS.items():
    daily = get_nws_snow_detailed(lat, lon)
    for day, inches in daily.items():
        totals = co_totals if state == "CO" else ut_totals
        totals[day] = max(totals.get(day, 0), inches)
    snow_days = [f"{day}: {round(inches)}\"" for day, inches in daily.items() if inches >= 0.5 and round(inches) > 0]
    forecast = ' | '.join(snow_days[:4]) if snow_days else 'Dry'
    snow_data.append({"resort": resort, "snow24": 0, "snow48": 0, "forecast": forecast})
    print(f"   {resort}: {forecast}")
data['snow'] = snow_data

# ============================================
# 6. STORM WATCH (Generated from NWS data)
# ============================================
print("🌨️ Generating storm watch...")
def format_storm_forecast(totals, region):
    snow_days = [(day, inches) for day, inches in totals.items() if inches >= 1]
    if not snow_days: return "Dry conditions expected. No significant snow in the forecast."
    parts = [f"{day}: {round(inches)}\"" for day, inches in snow_days]
    total = sum(inches for _, inches in snow_days)
    return f"{' → '.join(parts)}. ~{round(total)}\" total over the period."
data['stormWatch'] = [{"region":"Colorado", "forecast":format_storm_forecast(co_totals,"CO")}, {"region":"Utah", "forecast":format_storm_forecast(ut_totals,"UT")}]
print(f"   Generated forecasts for 2 regions")

# ============================================
# 7. SPECIAL ADVISORIES (NWS Alerts)
# ============================================
print("🚨 Checking NWS advisories...")
def get_nws_alerts(state):
    try:
        alerts_data = curl_json(f"https://api.weather.gov/alerts/active?area={state}")
        if not alerts_data: return []
        winter_alerts = []
        keywords = ['winter', 'snow', 'blizzard', 'avalanche', 'ice', 'freeze', 'frost', 'wind chill']
        for feature in alerts_data.get('features', []):
            props = feature.get('properties', {})
            event, headline = props.get('event',''), props.get('headline','')
            if any(kw in event.lower() or kw in headline.lower() for kw in keywords):
                winter_alerts.append({"type": event, "headline": headline[:100] + ("..." if len(headline) > 100 else ""), "severity": props.get('severity', 'Unknown')})
        return winter_alerts[:3]
    except: return []
advisories = []
for state in ['CO', 'UT', 'CA']: advisories.extend(get_nws_alerts(state))
data['specialAdvisories'] = advisories[:5]
print(f"   Found {len(advisories)} winter advisories")

# ============================================
# 8. SOCIAL WORTHY
# ============================================
print("📢 Generating social worthy content ideas...")
social_worthy = []
high_danger_zones = [z['zone'] for s in avy_data.values() for z in s if z.get('danger_level',0) >= 3]
if high_danger_zones:
    social_worthy.append({"icon":"⚠️", "text":f"Elevated avy danger ({', '.join(high_danger_zones[:2])}) - safety content opportunity"})
co_big_days = [(d, round(i)) for d, i in co_totals.items() if i >= 6]
ut_big_days = [(d, round(i)) for d, i in ut_totals.items() if i >= 6]
if co_big_days or ut_big_days:
    parts = []
    if ut_big_days: parts.append(f"Utah: {', '.join([f'{d} {i}\"' for d,i in ut_big_days[:2]])}")
    if co_big_days: parts.append(f"Colorado: {', '.join([f'{d} {i}\"' for d,i in co_big_days[:2]])}")
    social_worthy.append({"icon":"🌨️", "text":f"Storm incoming - {' | '.join(parts)} - powder alert content"})
if not social_worthy or (not co_big_days and not ut_big_days):
     social_worthy.append({"icon":"☀️", "text":"Dry spell continues - good time for gear/prep content or throwback posts"})
if len(social_worthy) < 3: social_worthy.append({"icon":"📚", "text":"Educational content: avy awareness, gear tips, or trip planning"})
if len(social_worthy) < 4: social_worthy.append({"icon":"💬", "text":"Engagement post: ask followers about weekend plans or favorite zones"})
data['socialWorthy'] = social_worthy[:4]
print(f"   Generated {len(social_worthy)} content ideas")

# ============================================
# 9. DAILY DIGEST (SNOTEL 24hr for favorites)
# ============================================
print("📊 Fetching daily digest (SNOTEL 24hr)...")
FAVORITES = [("Winter Park","335","CO"), ("Steamboat","825","CO"), ("Snowbird","766","UT"), ("Brighton","366","UT"), ("Copper Mountain","415","CO")]

def get_snotel_24hr(station_id, state):
    print(f"      Fetching SNOTEL for station {station_id}:{state}...")
    try:
        url = f"https://wcc.sc.egov.usda.gov/reportGenerator/view_csv/customSingleStationReport/daily/{station_id}:{state}:SNTL%7Cid%3D%22%22%7Cname/-3,0/WTEQ::value,TOBS::value"
        cmd = ['curl', '-s', '-L', '--max-time', '20', '-A', 'TSL-CommandCenter/1.0', url]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        if result.returncode != 0: 
            print(f"      SNOTEL request failed for {station_id} with exit code {result.returncode}")
            return 0, "⚪ N/A"
        content = result.stdout
        lines = [l for l in content.strip().split('\n') if l and not l.startswith('#')]
        if len(lines) < 3: 
            print(f"      SNOTEL data format unexpected for {station_id}")
            return 0, "⚪ N/A"
        rows = lines[-2:]
        data_rows = []
        for row in rows:
            parts = row.split(',')
            if len(parts) >= 3:
                try:
                    data_rows.append((float(parts[1]), float(parts[2])))
                except ValueError:
                    print(f"      SNOTEL could not parse row: {row}")
                    pass
        if len(data_rows) < 2: 
            print(f"      Not enough data rows for {station_id}")
            return 0, "⚪ N/A"
        
        swe_change = data_rows[1][0] - data_rows[0][0]
        if swe_change <= 0: return 0, f"🟢 0\""
        
        avg_temp_c = ((data_rows[0][1] + data_rows[1][1]) / 2 - 32) * 5/9
        if avg_temp_c > 2: return 0, f"🟢 0\"" # Too warm for snow
        
        # H&P Formula
        density = 67.92 + 51.25 * math.exp(avg_temp_c / 2.59)
        snowfall = (1000 / density) * swe_change
        
        return round(snowfall), f"🟢 {round(snowfall)}\""
        
    except subprocess.TimeoutExpired:
        print(f"      SNOTEL request timed out for {station_id}")
        return 0, "⚪ Timeout"
    except Exception as e:
        print(f"      SNOTEL processing error for {station_id}: {e}")
        return 0, "⚪ Error"

daily_digest = []
for resort, station, state in FAVORITES:
    snow, status = get_snotel_24hr(station, state)
    daily_digest.append({"resort": resort, "status": status, "match": True})
    print(f"   {resort}: {status}")
data['dailyDigest'] = daily_digest

# ============================================
# RESTORE & FINALIZE
# ============================================
data['tasks'] = preserved_tasks
data['reminders'] = preserved_reminders
riddles = [{"q": "I fall from the sky but I'm not rain...", "a": "Snow ❄️"}, {"q": "I go up but never come down...", "a": "Your age 🎂"}, {"q": "What has hands but can't clap?", "a": "A clock ⏰"}]
day_of_year = datetime.now(timezone.utc).timetuple().tm_yday
data['dailyRiddle'] = riddles[day_of_year % len(riddles)]
mst_time = subprocess.run(['date', '+%b %d, %Y at %I:%M %p %Z'], env={'TZ': 'America/Denver'}, capture_output=True, text=True).stdout.strip()
data['lastUpdated'] = mst_time

with open('data_inject.json', 'w') as f:
    json.dump(data, f, indent=2)
print("✅ Data updated")
PYEOF

# Inject into HTML
python3 -u << 'PYEOF'
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
