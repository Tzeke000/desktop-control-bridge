"""Launch the system-tray controller (starts the API on 127.0.0.1)."""

from dotenv import load_dotenv

load_dotenv()

from bridge.tray import run_tray

if __name__ == "__main__":
    run_tray()
