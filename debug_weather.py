
import json
import urllib.request

def get_weather_openmeteo(lat, lon, name, retries=3):
    icons = {0: '☀️', 1: '🌤️', 2: '⛅', 3: '☁️', 45: '🌫️', 48: '🌫️',
             51: '🌧️', 53: '🌧️', 55: '🌧️', 61: '🌧️', 63: '🌧️', 65: '🌧️',
             71: '🌨️', 73: '🌨️', 75: '🌨️', 77: '🌨️', 80: '🌧️', 81: '🌧️',
             82: '🌧️', 85: '🌨️', 86: '🌨️', 95: '⛈️', 96: '⛈️', 99: '⛈️'}
    for attempt in range(retries):
        try:
            print(f"Fetching weather for {name}...")
            url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,relative_humidity_2m,weather_code&temperature_unit=fahrenheit"
            req = urllib.request.Request(url, headers={'User-Agent': 'TSL-CommandCenter/1.0'})
            with urllib.request.urlopen(req, timeout=15) as response:
                api_data = json.loads(response.read())
                current = api_data.get('current', {})
                temp = current.get('temperature_2m', '?')
                humidity = current.get('relative_humidity_2m', '?')
                code = current.get('weather_code', 0)
                print(f"Success for {name}")
                return {"location": name, "icon": icons.get(code, '🌡️'), "temp": f"{temp}°F", "humidity": f"H:{humidity}%"}
        except Exception as e:
            print(f"Attempt {attempt + 1} failed for {name}: {e}")
            if attempt < retries - 1:
                import time
                time.sleep(1)
                continue
    return {"location": name, "icon": "?", "temp": "N/A", "humidity": ""}

weather_data = [
    get_weather_openmeteo(39.7392, -104.9903, "Denver, CO"),
    get_weather_openmeteo(37.8117, -107.6644, "Silverton, CO"),
    get_weather_openmeteo(40.7608, -111.8910, "Salt Lake City, UT"),
    get_weather_openmeteo(40.6461, -111.4980, "Park City, UT")
]

print(json.dumps(weather_data, indent=2))
