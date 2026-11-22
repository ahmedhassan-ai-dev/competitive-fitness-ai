"""Create users. Prepared for review; no database execution in Checkpoint 2."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0001_create_users"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("username", sa.String(32, collation="C"), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("user_id"),
        sa.UniqueConstraint("username", name="uq_users_username"),
        sa.CheckConstraint(
            "username ~ '^[A-Za-z0-9_]{3,32}$'", name="ck_users_username_format"
        ),
        sa.CheckConstraint(
            "password_hash LIKE '$argon2id$%'", name="ck_users_password_hash_argon2id"
        ),
    )


def downgrade() -> None:
    # Destructive: requires a separately reviewed rollback decision and backup.
    op.drop_table("users")
