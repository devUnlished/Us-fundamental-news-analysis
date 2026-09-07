"""
News Reminder & Notification Daemon.
Monitors upcoming high-impact US news releases (NFP, CPI, FOMC, Core PCE, etc.).
Triggers Windows Desktop notifications:
  1. On PC Startup / App Launch: Lists today's and tomorrow's upcoming events.
  2. 24 Hours Before Event.
  3. 4 Hours Before Event.
  4. 1 Hour Before Event.
  5. 15 Minutes Before Event (Final countdown to prepare charts).
"""
import time
import json
import urllib.request
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any

from engine.news_engine import identify_rule

try:
    from plyer import notification
    HAS_PLYER = True
except ImportError:
    HAS_PLYER = False

API_URL = "https://economic-calendar.tradingview.com/events"

class NewsReminderDaemon:
    def __init__(self):
        # Keeps track of sent reminders: event_id -> set of triggered thresholds (e.g., "startup", "24h", "4h", "1h", "15m")
        self.notified_milestones = {}

    def send_notification(self, title: str, message: str):
        print(f"\n🔔 [NOTIFICATION] {title}\n{message}\n")
        if HAS_PLYER:
            try:
                notification.notify(
                    title=title,
                    message=message,
                    app_name="News Sniper",
                    timeout=10
                )
            except Exception as e:
                print(f"[Toast Error]: {e}")

    def fetch_upcoming_events(self, days_ahead: int = 2) -> List[Dict[str, Any]]:
        now_utc = datetime.now(timezone.utc)
        from_str = now_utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        to_str = (now_utc + timedelta(days=days_ahead)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        url = f"{API_URL}?from={from_str}&to={to_str}&countries=US"

        req = urllib.request.Request(
            url,
            headers={
                "Origin": "https://www.tradingview.com",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            }
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                raw_events = data.get("result", [])
                
                matched = []
                for ev in raw_events:
                    rule = identify_rule(ev.get("title", ""))
                    if rule and rule.get("tier", 3) <= 2:  # High impact Tier 1 & 2
                        matched.append({
                            "id": ev.get("id"),
                            "title": ev.get("title"),
                            "rule_name": rule["name"],
                            "tier": rule["tier"],
                            "date": ev.get("date"),
                            "forecast": ev.get("forecast"),
                            "previous": ev.get("previous")
                        })
                return matched
        except Exception as e:
            print(f"[Reminder Fetch Error]: {e}")
            return []

    def check_startup_briefing(self):
        """Notifies user of today's and tomorrow's upcoming events upon starting the app."""
        events = self.fetch_upcoming_events(days_ahead=2)
        if not events:
            return

        now_utc = datetime.now(timezone.utc)
        today_events = []
        tomorrow_events = []

        for ev in events:
            try:
                ev_time = datetime.fromisoformat(ev["date"].replace("Z", "+00:00"))
                # Local GMT+2
                ev_local = ev_time + timedelta(hours=2)
                now_local = now_utc + timedelta(hours=2)

                if ev_local.date() == now_local.date():
                    today_events.append(f"• {ev['rule_name']} at {ev_local.strftime('%H:%M')} GMT+2")
                elif ev_local.date() == (now_local + timedelta(days=1)).date():
                    tomorrow_events.append(f"• {ev['rule_name']} at {ev_local.strftime('%H:%M')} GMT+2")
            except Exception:
                pass

        brief_lines = []
        if today_events:
            brief_lines.append("TODAY:")
            brief_lines.extend(today_events[:3])
        if tomorrow_events:
            brief_lines.append("TOMORROW:")
            brief_lines.extend(tomorrow_events[:3])

        if brief_lines:
            self.send_notification(
                title="📅 Upcoming US High-Impact News",
                message="\n".join(brief_lines)
            )

    def check_milestone_reminders(self):
        """Checks for 24h, 4h, 1h, and 15m countdown milestones."""
        events = self.fetch_upcoming_events(days_ahead=2)
        now_utc = datetime.now(timezone.utc)

        for ev in events:
            ev_id = ev["id"]
            if ev_id not in self.notified_milestones:
                self.notified_milestones[ev_id] = set()

            try:
                ev_time = datetime.fromisoformat(ev["date"].replace("Z", "+00:00"))
                time_diff = (ev_time - now_utc).total_seconds()
                ev_local_str = (ev_time + timedelta(hours=2)).strftime("%H:%M GMT+2")

                # 24 Hours reminder (within 23.5h - 24.5h)
                if 23 * 3600 <= time_diff <= 24.5 * 3600 and "24h" not in self.notified_milestones[ev_id]:
                    self.notified_milestones[ev_id].add("24h")
                    self.send_notification(
                        title=f"⚠️ News Tomorrow: {ev['rule_name']}",
                        message=f"Releasing tomorrow at {ev_local_str}.\nForecast: {ev['forecast'] or 'N/A'}"
                    )

                # 4 Hours reminder (within 3.8h - 4.2h)
                elif 3.8 * 3600 <= time_diff <= 4.2 * 3600 and "4h" not in self.notified_milestones[ev_id]:
                    self.notified_milestones[ev_id].add("4h")
                    self.send_notification(
                        title=f"⏳ 4 Hours Until: {ev['rule_name']}",
                        message=f"Releasing at {ev_local_str}.\nPrepare trading strategy for Gold (XAUUSD)."
                    )

                # 1 Hour reminder (within 55m - 65m)
                elif 55 * 60 <= time_diff <= 65 * 60 and "1h" not in self.notified_milestones[ev_id]:
                    self.notified_milestones[ev_id].add("1h")
                    self.send_notification(
                        title=f"🚨 1 HOUR ALERT: {ev['rule_name']}",
                        message=f"Releasing in 1 hour ({ev_local_str})!\nForecast: {ev['forecast']} | Prior: {ev['previous']}"
                    )

                # 15 Minutes reminder (within 13m - 16m)
                elif 13 * 60 <= time_diff <= 16 * 60 and "15m" not in self.notified_milestones[ev_id]:
                    self.notified_milestones[ev_id].add("15m")
                    self.send_notification(
                        title=f"🔥 15 MINS COUNTDOWN: {ev['rule_name']}",
                        message=f"Release at {ev_local_str}! Standby on charts for Buy/Sell signal."
                    )

            except Exception as e:
                print(f"[Milestone Parse Error]: {e}")

    def run(self):
        print("[Reminder Daemon] Initialized. Checking startup schedule...")
        self.check_startup_briefing()
        
        while True:
            try:
                self.check_milestone_reminders()
                time.sleep(60) # Check every minute
            except Exception as e:
                print(f"[Daemon Loop Error]: {e}")
                time.sleep(30)

if __name__ == "__main__":
    daemon = NewsReminderDaemon()
    daemon.run()
