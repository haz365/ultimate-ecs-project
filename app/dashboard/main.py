# ─── Imports ─────────────────────────────────────────────────
import os
import logging
from typing import List

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import create_engine, text

# ─── Logging ─────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}'
)
log = logging.getLogger(__name__)

# ─── Config ──────────────────────────────────────────────────
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/urlshortener"
)
PORT = int(os.getenv("PORT", "8081"))

# ─── App + DB ────────────────────────────────────────────────
app    = FastAPI(title="Analytics Dashboard", version="1.0.0")
engine = create_engine(DATABASE_URL, pool_pre_ping=True)

# ─── Models ──────────────────────────────────────────────────
class TopURL(BaseModel):
    code:     str
    original: str
    clicks:   int

class RecentClick(BaseModel):
    code:       str
    clicked_at: str

# ─── Routes ──────────────────────────────────────────────────

@app.get("/health")
def health():
    """ALB health check — no DB dependency."""
    return {"status": "healthy"}


@app.get("/api/top", response_model=List[TopURL])
def top_urls():
    """Top 10 URLs by total click count."""
    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT u.code, u.original, COUNT(c.id) as clicks
            FROM urls u
            LEFT JOIN clicks c ON u.code = c.code
            GROUP BY u.code, u.original
            ORDER BY clicks DESC
            LIMIT 10
        """)).fetchall()

    return [
        TopURL(code=r[0], original=r[1], clicks=r[2])
        for r in rows
    ]


@app.get("/api/recent", response_model=List[RecentClick])
def recent_clicks():
    """20 most recent click events."""
    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT code, clicked_at
            FROM clicks
            ORDER BY clicked_at DESC
            LIMIT 20
        """)).fetchall()

    return [
        RecentClick(code=r[0], clicked_at=str(r[1]))
        for r in rows
    ]


@app.get("/", response_class=HTMLResponse)
def dashboard():
    """Analytics dashboard HTML page."""
    return HTMLResponse(content=DASHBOARD_HTML)


# ─── HTML UI ─────────────────────────────────────────────────
DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Analytics Dashboard</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, sans-serif;
      background: #0f0f1a;
      color: #fff;
      padding: 32px;
    }
    h1 {
      font-size: 1.8rem;
      margin-bottom: 8px;
      background: linear-gradient(135deg, #667eea, #a78bfa);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }
    .subtitle { color: #8888aa; margin-bottom: 32px; font-size: 0.95rem; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
    .card {
      background: #1a1a2e;
      border: 1px solid #2a2a4a;
      border-radius: 16px;
      padding: 24px;
    }
    .card h2 { font-size: 1rem; color: #a78bfa; margin-bottom: 16px; }
    table { width: 100%; border-collapse: collapse; }
    th {
      text-align: left;
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 1px;
      color: #8888aa;
      padding: 8px 0;
    }
    td {
      padding: 8px 0;
      font-size: 0.9rem;
      border-bottom: 1px solid #2a2a4a;
    }
    .code { color: #a78bfa; font-weight: 600; }
    .url {
      color: #8888aa;
      font-size: 0.8rem;
      max-width: 200px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .clicks { color: #22c55e; font-weight: 600; }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: #2a2a4a;
      border-radius: 20px;
      padding: 4px 12px;
      font-size: 0.8rem;
      color: #a78bfa;
      margin-bottom: 24px;
    }
    .dot {
      width: 6px; height: 6px;
      background: #22c55e;
      border-radius: 50%;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.4; }
    }
  </style>
</head>
<body>
  <h1>Analytics Dashboard</h1>
  <p class="subtitle">
    URL shortener analytics — ECS Fargate + PostgreSQL + SQS
  </p>
  <div class="badge">
    <span class="dot"></span>
    Live — refreshes every 10 seconds
  </div>
  <div class="grid">
    <div class="card">
      <h2>Top URLs by clicks</h2>
      <table>
        <thead>
          <tr><th>Code</th><th>URL</th><th>Clicks</th></tr>
        </thead>
        <tbody id="top-body">
          <tr><td colspan="3" style="color:#8888aa">Loading...</td></tr>
        </tbody>
      </table>
    </div>
    <div class="card">
      <h2>Recent clicks</h2>
      <table>
        <thead>
          <tr><th>Code</th><th>Time</th></tr>
        </thead>
        <tbody id="recent-body">
          <tr><td colspan="2" style="color:#8888aa">Loading...</td></tr>
        </tbody>
      </table>
    </div>
  </div>
  <script>
    async function load() {
      try {
        const [top, recent] = await Promise.all([
          fetch('/api/top').then(r => r.json()),
          fetch('/api/recent').then(r => r.json())
        ]);

        document.getElementById('top-body').innerHTML =
          (top || []).map(r =>
            '<tr>' +
            '<td class="code">' + r.code + '</td>' +
            '<td class="url">' + r.original + '</td>' +
            '<td class="clicks">' + r.clicks + '</td>' +
            '</tr>'
          ).join('') ||
          '<tr><td colspan="3" style="color:#8888aa">No URLs yet</td></tr>';

        document.getElementById('recent-body').innerHTML =
          (recent || []).map(r =>
            '<tr>' +
            '<td class="code">' + r.code + '</td>' +
            '<td style="color:#8888aa;font-size:0.8rem">' +
            new Date(r.clicked_at).toLocaleString() +
            '</td>' +
            '</tr>'
          ).join('') ||
          '<tr><td colspan="2" style="color:#8888aa">No clicks yet</td></tr>';

      } catch(e) {
        console.error('Failed to load data:', e);
      }
    }

    // Load immediately then every 10 seconds
    load();
    setInterval(load, 10000);
  </script>
</body>
</html>
"""