from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
import math
from datetime import datetime
from boto3.dynamodb.conditions import Key

from app.core.database import get_table

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class ZoneDefinition(BaseModel):
    """A named geofence zone the student marks during onboarding."""
    zone_name: str              # "home"|"campus"|"library"|"hostel"|custom
    label: str                  # Human-readable: "My Hostel", "Main Campus"
    latitude: float
    longitude: float
    radius_meters: int = 200    # Default 200m radius geofence

class OnboardingRequest(BaseModel):
    """Student marks all their locations during onboarding."""
    user_id: str
    zones: List[ZoneDefinition]

class LocationUpdateRequest(BaseModel):
    """
    Flutter app fires this when the student enters or exits a geofence zone.
    On Android: uses Geofencing API → fires a BroadcastReceiver → POSTs here.
    No continuous GPS drain — only triggers on zone transitions.
    """
    user_id: str
    zone_name: str              # Which zone was entered/exited
    transition: str             # "enter"|"exit"
    latitude: Optional[float] = None
    longitude: Optional[float] = None

class CoarseLocationRequest(BaseModel):
    """
    For manual zone detection from coarse GPS.
    Flutter app sends current lat/lng, backend finds which zone they're in.
    """
    user_id: str
    latitude: float
    longitude: float

class ReminderAdjustmentRequest(BaseModel):
    """
    Calculate how early a reminder should fire based on current location.
    E.g. 'leave for class' fires 45 min early if at home, 15 min if on campus.
    """
    user_id: str
    destination_zone: str       # Where the student needs to be (e.g. "campus")
    event_time: str             # HH:MM — when the event starts


# ── Routes ────────────────────────────────────────────────────────────────────

# ── Onboarding: Save Zones ───────────────────────────────────────────────────

@router.post("/onboard-zones")
async def save_onboarding_zones(req: OnboardingRequest):
    """
    Student marks 3-4 locations during first-time setup:
    - Home (hostel / PG / house)
    - Main Campus
    - Library
    - Any other frequent spots

    Each zone is a 200m radius circle. The Flutter app uses Android Geofencing
    API to monitor these zones — no continuous GPS, no battery drain.

    This is called ONCE during onboarding.
    """
    table = get_table("locations")
    now = datetime.now().isoformat()
    saved = []

    for zone in req.zones:
        location_id = f"zone_{zone.zone_name}_{uuid.uuid4().hex[:6]}"
        item = {
            "user_id": req.user_id,
            "location_id": location_id,
            "type": "zone",
            "zone_name": zone.zone_name,
            "label": zone.label,
            "latitude": str(zone.latitude),     # DynamoDB doesn't support float
            "longitude": str(zone.longitude),
            "radius_meters": zone.radius_meters,
            "created_at": now,
        }
        table.put_item(Item=item)
        saved.append(item)

    # Also create a 'current_context' entry to track live zone
    context_item = {
        "user_id": req.user_id,
        "location_id": "current_context",
        "type": "current",
        "current_zone": "unknown",
        "last_transition": "none",
        "updated_at": now,
    }
    table.put_item(Item=context_item)

    return {
        "zones_saved": len(saved),
        "zones": saved,
        "message": "Location zones saved. Enable geofencing on the Flutter app.",
    }


# ── Zone Transition: Enter/Exit ──────────────────────────────────────────────

@router.post("/zone-transition")
async def update_zone_transition(req: LocationUpdateRequest):
    """
    Called by Flutter when Android Geofencing API fires a transition event.

    How it works on Android:
    1. GeofencingClient.addGeofences() registers the circles
    2. When student walks into/out of a zone → BroadcastReceiver fires
    3. Flutter plugin captures this → POSTs to this endpoint
    4. Backend updates 'current_location_context' → used by reminders

    This means:
    - No continuous GPS polling
    - No battery drain
    - Only fires on actual zone transitions
    - Works even when app is in background
    """
    table = get_table("locations")
    now = datetime.now().isoformat()

    if req.transition == "enter":
        new_zone = req.zone_name
    elif req.transition == "exit":
        new_zone = "transit"    # Between zones
    else:
        raise HTTPException(status_code=400, detail="transition must be 'enter' or 'exit'")

    # Update current context
    table.update_item(
        Key={"user_id": req.user_id, "location_id": "current_context"},
        UpdateExpression="SET current_zone = :z, last_transition = :t, updated_at = :u, last_lat = :lat, last_lng = :lng",
        ExpressionAttributeValues={
            ":z": new_zone,
            ":t": req.transition,
            ":u": now,
            ":lat": str(req.latitude) if req.latitude else "0",
            ":lng": str(req.longitude) if req.longitude else "0",
        },
    )

    # Log the transition for analytics
    log_id = f"transition_{uuid.uuid4().hex[:8]}"
    table.put_item(Item={
        "user_id": req.user_id,
        "location_id": log_id,
        "type": "transition_log",
        "zone_name": req.zone_name,
        "transition": req.transition,
        "timestamp": now,
    })

    return {
        "current_zone": new_zone,
        "transition": req.transition,
        "updated_at": now,
    }


# ── Get Current Zone ─────────────────────────────────────────────────────────

@router.get("/current-zone/{user_id}")
async def get_current_zone(user_id: str):
    """
    Returns which zone the student is currently in.
    Used by reminders to adjust timing.
    """
    table = get_table("locations")

    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    items = response.get("Items", [])

    current = next(
        (i for i in items if i.get("location_id") == "current_context"),
        None
    )
    if not current:
        return {"current_zone": "unknown", "message": "Location not set up yet"}

    # Get zone details
    zones = [i for i in items if i.get("type") == "zone"]

    return {
        "current_zone": current.get("current_zone", "unknown"),
        "last_transition": current.get("last_transition"),
        "updated_at": current.get("updated_at"),
        "saved_zones": [
            {"zone_name": z.get("zone_name"), "label": z.get("label")}
            for z in zones
        ],
    }


# ── Detect Zone from Coarse GPS ──────────────────────────────────────────────

@router.post("/detect-zone")
async def detect_zone_from_gps(req: CoarseLocationRequest):
    """
    Takes a coarse GPS reading and determines which saved zone the student
    is closest to (if within radius).

    Use this as a fallback when geofencing hasn't fired (e.g. app just opened).
    Also auto-updates the current_context.
    """
    table = get_table("locations")
    now = datetime.now().isoformat()

    response = table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    zones = [i for i in response.get("Items", []) if i.get("type") == "zone"]

    if not zones:
        return {"detected_zone": "unknown", "message": "No zones configured"}

    # Find which zone the student is inside (or closest to)
    detected = None
    min_distance = float("inf")

    for zone in zones:
        zone_lat = float(zone.get("latitude", 0))
        zone_lng = float(zone.get("longitude", 0))
        radius = int(zone.get("radius_meters", 200))

        distance = _haversine_meters(req.latitude, req.longitude, zone_lat, zone_lng)

        if distance <= radius and distance < min_distance:
            detected = zone
            min_distance = distance

    detected_zone = detected.get("zone_name", "unknown") if detected else "transit"

    # Auto-update current context
    table.update_item(
        Key={"user_id": req.user_id, "location_id": "current_context"},
        UpdateExpression="SET current_zone = :z, last_transition = :t, updated_at = :u, last_lat = :lat, last_lng = :lng",
        ExpressionAttributeValues={
            ":z": detected_zone,
            ":t": "gps_detect",
            ":u": now,
            ":lat": str(req.latitude),
            ":lng": str(req.longitude),
        },
    )

    return {
        "detected_zone": detected_zone,
        "zone_label": detected.get("label") if detected else "In transit",
        "distance_meters": round(min_distance) if detected else None,
        "within_radius": detected is not None,
    }


# ── Adjusted Reminder Time Based on Location ─────────────────────────────────

@router.post("/adjusted-reminder-time")
async def get_adjusted_reminder_time(req: ReminderAdjustmentRequest):
    """
    The key feature: adjusts reminder timing based on WHERE the student is.

    Example:
    - Event: Physics class at 10:00 AM on campus
    - Student is AT HOME → fire "leave now" at 9:15 AM (45 min travel)
    - Student is AT CAMPUS → fire "class in 15 min" at 9:45 AM
    - Student is AT LIBRARY → fire "head to class" at 9:50 AM (10 min walk)

    Travel time estimates between zones:
    - home ↔ campus: 30-45 min
    - hostel ↔ campus: 15-20 min
    - library ↔ campus: 5-10 min
    - campus ↔ campus: 5 min (walking between buildings)

    The Flutter app uses this to schedule flutter_local_notifications
    with the correct timing.
    """
    table = get_table("locations")

    # Get current zone
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    items = response.get("Items", [])

    current = next(
        (i for i in items if i.get("location_id") == "current_context"),
        None
    )
    current_zone = current.get("current_zone", "unknown") if current else "unknown"

    # Get zone coordinates for distance calculation
    zones = {i.get("zone_name"): i for i in items if i.get("type") == "zone"}

    # Calculate travel time between current zone and destination
    travel_minutes = _estimate_travel_minutes(current_zone, req.destination_zone, zones)

    # Preparation buffer (getting ready, packing, etc.)
    prep_buffer = _get_prep_buffer(current_zone)

    total_lead_time = travel_minutes + prep_buffer

    # Calculate when reminder should fire
    fire_at = _subtract_minutes_str(req.event_time, total_lead_time)

    # Build contextual reminder message
    if current_zone == req.destination_zone or current_zone == "campus":
        message = f"Class in {travel_minutes} min — you're already nearby"
        urgency = "low"
    elif current_zone == "home":
        message = f"Leave for campus in {prep_buffer} min — {travel_minutes} min commute"
        urgency = "high"
    elif current_zone == "transit":
        message = f"Heading to {req.destination_zone} — arrive by {req.event_time}"
        urgency = "medium"
    else:
        message = f"Event at {req.event_time} — {total_lead_time} min to get ready and travel"
        urgency = "medium"

    return {
        "current_zone": current_zone,
        "destination_zone": req.destination_zone,
        "event_time": req.event_time,
        "fire_reminder_at": fire_at,
        "travel_minutes": travel_minutes,
        "prep_buffer_minutes": prep_buffer,
        "total_lead_time_minutes": total_lead_time,
        "reminder_message": message,
        "urgency": urgency,
    }


# ── Get All Zones ────────────────────────────────────────────────────────────

@router.get("/zones/{user_id}")
async def get_all_zones(user_id: str):
    """Returns all saved geofence zones for a user."""
    table = get_table("locations")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    zones = [i for i in response.get("Items", []) if i.get("type") == "zone"]
    return {"zones": zones, "total": len(zones)}


# ── Update a Zone ─────────────────────────────────────────────────────────────

@router.put("/zones/{user_id}/{zone_name}")
async def update_zone(user_id: str, zone_name: str, zone: ZoneDefinition):
    """Updates coordinates or radius for an existing zone."""
    table = get_table("locations")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    existing = next(
        (i for i in response.get("Items", [])
         if i.get("type") == "zone" and i.get("zone_name") == zone_name),
        None
    )
    if not existing:
        raise HTTPException(status_code=404, detail=f"Zone '{zone_name}' not found")

    table.update_item(
        Key={"user_id": user_id, "location_id": existing["location_id"]},
        UpdateExpression="SET latitude = :lat, longitude = :lng, radius_meters = :r, label = :l, updated_at = :u",
        ExpressionAttributeValues={
            ":lat": str(zone.latitude),
            ":lng": str(zone.longitude),
            ":r": zone.radius_meters,
            ":l": zone.label,
            ":u": datetime.now().isoformat(),
        },
    )
    return {"updated": True, "zone_name": zone_name}


# ── Transition History ────────────────────────────────────────────────────────

@router.get("/history/{user_id}")
async def get_location_history(user_id: str, limit: int = 50):
    """Returns recent zone transitions for debugging / analytics."""
    table = get_table("locations")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    logs = [
        i for i in response.get("Items", [])
        if i.get("type") == "transition_log"
    ]
    logs.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
    return {"transitions": logs[:limit], "total": len(logs)}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates distance between two GPS coordinates in meters."""
    R = 6371000     # Earth's radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)

    a = (math.sin(d_phi / 2) ** 2 +
         math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def _estimate_travel_minutes(from_zone: str, to_zone: str, zones: dict) -> int:
    """
    Estimates travel time between two zones.
    First tries GPS distance calculation, falls back to lookup table.
    """
    # If we have actual coordinates for both zones, calculate from distance
    if from_zone in zones and to_zone in zones:
        from_z = zones[from_zone]
        to_z = zones[to_zone]
        distance = _haversine_meters(
            float(from_z.get("latitude", 0)), float(from_z.get("longitude", 0)),
            float(to_z.get("latitude", 0)), float(to_z.get("longitude", 0)),
        )
        # Rough estimate: walking 80m/min, auto 400m/min
        if distance < 1000:
            return max(5, int(distance / 80))       # Walking
        else:
            return max(10, int(distance / 400) + 5)  # Auto/bus + walking

    # Fallback: static lookup table (conservative estimates for Indian campuses)
    travel_table = {
        ("home", "campus"):     40,
        ("campus", "home"):     40,
        ("hostel", "campus"):   15,
        ("campus", "hostel"):   15,
        ("library", "campus"):  8,
        ("campus", "library"):  8,
        ("home", "library"):    45,
        ("library", "home"):    45,
        ("hostel", "library"):  10,
        ("library", "hostel"):  10,
        ("home", "hostel"):     35,
        ("hostel", "home"):     35,
    }
    return travel_table.get((from_zone, to_zone), 30)   # Default 30 min


def _get_prep_buffer(current_zone: str) -> int:
    """Returns preparation buffer in minutes based on where the student is."""
    buffers = {
        "home": 15,         # Shower, change, pack
        "hostel": 10,       # Change, grab bag
        "campus": 5,        # Just walk over
        "library": 3,       # Pack up and leave
        "transit": 0,       # Already moving
        "unknown": 10,      # Safe default
    }
    return buffers.get(current_zone, 10)


def _subtract_minutes_str(time_str: str, minutes: int) -> str:
    """Subtracts N minutes from an HH:MM time string."""
    try:
        h, m = map(int, time_str.split(":"))
        total = h * 60 + m - minutes
        if total < 0:
            total += 24 * 60
        return f"{(total // 60) % 24:02d}:{total % 60:02d}"
    except (ValueError, IndexError):
        return time_str
