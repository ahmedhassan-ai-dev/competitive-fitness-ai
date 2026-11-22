from math import cos, radians, sin
from uuid import UUID

import pytest
from pydantic import ValidationError

from exercise_engine import ReferenceEngine
from packages.contracts.v1.models import ExerciseType, Landmark, PoseFrame, RepEvent

SESSION = UUID("00000000-0000-4000-8000-000000000002")


def frame(timestamp, angle, exercise=ExerciseType.SQUAT, confidence=0.95):
    names = (
        ("hip", "knee", "ankle")
        if exercise == ExerciseType.SQUAT
        else ("shoulder", "elbow", "wrist")
    )
    points = (
        (0.8, 0.5),
        (0.5, 0.5),
        (0.5 + 0.3 * cos(radians(angle)), 0.5 + 0.3 * sin(radians(angle))),
    )
    return PoseFrame(
        timestamp_ms=timestamp,
        landmarks={
            name: Landmark(x=x, y=y, confidence=confidence)
            for name, (x, y) in zip(names, points)
        },
    )


def run(exercise, angles):
    engine = ReferenceEngine(SESSION, exercise)
    outputs = [
        engine.process(frame(i * 100, angle, exercise))
        for i, angle in enumerate(angles)
    ]
    return engine, [rep for output in outputs for rep in output.reps]


@pytest.mark.parametrize("exercise", list(ExerciseType))
def test_complete_cycles_are_deterministic_and_contract_valid(exercise):
    angles = [175, 175, 120, 70, 70, 120, 175, 175, 70, 70, 175, 175]
    engine, reps = run(exercise, angles)
    assert len(reps) == 2
    assert [r.sequence for r in reps] == [1, 2]
    assert [(r.started_at_ms, r.ended_at_ms) for r in reps] == [(100, 700), (700, 1100)]
    assert reps == run(exercise, angles)[1]
    for rep in reps:
        assert RepEvent.model_validate_json(rep.model_dump_json()) == rep
        assert rep.exercise == exercise
    engine.reset()
    assert engine.sequence == 2
    with pytest.raises(ValueError, match="increase"):
        engine.process(frame(1100, 175, exercise))


@pytest.mark.parametrize("exercise", list(ExerciseType))
@pytest.mark.parametrize(
    "angles",
    [
        [175] * 20,
        [70] * 20,
        [175, 70] * 10,
        [175, 175, 70, 120, 175, 175],
        [70, 70, 175, 175],
        [175, 175, 120, 120, 175, 175],
        [175, 175, 70, 70, 120, 120],
    ],
)
def test_holds_jitter_partial_and_bottom_start_do_not_count(exercise, angles):
    assert run(exercise, angles)[1] == []


@pytest.mark.parametrize("exercise", list(ExerciseType))
@pytest.mark.parametrize(
    "interruption", ["missing", "low", "gap", "degenerate", "reset"]
)
def test_tracking_loss_requires_rearming(exercise, interruption):
    engine = ReferenceEngine(SESSION, exercise)
    for i, angle in enumerate([175, 175, 70, 70]):
        engine.process(frame(i * 100, angle, exercise))
    timestamp = 400
    if interruption == "missing":
        output = engine.process(PoseFrame(timestamp_ms=timestamp, landmarks={}))
        assert output.feedback[0].code == "low_confidence"
    elif interruption == "low":
        assert engine.process(frame(timestamp, 175, exercise, 0.79)).feedback
    elif interruption == "degenerate":
        bad = frame(timestamp, 175, exercise)
        bad = bad.model_copy(
            update={
                "landmarks": dict.fromkeys(
                    bad.landmarks, Landmark(x=0.5, y=0.5, confidence=1)
                )
            }
        )
        assert engine.process(bad).feedback
    elif interruption == "reset":
        engine.reset()
    else:
        timestamp = 1000
        assert not engine.process(frame(timestamp, 175, exercise)).reps
    for offset in (100, 200, 300):
        assert not engine.process(frame(timestamp + offset, 175, exercise)).reps


def test_timestamp_rejection_preserves_state():
    engine = ReferenceEngine(SESSION, ExerciseType.SQUAT)
    engine.process(frame(100, 175))
    for timestamp in (100, 99):
        with pytest.raises(ValueError, match="increase"):
            engine.process(frame(timestamp, 70))
    engine.process(frame(200, 175))
    assert engine.phase == "top"


def test_confidence_boundary_and_minimum_over_cycle():
    engine = ReferenceEngine(SESSION, ExerciseType.SQUAT)
    reps = []
    for i, angle in enumerate([175, 175, 70, 70, 175, 175]):
        reps.extend(
            engine.process(
                frame(i * 100, angle, confidence=0.8 if i == 2 else 0.95)
            ).reps
        )
    assert len(reps) == 1
    assert reps[0].confidence == 0.8


@pytest.mark.parametrize("value", [float("nan"), float("inf"), -0.1, 1.1])
def test_invalid_coordinates_rejected(value):
    with pytest.raises(ValidationError):
        Landmark(x=value, y=0.5, confidence=0.95)


def test_hold_uses_elapsed_time_not_frame_count():
    engine = ReferenceEngine(SESSION, ExerciseType.SQUAT)
    for timestamp in range(100):
        engine.process(frame(timestamp, 175))
    assert engine.phase == "unarmed"
    engine.process(frame(100, 175))
    assert engine.phase == "top"


@pytest.mark.parametrize(
    "exercise,top,bottom",
    [
        (ExerciseType.SQUAT, 160, 100),
        (ExerciseType.PUSH_UP, 155, 90),
    ],
)
def test_exercise_thresholds_and_dead_band(exercise, top, bottom):
    assert (
        len(run(exercise, [top + 0.1] * 2 + [bottom - 0.1] * 2 + [top + 0.1] * 2)[1])
        == 1
    )
    assert not run(exercise, [top - 0.1] * 2 + [bottom - 0.1] * 2 + [top + 0.1] * 2)[1]
    assert not run(exercise, [top + 0.1] * 2 + [bottom + 0.1] * 2 + [top + 0.1] * 2)[1]
