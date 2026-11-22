"""Private, authenticated friendly room API.

Scores are device-reported and UNVERIFIED. A workout can be submitted once.
Each exercise has its own native-unit total; the overall board uses position
points instead of mixing repetitions with milliseconds.
"""
from datetime import datetime, timezone
import secrets
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user
from app.auth.models import User
from app.db import get_session
from app.rooms.models import ChallengeRoom, RoomMember, RoomSubmission
from app.workouts.catalog import CATALOG
from app.workouts.models import WorkoutRecord

router = APIRouter(prefix='/api/v1/rooms', tags=['rooms'])
UserDep = Annotated[User, Depends(get_current_user)]
SessionDep = Annotated[Session, Depends(get_session)]
ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
EXERCISES = tuple(CATALOG)


class CreateRoomRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    title: str = Field(min_length=3, max_length=70, pattern=r'^\S(?:.*\S)?$')
    max_players: int = Field(default=8, ge=2, le=12)


class JoinRoomRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    invite_code: str = Field(min_length=10, max_length=10, pattern='^[A-Za-z0-9]+$')


class SubmitWorkoutRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    workout_id: UUID


class ExerciseScore(BaseModel):
    exercise: str
    metric: Literal['reps', 'hold_ms']
    total: int
    sessions: int
    rank: int | None


class MemberScore(BaseModel):
    user_id: UUID
    display_name: str
    total_points: int
    overall_rank: int
    exercises: list[ExerciseScore]


class RoomView(BaseModel):
    room_id: UUID
    invite_code: str
    title: str
    status: Literal['waiting', 'active', 'completed']
    owner_id: UUID
    max_players: int
    created_at: datetime
    started_at: datetime | None
    finished_at: datetime | None
    score_source: Literal['device_reported_unverified'] = 'device_reported_unverified'
    members: list[MemberScore]


class RoomSummary(BaseModel):
    room_id: UUID
    title: str
    invite_code: str
    status: str
    member_count: int


def fail(code: int, message: str) -> None:
    raise HTTPException(status_code=code, detail=message)


def locked_room(session: Session, room_id: UUID) -> ChallengeRoom:
    room = session.scalar(select(ChallengeRoom).where(ChallengeRoom.room_id == room_id).with_for_update())
    if room is None:
        fail(404, 'Room not found')
    return room


def require_member(session: Session, room_id: UUID, user_id: UUID) -> None:
    member = session.get(RoomMember, (room_id, user_id))
    if member is None:
        # Do not disclose a private room to an unrelated account.
        fail(404, 'Room not found')


def snapshot(session: Session, room: ChallengeRoom) -> RoomView:
    members = session.scalars(select(RoomMember).where(RoomMember.room_id == room.room_id)
                              .order_by(RoomMember.joined_at, RoomMember.display_name)).all()
    submissions = session.execute(
        select(RoomSubmission.user_id, WorkoutRecord.exercise, WorkoutRecord.metric,
               WorkoutRecord.reps, WorkoutRecord.hold_ms)
        .join(WorkoutRecord, RoomSubmission.workout_id == WorkoutRecord.workout_id)
        .where(RoomSubmission.room_id == room.room_id)
    ).all()
    totals = {member.user_id: {exercise: 0 for exercise in EXERCISES} for member in members}
    sessions = {member.user_id: {exercise: 0 for exercise in EXERCISES} for member in members}
    for user_id, exercise, metric, reps, hold_ms in submissions:
        if user_id in totals and exercise in CATALOG:
            totals[user_id][exercise] += hold_ms if metric == 'hold_ms' else reps
            sessions[user_id][exercise] += 1

    # Competition ranking: equal positive totals get equal rank; zero doesn't score.
    per_exercise_rank: dict[str, dict[UUID, int]] = {exercise: {} for exercise in EXERCISES}
    points: dict[UUID, int] = {member.user_id: 0 for member in members}
    n = len(members)
    for exercise in EXERCISES:
        for member in members:
            total = totals[member.user_id][exercise]
            if total > 0:
                rank = 1 + sum(1 for candidate in members if totals[candidate.user_id][exercise] > total)
                per_exercise_rank[exercise][member.user_id] = rank
                points[member.user_id] += n - rank + 1

    ordered = sorted(members, key=lambda member: (-points[member.user_id], member.display_name.lower(), str(member.user_id)))
    results = []
    for member in ordered:
        score = points[member.user_id]
        overall_rank = 1 + sum(1 for other in members if points[other.user_id] > score)
        results.append(MemberScore(
            user_id=member.user_id, display_name=member.display_name,
            total_points=score, overall_rank=overall_rank,
            exercises=[ExerciseScore(exercise=exercise, metric=CATALOG[exercise].metric,
                                     total=totals[member.user_id][exercise],
                                     sessions=sessions[member.user_id][exercise],
                                     rank=per_exercise_rank[exercise].get(member.user_id))
                       for exercise in EXERCISES],
        ))
    return RoomView(
        room_id=room.room_id, invite_code=room.invite_code, title=room.title,
        status=room.status, owner_id=room.owner_id, max_players=room.max_players,
        created_at=room.created_at, started_at=room.started_at,
        finished_at=room.finished_at, members=results,
    )


@router.post('', status_code=201, response_model=RoomView)
def create_room(body: CreateRoomRequest, user: UserDep, session: SessionDep):
    # The auth dependency may already have opened a transaction by loading the
    # user. Do not use session.begin() after that implicit SELECT.
    room = ChallengeRoom(
        invite_code=''.join(secrets.choice(ALPHABET) for _ in range(10)),
        title=body.title, owner_id=user.user_id, max_players=body.max_players,
    )
    session.add(room)
    session.flush()
    session.add(RoomMember(room_id=room.room_id, user_id=user.user_id, display_name=user.username))
    session.commit()
    return snapshot(session, room)


@router.post('/join', response_model=RoomView)
def join_room(body: JoinRoomRequest, user: UserDep, session: SessionDep):
    room = session.scalar(select(ChallengeRoom).where(ChallengeRoom.invite_code == body.invite_code.upper()).with_for_update())
    if room is None:
        fail(404, 'Invite code not found')
    if session.get(RoomMember, (room.room_id, user.user_id)) is None:
        if room.status != 'waiting':
            fail(409, 'Room has already started')
        count = len(session.scalars(select(RoomMember).where(RoomMember.room_id == room.room_id)).all())
        if count >= room.max_players:
            fail(409, 'Room is full')
        session.add(RoomMember(room_id=room.room_id, user_id=user.user_id, display_name=user.username))
    session.commit()
    return snapshot(session, room)


@router.get('', response_model=list[RoomSummary])
def my_rooms(user: UserDep, session: SessionDep):
    pairs = session.execute(
        select(ChallengeRoom, RoomMember).join(RoomMember, ChallengeRoom.room_id == RoomMember.room_id)
        .where(RoomMember.user_id == user.user_id).order_by(ChallengeRoom.created_at.desc()).limit(100)
    ).all()
    return [RoomSummary(room_id=room.room_id, title=room.title,
                        invite_code=room.invite_code, status=room.status,
                        member_count=session.query(RoomMember).filter(RoomMember.room_id == room.room_id).count())
            for room, _ in pairs]


@router.get('/{room_id}', response_model=RoomView)
def get_room(room_id: UUID, user: UserDep, session: SessionDep):
    require_member(session, room_id, user.user_id)
    room = session.get(ChallengeRoom, room_id)
    return snapshot(session, room)


@router.post('/{room_id}/start', response_model=RoomView)
def start_room(room_id: UUID, user: UserDep, session: SessionDep):
    room = locked_room(session, room_id)
    require_member(session, room_id, user.user_id)
    if room.owner_id != user.user_id:
        fail(403, 'Only the owner can start the room')
    if room.status != 'waiting':
        fail(409, 'Room is not waiting')
    members = session.scalars(select(RoomMember).where(RoomMember.room_id == room_id)).all()
    if len(members) < 2:
        fail(409, 'At least two players are required')
    room.status = 'active'
    room.started_at = datetime.now(timezone.utc)
    session.commit()
    return snapshot(session, room)


@router.post('/{room_id}/finish', response_model=RoomView)
def finish_room(room_id: UUID, user: UserDep, session: SessionDep):
    room = locked_room(session, room_id)
    require_member(session, room_id, user.user_id)
    if room.owner_id != user.user_id:
        fail(403, 'Only the owner can finish the room')
    if room.status != 'active':
        fail(409, 'Room is not active')
    room.status = 'completed'
    room.finished_at = datetime.now(timezone.utc)
    session.commit()
    return snapshot(session, room)


@router.post('/{room_id}/submissions', response_model=RoomView)
def submit_workout(room_id: UUID, body: SubmitWorkoutRequest, user: UserDep, session: SessionDep):
    room = locked_room(session, room_id)
    require_member(session, room_id, user.user_id)
    workout = session.get(WorkoutRecord, body.workout_id)
    if workout is None or workout.user_id != user.user_id:
        fail(404, 'Workout not found')
    already = session.scalar(select(RoomSubmission).where(RoomSubmission.workout_id == body.workout_id))
    if already is not None:
        if already.room_id != room_id or already.user_id != user.user_id:
            fail(409, 'Workout already submitted to another room')
        return snapshot(session, room)
    if room.status != 'active':
        fail(409, 'Room is not active')
    if room.started_at is None:
        fail(409, 'Room has not started')
    start = room.started_at.replace(tzinfo=timezone.utc) if room.started_at.tzinfo is None else room.started_at
    created = workout.created_at.replace(tzinfo=timezone.utc) if workout.created_at.tzinfo is None else workout.created_at
    if created < start:
        fail(409, 'Workout must be recorded after room start')
    session.add(RoomSubmission(room_id=room_id, workout_id=body.workout_id, user_id=user.user_id))
    session.commit()
    return snapshot(session, room)
