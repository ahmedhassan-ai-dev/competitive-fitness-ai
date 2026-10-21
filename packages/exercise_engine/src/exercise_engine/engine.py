"""Deterministic, side-view exercise reference with no inference dependencies."""

from dataclasses import dataclass
from math import acos, degrees, hypot
from typing import Protocol
from uuid import UUID, uuid5

from packages.contracts.v1.models import ExerciseType, FormFeedback, PoseFrame, RepEvent


@dataclass(frozen=True)
class EngineOutput:
    reps: tuple[RepEvent, ...] = ()
    feedback: tuple[FormFeedback, ...] = ()


class ExerciseEngine(Protocol):
    """One engine per session; process strictly increasing monotonic timestamps."""

    def process(self, frame: PoseFrame) -> EngineOutput: ...

    def reset(self) -> None:
        """Discard partial movement; retain sequence and last timestamp."""
        ...


class ReferenceEngine:
    VERSION = "reference-1.0.0"
    HOLD_MS = 100
    MAX_GAP_MS = 500
    MIN_CONFIDENCE = 0.8

    def __init__(self, session_id: UUID, exercise: ExerciseType):
        self.session_id = session_id
        self.exercise = ExerciseType(exercise)
        self.sequence = 0
        self._last_timestamp = None
        self.reset()

    def reset(self) -> None:
        self.phase = "unarmed"
        self._candidate = None
        self._candidate_since = None
        self._started = None
        self._confidence = 1.0

    def process(self, frame: PoseFrame) -> EngineOutput:
        timestamp = frame.timestamp_ms
        if self._last_timestamp is not None:
            if timestamp <= self._last_timestamp:
                raise ValueError("timestamps must strictly increase")
            if timestamp - self._last_timestamp > self.MAX_GAP_MS:
                self.reset()
        self._last_timestamp = timestamp
        names = (
            ("hip", "knee", "ankle")
            if self.exercise == ExerciseType.SQUAT
            else ("shoulder", "elbow", "wrist")
        )
        points = [frame.landmarks.get(name) for name in names]
        if any(p is None or p.confidence < self.MIN_CONFIDENCE for p in points):
            self.reset()
            return EngineOutput(
                feedback=(
                    FormFeedback(
                        code="low_confidence",
                        severity="warning",
                        message="Show all required joints clearly.",
                    ),
                )
            )
        a, b, c = points
        u, v = (a.x - b.x, a.y - b.y), (c.x - b.x, c.y - b.y)
        length = hypot(*u) * hypot(*v)
        if length <= 1e-12:
            self.reset()
            return EngineOutput(
                feedback=(
                    FormFeedback(
                        code="low_confidence",
                        severity="warning",
                        message="Joint geometry is degenerate.",
                    ),
                )
            )
        angle = degrees(acos(max(-1.0, min(1.0, (u[0] * v[0] + u[1] * v[1]) / length))))
        self._confidence = min(self._confidence, *(p.confidence for p in points))
        top, bottom = (160, 100) if self.exercise == ExerciseType.SQUAT else (155, 90)
        target = "top" if angle >= top else "bottom" if angle <= bottom else None
        expected = "bottom" if self.phase == "top" else "top"
        if target != expected:
            self._candidate = None
            self._candidate_since = None
            return EngineOutput()
        if self._candidate != target:
            self._candidate, self._candidate_since = target, timestamp
            return EngineOutput()
        if timestamp - self._candidate_since < self.HOLD_MS:
            return EngineOutput()
        self._candidate = None
        if self.phase == "unarmed":
            self.phase = "top"
            self._started = timestamp
            self._confidence = min(p.confidence for p in points)
        elif self.phase == "top":
            self.phase = "bottom"
        else:
            self.sequence += 1
            rep = RepEvent(
                schema_version="1.0.0",
                event_id=uuid5(self.session_id, f"rep:{self.sequence}"),
                session_id=self.session_id,
                exercise=self.exercise,
                sequence=self.sequence,
                started_at_ms=self._started,
                ended_at_ms=timestamp,
                valid=True,
                confidence=self._confidence,
                form_score=1.0,
                feedback=[],
                engine_version=self.VERSION,
            )
            self.phase, self._started = "top", timestamp
            self._confidence = min(p.confidence for p in points)
            return EngineOutput(reps=(rep,))
        return EngineOutput()
