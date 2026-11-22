"""Persisted rooms and accepted, client-reported workout references."""
from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, ForeignKeyConstraint, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class ChallengeRoom(Base):
    __tablename__ = 'challenge_rooms'
    __table_args__ = (
        CheckConstraint("status IN ('waiting','active','completed')", name='ck_room_status'),
        CheckConstraint('max_players BETWEEN 2 AND 12', name='ck_room_max_players'),
    )

    room_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    invite_code: Mapped[str] = mapped_column(String(10), nullable=False, unique=True)
    title: Mapped[str] = mapped_column(String(70), nullable=False)
    owner_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey('users.user_id', ondelete='CASCADE'), nullable=False)
    status: Mapped[str] = mapped_column(String(12), default='waiting', nullable=False)
    max_players: Mapped[int] = mapped_column(Integer, nullable=False, default=8)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class RoomMember(Base):
    __tablename__ = 'room_members'
    room_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey('challenge_rooms.room_id', ondelete='CASCADE'), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey('users.user_id', ondelete='CASCADE'), primary_key=True)
    display_name: Mapped[str] = mapped_column(String(32), nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class RoomSubmission(Base):
    __tablename__ = 'room_submissions'
    __table_args__ = (
        ForeignKeyConstraint(['room_id', 'user_id'], ['room_members.room_id', 'room_members.user_id'], ondelete='CASCADE'),
        UniqueConstraint('workout_id', name='uq_room_submission_workout'),
    )
    submission_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    room_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey('challenge_rooms.room_id', ondelete='CASCADE'), nullable=False, index=True)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    workout_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey('workout_records.workout_id', ondelete='CASCADE'), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
