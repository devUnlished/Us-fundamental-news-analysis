"""
Desktop Floating HUD with integrated Reminder Daemon & Startup Schedule (Option A).
"""
import sys
import time
import winsound
import threading
import tkinter as tk
from datetime import datetime, timezone, timedelta

from engine.news_engine import analyze_event, identify_rule
from engine.poller import CalendarPoller
from engine.reminder_daemon import NewsReminderDaemon

class NewsHUDApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Fundamental News Sniper & Reminder HUD")
        self.root.geometry("680x250+40+40")
        self.root.attributes("-topmost", True)
        self.root.attributes("-alpha", 0.93)
        self.root.configure(bg="#121418")

        # Top status bar
        self.header_frame = tk.Frame(self.root, bg="#1a1e24", height=34)
        self.header_frame.pack(fill=tk.X)

        self.title_label = tk.Label(
            self.header_frame,
            text="⚡ FUNDAMENTAL NEWS SNIPER | XAUUSD",
            fg="#f0b90b",
            bg="#1a1e24",
            font=("Segoe UI", 10, "bold")
        )
        self.title_label.pack(side=tk.LEFT, padx=12, pady=5)

        self.clock_label = tk.Label(
            self.header_frame,
            text="--:--:-- GMT+2",
            fg="#848e9c",
            bg="#1a1e24",
            font=("Consolas", 10)
        )
        self.clock_label.pack(side=tk.RIGHT, padx=12, pady=5)

        # Main Signal Display
        self.signal_frame = tk.Frame(self.root, bg="#121418")
        self.signal_frame.pack(fill=tk.BOTH, expand=True, padx=15, pady=6)

        self.signal_badge = tk.Label(
            self.signal_frame,
            text="STANDBY - WAITING FOR NEWS RELEASE",
            fg="#94a3b8",
            bg="#1e2430",
            font=("Segoe UI", 16, "bold"),
            relief=tk.FLAT,
            pady=8
        )
        self.signal_badge.pack(fill=tk.X, pady=3)

        self.details_label = tk.Label(
            self.signal_frame,
            text="Monitoring NFP, CPI, FOMC, PCE, GDP, Retail Sales, PMIs...",
            fg="#e2e8f0",
            bg="#121418",
            font=("Segoe UI", 9)
        )
        self.details_label.pack(pady=2)

        self.upcoming_label = tk.Label(
            self.signal_frame,
            text="📅 Upcoming News: Checking schedule...",
            fg="#38bdf8",
            bg="#121418",
            font=("Segoe UI", 9, "italic")
        )
        self.upcoming_label.pack(pady=2)

        # Bottom Button controls
        self.footer_frame = tk.Frame(self.root, bg="#121418")
        self.footer_frame.pack(fill=tk.X, padx=15, pady=6)

        self.test_buy_btn = tk.Button(
            self.footer_frame,
            text="Test BUY (Weak USD)",
            bg="#059669",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            relief=tk.FLAT,
            padx=10,
            command=self.simulate_buy
        )
        self.test_buy_btn.pack(side=tk.LEFT, padx=4)

        self.test_sell_btn = tk.Button(
            self.footer_frame,
            text="Test SELL (Strong USD)",
            bg="#dc2626",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            relief=tk.FLAT,
            padx=10,
            command=self.simulate_sell
        )
        self.test_sell_btn.pack(side=tk.LEFT, padx=4)

        self.poller = CalendarPoller()
        self.reminder_daemon = NewsReminderDaemon()
        self.running = True

        self.update_clock()
        self.start_worker_threads()

    def update_clock(self):
        now_gmt2 = datetime.now(timezone.utc) + timedelta(hours=2)
        self.clock_label.config(text=now_gmt2.strftime("%H:%M:%S GMT+2"))
        self.root.after(1000, self.update_clock)

    def trigger_alert(self, signal: str, event_title: str, explanation: str, actual: float, forecast: float):
        if signal == "BUY":
            self.signal_badge.config(
                text="🟢 BUY GOLD (XAUUSD) - WEAK USD",
                bg="#10b981",
                fg="#ffffff"
            )
            threading.Thread(target=lambda: self.play_sound(880, 400), daemon=True).start()
        elif signal == "SELL":
            self.signal_badge.config(
                text="🔴 SELL GOLD (XAUUSD) - STRONG USD",
                bg="#ef4444",
                fg="#ffffff"
            )
            threading.Thread(target=lambda: self.play_sound(440, 500), daemon=True).start()
        else:
            self.signal_badge.config(
                text="⚪ NEUTRAL - NO STRONG BIAS",
                bg="#6b7280",
                fg="#ffffff"
            )

        self.details_label.config(
            text=f"[{event_title}] Actual: {actual} | Forecast: {forecast}\n{explanation}"
        )

    def play_sound(self, freq, duration):
        try:
            winsound.Beep(freq, duration)
            time.sleep(0.1)
            winsound.Beep(freq, duration)
        except Exception:
            pass

    def simulate_buy(self):
        self.trigger_alert(
            signal="BUY",
            event_title="US Non Farm Payrolls (NFP)",
            explanation="Actual (140k) missed forecast (185k) -> USD Weakens -> Gold Rallies",
            actual=140.0,
            forecast=185.0
        )

    def simulate_sell(self):
        self.trigger_alert(
            signal="SELL",
            event_title="US Non Farm Payrolls (NFP)",
            explanation="Actual (260k) beat forecast (185k) -> USD Strengthens -> Gold Plummets",
            actual=260.0,
            forecast=185.0
        )

    def start_worker_threads(self):
        # 1. Thread for live sub-second news release sniper
        threading.Thread(target=self.poll_loop, daemon=True).start()
        # 2. Thread for background upcoming reminders (startup, 24h, 4h, 1h, 15m)
        threading.Thread(target=self.reminder_loop, daemon=True).start()

    def reminder_loop(self):
        # Initial briefing on launch
        self.reminder_daemon.check_startup_briefing()
        while self.running:
            try:
                self.reminder_daemon.check_milestone_reminders()
                
                # Update on-screen upcoming schedule line
                events = self.reminder_daemon.fetch_upcoming_events(days_ahead=2)
                if events:
                    next_ev = events[0]
                    ev_dt = datetime.fromisoformat(next_ev["date"].replace("Z", "+00:00")) + timedelta(hours=2)
                    schedule_text = f"📅 Next: {next_ev['rule_name']} at {ev_dt.strftime('%b %d, %H:%M GMT+2')}"
                    self.root.after(0, lambda txt=schedule_text: self.upcoming_label.config(text=txt))

                time.sleep(60)
            except Exception as e:
                print(f"[HUD Reminder Loop Error]: {e}")
                time.sleep(30)

    def poll_loop(self):
        while self.running:
            try:
                now_gmt2 = datetime.now(timezone.utc) + timedelta(hours=2)
                # Rapid polling during release minute
                is_rush_window = (now_gmt2.minute == 29 and now_gmt2.second >= 45) or (now_gmt2.minute in [30, 31])
                poll_interval = 0.5 if is_rush_window else 5.0

                releases = self.poller.run_poll_cycle()
                for rel in releases:
                    result = analyze_event(rel)
                    if result and result.get("gold_signal") in ["BUY", "SELL"]:
                        self.root.after(0, lambda r=result: self.trigger_alert(
                            signal=r["gold_signal"],
                            event_title=r["rule_name"],
                            explanation=r["explanation"],
                            actual=r["actual"],
                            forecast=r["forecast"]
                        ))

                time.sleep(poll_interval)
            except Exception as e:
                print(f"[HUD Poll Error]: {e}")
                time.sleep(3)

def main():
    root = tk.Tk()
    app = NewsHUDApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
