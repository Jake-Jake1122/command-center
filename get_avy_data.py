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

def point_in_polygon(lat, lon, polygon):
    """Ray casting algorithm for point-in-polygon test."""
    # Handle both Polygon and MultiPolygon
    if not polygon:
        return False
    
    # Flatten to list of rings (outer boundaries)
    rings = []
    if isinstance(polygon[0][0], (int, float)):
        # Simple polygon: [[lon, lat], ...]
        rings = [polygon]
    elif isinstance(polygon[0][0], list):
        if isinstance(polygon[0][0][0], (int, float)):
            # Polygon with holes: [[[lon, lat], ...], ...]
            rings = [polygon[0]]  # Just use outer ring
        else:
            # MultiPolygon: [[[[lon, lat], ...], ...], ...]
            for poly in polygon:
                if poly and poly[0]:
                    rings.append(poly[0])  # Outer ring of each polygon
    
    for ring in rings:
        n = len(ring)
        inside = False
        
        j = n - 1
        for i in range(n):
            xi, yi = ring[i][0], ring[i][1]  # lon, lat
            xj, yj = ring[j][0], ring[j][1]
            
            if ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi):
                inside = not inside
            j = i
        
        if inside:
            return True
    
    return False

def fetch_avy_data():
    try:
        url = "https://api.avalanche.org/v2/public/products/map-layer"
        req = urllib.request.Request(url, headers={'User-Agent': 'CommandCenter/1.0'})
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.loads(response.read())
        
        zones_by_center = {}
        caic_features = []
        
        for feature in data.get('features', []):
            props = feature.get('properties', {})
            name = props.get('name', '')
            danger = props.get('danger_level', 0)
            center = props.get('center_id', '')
            rating, rating_class = DANGER_MAP.get(danger, ("No Rating", "no-rating"))
            
            if center == 'CAIC':
                # Store CAIC features for polygon matching
                caic_features.append({
                    'geometry': feature.get('geometry', {}),
                    'danger': danger,
                    'rating': rating,
                    'rating_class': rating_class
                })
            else:
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
        shasta = {"zone": "Shasta", "rating": "Low", "ratingClass": "low"}
        for name, zdata in msac.items():
            if "shasta" in name.lower():
                shasta = zdata
                shasta["zone"] = "Shasta"
                break
        
        california = [tahoe_data, east_sierra, shasta]
        
        # Colorado (CAIC) - polygon matching using zone coordinates
        colorado = []
        for zone_name, (lat, lon) in CO_ZONES.items():
            zone_rating = {"zone": zone_name, "rating": "No Rating", "ratingClass": "no-rating"}
            
            # Find which CAIC polygon contains this point
            for feature in caic_features:
                geom = feature['geometry']
                geom_type = geom.get('type', '')
                coords = geom.get('coordinates', [])
                
                if geom_type == 'Polygon':
                    if point_in_polygon(lat, lon, coords):
                        zone_rating = {
                            "zone": zone_name,
                            "rating": feature['rating'],
                            "ratingClass": feature['rating_class']
                        }
                        break
                elif geom_type == 'MultiPolygon':
                    found = False
                    for poly in coords:
                        if point_in_polygon(lat, lon, poly):
                            zone_rating = {
                                "zone": zone_name,
                                "rating": feature['rating'],
                                "ratingClass": feature['rating_class']
                            }
                            found = True
                            break
                    if found:
                        break
            
            colorado.append(zone_rating)
        
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
