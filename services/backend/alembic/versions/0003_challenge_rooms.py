"""Private friendly multiplayer rooms, memberships and once-only workout submissions."""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0003_challenge_rooms"
down_revision = "0002_workout_records"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "challenge_rooms",
        sa.Column("room_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("invite_code", sa.String(10), nullable=False, unique=True),
        sa.Column("title", sa.String(70), nullable=False),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.user_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("status", sa.String(12), nullable=False),
        sa.Column("max_players", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("started_at", sa.DateTime(timezone=True)),
        sa.Column("finished_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint(
            "status IN ('waiting','active','completed')", name="ck_room_status"
        ),
        sa.CheckConstraint("max_players BETWEEN 2 AND 12", name="ck_room_max_players"),
    )
    op.create_table(
        "room_members",
        sa.Column(
            "room_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("challenge_rooms.room_id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.user_id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("display_name", sa.String(32), nullable=False),
        sa.Column(
            "joined_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_table(
        "room_submissions",
        sa.Column("submission_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "room_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("challenge_rooms.room_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "workout_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("workout_records.workout_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["room_id", "user_id"],
            ["room_members.room_id", "room_members.user_id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("workout_id", name="uq_room_submission_workout"),
    )
    op.create_index("ix_room_submissions_room_id", "room_submissions", ["room_id"])


def downgrade() -> None:
    raise RuntimeError(
        "Destructive room migration downgrade is intentionally disabled. Restore from a reviewed backup."
    )
