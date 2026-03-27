import json
import urllib.request

DANGER_MAP = {
    -1: ("No Rating", "no-rating"),
    0: ("No Rating", "no-rating"),
    1: ("Low", "low"),
    2: ("Moderate", "moderate"),
    3: ("Considerable", "considerable"),
    4: ("High", "high"),
    5: ("Extreme", "extreme")
}

def fetch_avy_data():
    try:
        url = "https://api.avalanche.org/v2/public/products/map-layer"
        req = urllib.request.Request(url, headers={'User-Agent': 'CommandCenter/1.0'})
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.loads(response.read())
        
        zones_by_center = {}
        for feature in data.get('features', []):
            props = feature.get('properties', {})
            name = props.get('name', '')
            danger = props.get('danger_level', 0)
            center = props.get('center_id', '')
            rating, rating_class = DANGER_MAP.get(danger, ("No Rating", "no-rating"))
            
            if center not in zones_by_center:
                zones_by_center[center] = {}
            zones_by_center[center][name] = {"zone": name, "rating": rating, "ratingClass": rating_class}
        
        # Utah (UAC) - direct mapping
        uac = zones_by_center.get('UAC', {})
        utah = [
            uac.get("Salt Lake", {"zone": "Salt Lake", "rating": "No Rating", "ratingClass": "no-rating"}),
            uac.get("Ogden", {"zone": "Ogden", "rating": "No Rating", "ratingClass": "no-rating"}),
            uac.get("Provo", {"zone": "Provo", "rating": "No Rating", "ratingClass": "no-rating"}),
            uac.get("Uintas", {"zone": "Uintas", "rating": "No Rating", "ratingClass": "no-rating"}),
            uac.get("Skyline", {"zone": "Skyline", "rating": "No Rating", "ratingClass": "no-rating"}),
            uac.get("Logan", {"zone": "Logan", "rating": "No Rating", "ratingClass": "no-rating"}),
            uac.get("Moab", {"zone": "Moab", "rating": "No Rating", "ratingClass": "no-rating"}),
            uac.get("Abajos", {"zone": "Abajos", "rating": "No Rating", "ratingClass": "no-rating"}),
        ]
        
        # California (SAC + ESAC)
        sac = zones_by_center.get('SAC', {})
        esac = zones_by_center.get('ESAC', {})
        tahoe_data = sac.get("Central Sierra Nevada", {"zone": "Tahoe", "rating": "No Rating", "ratingClass": "no-rating"})
        tahoe_data["zone"] = "Tahoe"
        east_sierra = esac.get("Eastside Region", {"zone": "Eastern Sierra", "rating": "No Rating", "ratingClass": "no-rating"})
        east_sierra["zone"] = "Eastern Sierra"
        
        # Shasta (MSAC)
        msac = zones_by_center.get('MSAC', {})
        shasta = {"zone": "Shasta", "rating": "Low", "ratingClass": "low"}  # Default, MSAC might have different name
        for name, zdata in msac.items():
            if "shasta" in name.lower():
                shasta = zdata
                shasta["zone"] = "Shasta"
                break
        
        california = [tahoe_data, east_sierra, shasta]
        
        # Colorado (CAIC) - zones not individually named in API, using geometry would be complex
        # For now, set all to Moderate as baseline (will be manually updated or enhanced later)
        colorado = [
            {"zone": "Front Range", "rating": "No Rating", "ratingClass": "no-rating"},
            {"zone": "Vail & Summit County", "rating": "Moderate", "ratingClass": "moderate"},
            {"zone": "Sawatch", "rating": "Moderate", "ratingClass": "moderate"},
            {"zone": "Aspen", "rating": "Moderate", "ratingClass": "moderate"},
            {"zone": "Gunnison", "rating": "Low", "ratingClass": "low"},
            {"zone": "Grand Mesa", "rating": "Low", "ratingClass": "low"},
            {"zone": "North San Juan", "rating": "Moderate", "ratingClass": "moderate"},
            {"zone": "South San Juan", "rating": "Moderate", "ratingClass": "moderate"},
        ]
        
        return {
            "colorado": colorado,
            "utah": utah,
            "california": california
        }
    except Exception as e:
        print(f"Error fetching avy data: {e}")
        return None

if __name__ == "__main__":
    data = fetch_avy_data()
    if data:
        for state, zones in data.items():
            print(f"\n{state.upper()}:")
            for z in zones:
                print(f"  {z['zone']}: {z['rating']}")
