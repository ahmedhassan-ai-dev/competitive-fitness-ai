"""Authoritative Pydantic wire models. Export using generate.py."""

from datetime import datetime, timedelta
from enum import Enum
from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)

Unit = Annotated[float, Field(strict=True, ge=0, le=1, allow_inf_nan=False)]
Count = Annotated[int, Field(strict=True, ge=0)]
Positive = Annotated[int, Field(strict=True, ge=1)]
Label = Annotated[str, StringConstraints(min_length=1, max_length=100)]


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    @field_validator("*", mode="after")
    @classmethod
    def utc_dates(cls, value):
        if isinstance(value, datetime) and (
            value.tzinfo is None or value.utcoffset() != timedelta(0)
        ):
            raise ValueError("timestamps must use UTC")
        return value


class ExerciseType(str, Enum):
    SQUAT = "squat"
    PUSH_UP = "push_up"


class FormFeedback(Contract):
    code: Literal["low_confidence", "incomplete_range", "body_alignment"]
    severity: Literal["info", "warning"]
    message: Annotated[str, StringConstraints(min_length=1, max_length=250)]


class WorkoutSession(Contract):
    session_id: UUID
    user_id: UUID
    exercise: ExerciseType
    challenge_id: UUID | None = None
    status: Literal["active", "completed"]
    started_at: datetime
    ended_at: datetime | None = None

    @model_validator(mode="after")
    def lifecycle(self):
        if (self.status == "completed") != (self.ended_at is not None):
            raise ValueError("only completed sessions have ended_at")
        if self.ended_at is not None and self.ended_at < self.started_at:
            raise ValueError("ended_at precedes started_at")
        return self


class RepEvent(Contract):
    schema_version: Literal["1.0.0"]
    event_id: UUID
    session_id: UUID
    exercise: ExerciseType
    sequence: Positive
    started_at_ms: Count
    ended_at_ms: Count
    valid: bool = Field(strict=True)
    confidence: Unit
    form_score: Unit
    feedback: list[FormFeedback] = Field(max_length=20)
    engine_version: Label

    @model_validator(mode="after")
    def duration(self):
        if self.ended_at_ms <= self.started_at_ms:
            raise ValueError("rep must have positive duration")
        if self.valid and self.confidence < 0.8:
            raise ValueError("valid reps require confidence >= 0.8")
        return self


class ChallengeParticipant(Contract):
    user_id: UUID
    session_id: UUID | None = None
    accepted_reps: Count


class Challenge(Contract):
    challenge_id: UUID
    exercise: ExerciseType
    status: Literal["waiting", "active", "completed"]
    created_at: datetime
    participants: list[ChallengeParticipant] = Field(min_length=1, max_length=2)

    @model_validator(mode="after")
    def membership(self):
        if len({p.user_id for p in self.participants}) != len(self.participants):
            raise ValueError("participants must be distinct")
        if self.status != "waiting" and len(self.participants) != 2:
            raise ValueError("active/completed challenges require two participants")
        sessions = [p.session_id for p in self.participants if p.session_id is not None]
        if len(set(sessions)) != len(sessions):
            raise ValueError("participant sessions must be distinct")
        if self.status != "waiting" and len(sessions) != 2:
            raise ValueError("active/completed participants require sessions")
        if self.status == "waiting" and (
            len(sessions) == 2 or any(p.accepted_reps for p in self.participants)
        ):
            raise ValueError("waiting rooms cannot have two sessions or scores")
        return self


class ScoreUpdate(Contract):
    schema_version: Literal["1.0.0"]
    type: Literal["challenge.score_updated"]
    event_id: UUID
    challenge_id: UUID
    revision: Positive
    occurred_at: datetime
    participants: list[ChallengeParticipant] = Field(min_length=2, max_length=2)

    @model_validator(mode="after")
    def distinct_participants(self):
        if len({p.user_id for p in self.participants}) != 2:
            raise ValueError("score snapshot requires distinct users")
        if any(p.session_id is None for p in self.participants):
            raise ValueError("score snapshot requires participant sessions")
        if self.participants[0].session_id == self.participants[1].session_id:
            raise ValueError("score snapshot requires distinct sessions")
        return self


class AuthRequest(Contract):
    username: Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9_]{3,32}$")]
    password: Annotated[str, StringConstraints(min_length=12, max_length=128)]


class TokenResponse(Contract):
    access_token: Annotated[str, StringConstraints(min_length=1)]
    token_type: Literal["bearer"]
    expires_in: Positive
    user_id: UUID


class CreateWorkout(Contract):
    exercise: ExerciseType
    challenge_id: UUID | None = None


class CreateChallenge(Contract):
    exercise: ExerciseType


class RepReceipt(Contract):
    event_id: UUID
    session_id: UUID
    disposition: Literal["accepted", "rejected"]
    reason: Literal["invalid_rep", "low_confidence"] | None
    accepted_reps: Count

    @model_validator(mode="after")
    def reason_matches(self):
        if (self.disposition == "rejected") != (self.reason is not None):
            raise ValueError("only rejected events have a reason")
        return self


class ApiError(Contract):
    code: Literal[
        "unauthorized", "forbidden", "not_found", "conflict", "validation_error"
    ]
    message: Label


class Landmark(Contract):
    x: Unit
    y: Unit
    confidence: Unit


class PoseFrame(Contract):
    timestamp_ms: Count
    landmarks: dict[
        Literal["shoulder", "elbow", "wrist", "hip", "knee", "ankle"], Landmark
    ]
