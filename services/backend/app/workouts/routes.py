"""Authenticated workout history, not competitive score verification."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user
from app.auth.models import User
from app.db import get_session
from app.workouts.catalog import CATALOG, EXERCISES, ExerciseDefinition
from app.workouts.models import WorkoutRecord

router = APIRouter(prefix="/api/v1", tags=["workouts"])
UserDep = Annotated[User, Depends(get_current_user)]
SessionDep = Annotated[Session, Depends(get_session)]


class CompleteWorkoutRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    exercise: Literal["squat", "push_up", "jumping_jack", "plank"]
    reps: int = Field(default=0, ge=0, le=100000)
    hold_ms: int = Field(default=0, ge=0, le=86_400_000)
    active_ms: int = Field(ge=0, le=86_400_000)

    @model_validator(mode="after")
    def metric_and_duration(self):
        metric = CATALOG[self.exercise].metric
        if metric == "reps" and self.hold_ms != 0:
            raise ValueError("Rep exercises must not submit hold_ms")
        if metric == "hold_ms" and self.reps != 0:
            raise ValueError("Hold exercises must not submit reps")
        if self.hold_ms > self.active_ms:
            raise ValueError("Hold time cannot exceed active time")
        return self


class WorkoutResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    workout_id: UUID
    exercise: str
    metric: str
    reps: int
    hold_ms: int
    active_ms: int
    created_at: datetime
    source: str


@router.get("/exercises", response_model=list[ExerciseDefinition])
def get_exercises() -> tuple[ExerciseDefinition, ...]:
    return EXERCISES


@router.post("/workouts", status_code=201, response_model=WorkoutResponse)
def create_workout(body: CompleteWorkoutRequest, user: UserDep, session: SessionDep):
    workout = WorkoutRecord(
        user_id=user.user_id,
        exercise=body.exercise,
        metric=CATALOG[body.exercise].metric,
        reps=body.reps,
        hold_ms=body.hold_ms,
        active_ms=body.active_ms,
        source="device_reported",
    )
    session.add(workout)
    session.commit()
    session.refresh(workout)
    return workout


@router.get("/workouts", response_model=list[WorkoutResponse])
def list_workouts(user: UserDep, session: SessionDep, limit: int = 30):
    if not 1 <= limit <= 100:
        raise HTTPException(status_code=422, detail="limit must be 1..100")
    stmt = (
        select(WorkoutRecord)
        .where(WorkoutRecord.user_id == user.user_id)
        .order_by(WorkoutRecord.created_at.desc(), WorkoutRecord.workout_id.desc())
        .limit(limit)
    )
    return session.scalars(stmt).all()
