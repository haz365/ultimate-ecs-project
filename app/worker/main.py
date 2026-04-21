# ─── Imports ─────────────────────────────────────────────────
import os
import json
import time
import logging
from datetime import datetime

import boto3
from sqlalchemy import create_engine, text

# ─── Logging ─────────────────────────────────────────────────
# Structured JSON so CloudWatch can parse individual fields
logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}'
)
log = logging.getLogger(__name__)

# ─── Config from environment variables ───────────────────────
DATABASE_URL  = os.getenv("DATABASE_URL",  "postgresql://postgres:postgres@localhost:5432/urlshortener")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
AWS_REGION    = os.getenv("AWS_REGION",    "eu-west-2")

# ─── Database connection ──────────────────────────────────────
# Same pattern as the api service
# pool_pre_ping checks connection health before each use
engine = create_engine(DATABASE_URL, pool_pre_ping=True)

# ─── AWS SQS client ──────────────────────────────────────────
# Credentials auto-discovered from ECS task role
# Locally uses ~/.aws/credentials
sqs = boto3.client("sqs", region_name=AWS_REGION)


def wait_for_db():
    """Retry database connection until it succeeds."""
    while True:
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            log.info("Database connected")
            return
        except Exception:
            log.info("Waiting for database...")
            time.sleep(2)


def process_message(message: dict) -> bool:
    """
    Process a single click event from SQS.
    Returns True if successful, False if should retry.
    """
    try:
        # Parse the JSON body published by the api service
        body = json.loads(message["Body"])
        code       = body["code"]
        clicked_at = body["clicked_at"]

        # Write click to PostgreSQL analytics table
        with engine.connect() as conn:
            conn.execute(
                text("INSERT INTO clicks (code, clicked_at) VALUES (:code, :clicked_at)"),
                {"code": code, "clicked_at": clicked_at}
            )
            conn.commit()

        log.info(f"Recorded click for code={code}")
        return True

    except json.JSONDecodeError as e:
        # Bad message format — delete it so it doesn't block the queue
        log.warning(f"Bad message format: {e}")
        return True  # delete it anyway

    except Exception as e:
        log.error(f"Failed to process message: {e}")
        return False  # leave in queue for retry


def main():
    log.info(f"Worker starting, region={AWS_REGION}")

    # Wait for database to be ready before starting
    wait_for_db()

    log.info("Worker ready, polling SQS")

    # ── Main polling loop ──────────────────────────────────────
    # Runs forever — ECS restarts if this exits unexpectedly
    while True:
        if not SQS_QUEUE_URL:
            # No queue configured — common when running locally
            log.info("No SQS queue configured, sleeping...")
            time.sleep(10)
            continue

        try:
            # Long poll SQS — waits up to 20s for messages
            # More efficient than constant short polling
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=10,    # process up to 10 at once
                WaitTimeSeconds=20,        # long polling — reduces API calls
            )
        except Exception as e:
            log.error(f"Failed to poll SQS: {e}")
            time.sleep(5)
            continue

        messages = response.get("Messages", [])

        for message in messages:
            success = process_message(message)

            if success:
                # Delete from SQS — signals successful processing
                # If we don't delete, SQS redelivers after visibility timeout
                try:
                    sqs.delete_message(
                        QueueUrl=SQS_QUEUE_URL,
                        ReceiptHandle=message["ReceiptHandle"]
                    )
                except Exception as e:
                    log.error(f"Failed to delete message: {e}")


if __name__ == "__main__":
    main()