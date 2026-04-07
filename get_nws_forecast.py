
import json
import requests
import sys
from datetime import datetime, timedelta

# Colorado zone coordinates from SNOTEL_backcountry_master.csv
CO_ZONES = {
    "Front Range": (39.8, -105.7),
    "Vail & Summit County": (39.55, -106.2),
    "Sawatch": (39.0, -106.5),
    "Aspen": (39.1576, -106.8201),
    "Gunnison": (38.7, -106.9),
    "Grand Mesa": (39.02, -108.2),
    "North San Juan": (37.9, -107.7),
    "South San Juan": (37.4, -106.6),
}

from datetime import datetime, timedelta, timezone

def get_nws_forecast():
    storm_watch = ""
    for zone, (lat, lon) in CO_ZONES.items():
        try:
            # Get gridpoint URL
            points_url = f"https://api.weather.gov/points/{lat},{lon}"
            headers = {'User-Agent': 'TheSnowLine/1.0'}
            points_res = requests.get(points_url, headers=headers, timeout=10)
            points_res.raise_for_status()
            grid_url = points_res.json()['properties']['forecastGridData']

            # Get gridpoint data
            grid_res = requests.get(grid_url, headers=headers, timeout=15)
            grid_res.raise_for_status()
            grid_data = grid_res.json()

            # Check for significant snowfall or weather
            snowfall = grid_data['properties'].get('snowfallAmount', {}).get('values', [])
            weather = grid_data['properties'].get('weather', {}).get('values', [])

            total_snow = 0
            storm_summary = ""
            today = datetime.now(timezone.utc).date()
            tomorrow = today + timedelta(days=1)

            for s in snowfall:
                valid_time_str = s['validTime'].split('/')[0]
                value_time = datetime.fromisoformat(valid_time_str.replace('Z', '+00:00')).date()
                if value_time == today or value_time == tomorrow:
                    # NWS snowfall is in millimeters, convert to inches
                    total_snow += s['value'] * 0.0393701 if s['value'] else 0
            
            if total_snow > 1: # If more than an inch of snow is expected
                storm_summary += f"{zone}: Expecting {round(total_snow)} inches of snow in the next 48 hours. "

            if not storm_summary:
                for w in weather:
                    valid_time_str = w['validTime'].split('/')[0]
                    value_time = datetime.fromisoformat(valid_time_str.replace('Z', '+00:00')).date()
                    if (value_time == today or value_time == tomorrow) and w['value']:
                        for condition in w['value']:
                            current_weather = condition.get('weather')
                            if current_weather and ("snow" in current_weather.lower() or "storm" in current_weather.lower()):
                                coverage = condition.get('coverage', '')
                                intensity = condition.get('intensity', '')
                                weather_str = f"{coverage} {intensity} {current_weather}".strip()
                                storm_summary += f"{zone}: {weather_str} expected. "
                                break # just need one mention
                    if storm_summary:
                        break
            
            if storm_summary:
                storm_watch += storm_summary

        except requests.exceptions.RequestException as e:
            print(f"Error fetching NWS data for {zone}: {e}", file=sys.stderr)
            continue

    if not storm_watch:
        return "Dry pattern continues across Colorado."
    
    return storm_watch

if __name__ == "__main__":
    print(get_nws_forecast())
