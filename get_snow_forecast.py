import json
import urllib.request
from datetime import datetime, timedelta

RESORTS = {
    "Arapahoe Basin": (39.6324, -105.871),
    "Copper Mountain": (39.4817, -106.15),
    "Winter Park": (39.8864, -105.7625),
    "Steamboat": (40.4537, -106.7587),
    "Brighton": (40.5981, -111.5831),
    "Alta": (40.5784, -111.6328)
}

def get_nws_snow_forecast(lat, lon):
    """Get 7-day snow forecast from NWS, return only days with snow"""
    try:
        # Get grid point
        points_url = f"https://api.weather.gov/points/{lat},{lon}"
        req = urllib.request.Request(points_url, headers={'User-Agent': 'CommandCenter/1.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            points_data = json.loads(response.read())
        
        grid_url = points_data['properties']['forecastGridData']
        
        # Get gridded forecast
        req = urllib.request.Request(grid_url, headers={'User-Agent': 'CommandCenter/1.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            grid_data = json.loads(response.read())
        
        # Parse snowfall amounts
        snow_values = grid_data['properties'].get('snowfallAmount', {}).get('values', [])
        
        # Group by day and sum
        daily_snow = {}
        for sv in snow_values:
            time_str = sv['validTime'].split('/')[0]
            dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
            day_key = dt.strftime('%a')  # Mon, Tue, etc.
            date_key = dt.strftime('%m/%d')
            mm = sv['value'] or 0
            inches = mm / 25.4
            
            key = f"{day_key}"
            if key not in daily_snow:
                daily_snow[key] = {'inches': 0, 'date': date_key}
            daily_snow[key]['inches'] += inches
        
        # Filter to days with snow > 0.5", round to nearest inch
        snow_days = []
        for day, data in daily_snow.items():
            if data['inches'] >= 0.5:
                rounded = round(data['inches'])
                if rounded > 0:
                    snow_days.append(f"{day}: {rounded}\"")
        
        if snow_days:
            return ' | '.join(snow_days[:4])  # Limit to 4 entries
        else:
            return 'Dry'
            
    except Exception as e:
        return 'N/A'

def get_all_forecasts():
    results = []
    for resort, (lat, lon) in RESORTS.items():
        forecast = get_nws_snow_forecast(lat, lon)
        results.append({
            "resort": resort,
            "snow24": 0,
            "snow48": 0,
            "forecast": forecast
        })
        print(f"{resort}: {forecast}")
    return results

if __name__ == "__main__":
    forecasts = get_all_forecasts()
    print(json.dumps(forecasts))
