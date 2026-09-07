"""
High-Speed Poller for Economic Calendar Events.
Uses TradingView's economic calendar backend API (real-time, zero auth required).
Polls at normal speed (every 10s) when idle, and shifts into hyper-speed (every 300ms)
during the exact release window (e.g. 14:29:50 - 14:30:30 GMT+2).
"""
import time
import json
import urllib.request
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any, Callable, Optional

API_URL = "https://economic-calendar.tradingview.com/events"

class CalendarPoller:
    def __init__(self, on_signal_callback: Optional[Callable[[Dict[str, Any]], None]] = None):
        self.on_signal_callback = on_signal_callback
        self.seen_released_events = set()

    def fetch_events(self, start_dt: datetime, end_dt: datetime) -> List[Dict[str, Any]]:
        from_str = start_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        to_str = end_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        url = f"{API_URL}?from={from_str}&to={to_str}&countries=US"
        req = urllib.request.Request(
            url,
            headers={
                "Origin": "https://www.tradingview.com",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            }
        )
        try:
            with urllib.request.urlopen(req, timeout=4) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data.get("result", [])
        except Exception as e:
            print(f"[Poller Error] Failed to fetch events: {e}")
            return []

    def run_poll_cycle(self) -> List[Dict[str, Any]]:
        """Checks events for today and returns new actual releases."""
        now_utc = datetime.now(timezone.utc)
        start_utc = now_utc - timedelta(hours=2)
        end_utc = now_utc + timedelta(hours=6)

        events = self.fetch_events(start_utc, end_utc)
        new_releases = []

        for ev in events:
            ev_id = ev.get("id")
            actual = ev.get("actual")
            if actual is not None and ev_id not in self.seen_released_events:
                self.seen_released_events.add(ev_id)
                new_releases.append(ev)

        return new_releases
