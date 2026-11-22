"""Add client-reported workout history (not validated challenge scores)."""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0002_workout_records"
down_revision = "0001_create_users"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "workout_records",
        sa.Column("workout_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("exercise", sa.String(32), nullable=False),
        sa.Column("metric", sa.String(12), nullable=False),
        sa.Column("reps", sa.Integer(), nullable=False),
        sa.Column("hold_ms", sa.Integer(), nullable=False),
        sa.Column("active_ms", sa.Integer(), nullable=False),
        sa.Column("source", sa.String(32), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("workout_id"),
        sa.ForeignKeyConstraint(["user_id"], ["users.user_id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "exercise IN ('squat','push_up','jumping_jack','plank')",
            name="ck_workout_exercise",
        ),
        sa.CheckConstraint("metric IN ('reps','hold_ms')", name="ck_workout_metric"),
        sa.CheckConstraint(
            "reps >= 0 AND hold_ms >= 0 AND active_ms >= 0",
            name="ck_workout_nonnegative",
        ),
        sa.CheckConstraint(
            "(metric = 'reps' AND hold_ms = 0) OR (metric = 'hold_ms' AND reps = 0)",
            name="ck_workout_metric_value",
        ),
    )
    op.create_index("ix_workout_records_user_id", "workout_records", ["user_id"])


def downgrade() -> None:
    # Destroys all workout history: require a backup and separate approval.
    op.drop_index("ix_workout_records_user_id", table_name="workout_records")
    op.drop_table("workout_records")
