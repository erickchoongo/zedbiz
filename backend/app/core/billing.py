import calendar
from datetime import datetime

from app.core.time import ensure_utc


def add_calendar_month(value: datetime) -> datetime:
    """Advance one calendar month, preserving end-of-month billing anchors."""
    value = ensure_utc(value)
    source_last_day = calendar.monthrange(value.year, value.month)[1]
    target_year = value.year + (1 if value.month == 12 else 0)
    target_month = 1 if value.month == 12 else value.month + 1
    target_last_day = calendar.monthrange(target_year, target_month)[1]
    target_day = target_last_day if value.day == source_last_day else min(value.day, target_last_day)
    return value.replace(year=target_year, month=target_month, day=target_day)
