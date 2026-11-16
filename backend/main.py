import logging
import os
import sqlite3
from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager, closing, contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi import Path as PathParam
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import AwareDatetime, BaseModel, Field, FiniteFloat

DB_PATH = (
    Path(os.getenv("RAILWAY_VOLUME_MOUNT_PATH") or Path(__file__).parent)
    / "toposurvey.sqlite3"
)
logger = logging.getLogger(__name__)


class SurveyInput(BaseModel):
    latitude: Annotated[FiniteFloat, Field(strict=True, ge=-90, le=90)]
    longitude: Annotated[FiniteFloat, Field(strict=True, ge=-180, le=180)]
    elevation: Annotated[FiniteFloat, Field(strict=True)]


class Survey(SurveyInput):
    id: int
    created_at: AwareDatetime


SurveyId = Annotated[int, PathParam(ge=1, le=2**63 - 1)]


@contextmanager
def database() -> Iterator[sqlite3.Connection]:
    with closing(sqlite3.connect(DB_PATH)) as connection, connection:
        connection.row_factory = sqlite3.Row
        yield connection


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    with database() as connection:
        connection.execute("""
            CREATE TABLE IF NOT EXISTS surveys (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                elevation REAL NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
    yield


app = FastAPI(title="TopoSurvey API", lifespan=lifespan)


@app.exception_handler(sqlite3.Error)
async def database_error(_request: Request, exc: sqlite3.Error) -> JSONResponse:
    logger.error("SQLite request failed", exc_info=exc)
    return JSONResponse(status_code=503, content={"detail": "SQLite unavailable"})


@app.exception_handler(RequestValidationError)
async def validation_error(
    _request: Request, exc: RequestValidationError
) -> JSONResponse:
    # Rejected input can contain NaN or infinity, which JSON cannot encode.
    errors = [
        {key: error[key] for key in ("loc", "msg", "type")}
        for error in exc.errors()
    ]
    return JSONResponse(status_code=422, content={"detail": errors})


@app.get("/api/health")
def health() -> dict[str, str]:
    with database() as connection:
        connection.execute("SELECT id FROM surveys LIMIT 1").fetchone()
    return {"status": "ok", "database": "ok"}


@app.post("/api/surveys", status_code=201)
def create_survey(survey: SurveyInput) -> Survey:
    created_at = datetime.now(UTC)
    with database() as connection:
        cursor = connection.execute(
            """
            INSERT INTO surveys (latitude, longitude, elevation, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (survey.latitude, survey.longitude, survey.elevation, created_at.isoformat()),
        )
        return Survey(id=cursor.lastrowid, created_at=created_at, **survey.model_dump())


@app.get("/api/surveys")
def list_surveys() -> list[Survey]:
    with database() as connection:
        rows = connection.execute("SELECT * FROM surveys ORDER BY id DESC").fetchall()
    return [Survey(**row) for row in rows]


@app.get("/api/surveys/{id}")
def get_survey(id: SurveyId) -> Survey:
    with database() as connection:
        row = connection.execute("SELECT * FROM surveys WHERE id = ?", (id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Survey not found")
    return Survey(**row)


@app.delete("/api/surveys/{id}", status_code=204)
def delete_survey(id: SurveyId) -> Response:
    with database() as connection:
        cursor = connection.execute("DELETE FROM surveys WHERE id = ?", (id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Survey not found")
    return Response(status_code=204)
