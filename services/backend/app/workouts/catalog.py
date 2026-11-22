"""One exercise catalog used by the workout API; challenge eligibility stays separate."""
from typing import Literal
from pydantic import BaseModel, ConfigDict

Metric = Literal['reps', 'hold_ms']

class ExerciseDefinition(BaseModel):
    model_config = ConfigDict(frozen=True)
    id: str
    label: str
    metric: Metric
    suggested_view: str
    challenge_enabled: bool = False

EXERCISES = (
    ExerciseDefinition(id='squat', label='Squat', metric='reps', suggested_view='front or diagonal'),
    ExerciseDefinition(id='push_up', label='Push-up', metric='reps', suggested_view='side or diagonal'),
    ExerciseDefinition(id='jumping_jack', label='Jumping Jack', metric='reps', suggested_view='front'),
    ExerciseDefinition(id='plank', label='Plank', metric='hold_ms', suggested_view='side'),
)
CATALOG = {item.id: item for item in EXERCISES}
