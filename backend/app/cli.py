import argparse
import logging

from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.user import User
from app.services.commercial import add_audit, ensure_founder_plan

logger = logging.getLogger("zedbiz.cli")


def seed_founder_plan() -> int:
    with SessionLocal() as db:
        plan, created = ensure_founder_plan(db)
        print(f"Founder plan {'created' if created else 'already exists'}: {plan.code}")
    return 0


def promote_admin(email: str, confirmed: bool) -> int:
    normalized_email = email.strip().lower()
    if not confirmed:
        answer = input(f"Promote existing user {normalized_email} to platform admin? [y/N] ")
        if answer.strip().lower() not in {"y", "yes"}:
            print("Promotion cancelled")
            return 1
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.email == normalized_email))
        if user is None:
            print("User does not exist")
            return 2
        if user.is_platform_admin:
            print("User is already a platform administrator")
            return 0
        user.is_platform_admin = True
        add_audit(
            db,
            actor_user_id=user.id,
            business_id=None,
            action="platform_admin.promoted",
            entity_type="user",
            entity_id=user.id,
            metadata={"method": "server_cli"},
        )
        db.commit()
        logger.warning("Platform administrator promoted via server CLI: user_id=%s", user.id)
        print(f"Promoted {normalized_email} to platform administrator")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="ZedBiz server management commands")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("seed-founder-plan", help="Create the Founder plan when absent")
    promote = subparsers.add_parser("promote-admin", help="Promote an existing user")
    promote.add_argument("--email", required=True)
    promote.add_argument("--yes", action="store_true", help="Skip interactive confirmation")
    args = parser.parse_args()
    if args.command == "seed-founder-plan":
        return seed_founder_plan()
    return promote_admin(args.email, args.yes)


if __name__ == "__main__":
    raise SystemExit(main())
