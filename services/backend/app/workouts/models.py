"""Client-reported workout history. No claims of server-verified scores."""
from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

class WorkoutRecord(Base):
    __tablename__ = 'workout_records'
    __table_args__ = (
        CheckConstraint("exercise IN ('squat','push_up','jumping_jack','plank')", name='ck_workout_exercise'),
        CheckConstraint("metric IN ('reps','hold_ms')", name='ck_workout_metric'),
        CheckConstraint('reps >= 0 AND hold_ms >= 0 AND active_ms >= 0', name='ck_workout_nonnegative'),
        CheckConstraint("(metric = 'reps' AND hold_ms = 0) OR (metric = 'hold_ms' AND reps = 0)", name='ck_workout_metric_value'),
    )
    workout_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey('users.user_id', ondelete='CASCADE'), nullable=False, index=True)
    exercise: Mapped[str] = mapped_column(String(32), nullable=False)
    metric: Mapped[str] = mapped_column(String(12), nullable=False)
    reps: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    hold_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    active_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    # Explicit provenance. Never count mobile reports as validated challenge scores.
    source: Mapped[str] = mapped_column(String(32), nullable=False, default='device_reported')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
