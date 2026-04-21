# ─── Imports ─────────────────────────────────────────────────
import os
import json
import logging
from datetime import datetime

import boto3
import redis
from fastapi import FastAPI, HTTPException
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy import create_engine, text
from nanoid import generate

# ─── Logging ─────────────────────────────────────────────────
# Structured JSON logging so CloudWatch can parse fields
logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}'
)
log = logging.getLogger(__name__)

# ─── Config from environment variables ───────────────────────
# All config comes from env vars injected by ECS task definition
# Locally, docker-compose sets these
DATABASE_URL   = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/urlshortener")
REDIS_URL      = os.getenv("REDIS_URL",    "redis://localhost:6379")
SQS_QUEUE_URL  = os.getenv("SQS_QUEUE_URL", "")
AWS_REGION     = os.getenv("AWS_REGION",   "eu-west-2")

# ─── App setup ───────────────────────────────────────────────
app = FastAPI(title="URL Shortener API", version="1.0.0")

# ─── Database connection ──────────────────────────────────────
# SQLAlchemy engine — connection pool managed automatically
# pool_pre_ping=True checks connection health before using it
engine = create_engine(DATABASE_URL, pool_pre_ping=True)

# ─── Redis connection ─────────────────────────────────────────
# Used to cache short code → URL lookups
# Avoids hitting the database on every redirect
cache = redis.from_url(REDIS_URL, decode_responses=True)

# ─── AWS SQS client ──────────────────────────────────────────
# boto3 auto-discovers credentials from ECS task role
# Locally uses whatever is in ~/.aws/credentials
sqs = boto3.client("sqs", region_name=AWS_REGION)

# ─── Database setup ──────────────────────────────────────────
def init_db():
    """Create tables if they don't exist yet."""
    with engine.connect() as conn:
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS urls (
                id         SERIAL PRIMARY KEY,
                code       VARCHAR(10) UNIQUE NOT NULL,
                original   TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS clicks (
                id         SERIAL PRIMARY KEY,
                code       VARCHAR(10) NOT NULL,
                clicked_at TIMESTAMP DEFAULT NOW(),
                user_agent TEXT,
                ip_address TEXT
            )
        """))
        conn.commit()
    log.info("Database tables ready")

# Run on startup
@app.on_event("startup")
def startup():
    init_db()
    log.info("API service started")

# ─── Models ──────────────────────────────────────────────────
class ShortenRequest(BaseModel):
    url: str

class ShortenResponse(BaseModel):
    code:      str
    short_url: str
    original:  str

# ─── Routes ──────────────────────────────────────────────────

@app.get("/health")
def health():
    """
    ALB health check endpoint.
    Does NOT check database or Redis — so ALB doesn't mark us
    unhealthy just because a downstream dependency is slow.
    """
    return {"status": "healthy"}


@app.post("/shorten", response_model=ShortenResponse)
def shorten(req: ShortenRequest):
    """
    Create a short URL.
    Generates a 6-char random code, stores in PostgreSQL.
    """
    if not req.url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="URL must start with http:// or https://")

    # Generate a unique short code using nanoid
    # 6 chars gives ~56 billion combinations — enough for any project
    code = generate(size=6)

    with engine.connect() as conn:
        conn.execute(
            text("INSERT INTO urls (code, original) VALUES (:code, :url)"),
            {"code": code, "url": req.url}
        )
        conn.commit()

    log.info(f"Shortened {req.url} to {code}")

    # The host in production will be the ALB/domain
    # Locally it'll be localhost:8080
    host = os.getenv("HOST", "localhost:8080")
    return ShortenResponse(
        code=code,
        short_url=f"http://{host}/{code}",
        original=req.url
    )


@app.get("/{code}")
def redirect(code: str, request_user_agent: str = ""):
    """
    Redirect a short code to the original URL.
    1. Check Redis cache first (fast path)
    2. Fall back to PostgreSQL if not cached
    3. Publish click event to SQS for the worker to process
    """
    # Check Redis cache first — avoids DB hit on popular links
    cached_url = cache.get(f"url:{code}")

    if cached_url:
        original_url = cached_url
        log.info(f"Cache hit for code={code}")
    else:
        # Cache miss — look up in database
        with engine.connect() as conn:
            row = conn.execute(
                text("SELECT original FROM urls WHERE code = :code"),
                {"code": code}
            ).fetchone()

        if not row:
            raise HTTPException(status_code=404, detail=f"Code '{code}' not found")

        original_url = row[0]

        # Cache for 1 hour (3600 seconds) to speed up future requests
        cache.setex(f"url:{code}", 3600, original_url)

    # Publish click event to SQS
    # Worker will consume this and write to PostgreSQL analytics table
    if SQS_QUEUE_URL:
        try:
            sqs.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps({
                    "code":       code,
                    "clicked_at": datetime.utcnow().isoformat(),
                })
            )
        except Exception as e:
            # Don't fail the redirect if SQS is unavailable
            # The redirect is more important than the analytics
            log.warning(f"Failed to publish click event: {e}")

    # HTTP 301 = permanent redirect (cached by browsers)
    return RedirectResponse(url=original_url, status_code=301)