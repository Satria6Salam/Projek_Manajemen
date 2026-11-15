"""Ringkasan & analitik pengeluaran untuk layar Beranda dan Kategori."""
from datetime import date, datetime, time, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.timeutils import month_key, month_label, month_range, shift_month
from app.models import Category, Receipt, ReceiptItem, User
from app.schemas.category import CategoryBrief
from app.schemas.dashboard import (
    CategoryBreakdownOut,
    CategorySpendingOut,
    DashboardOut,
    MonthlyPointOut,
    PeriodOut,
    PeriodReceiptOut,
    YearlyPointOut,
)
from app.services import category_service, receipt_service


def _receipt_totals(db: Session, user: User, month: date) -> tuple[float, int]:
    start, end = month_range(month)
    total, count = db.execute(
        select(func.coalesce(func.sum(Receipt.total_amount), 0), func.count(Receipt.id)).where(
            Receipt.user_id == user.id, Receipt.transaction_date >= start, Receipt.transaction_date < end
        )
    ).one()
    return float(total or 0), int(count or 0)


def _category_spending(
    db: Session, user: User, start: datetime, end: datetime
) -> tuple[list[CategorySpendingOut], float]:
    """Pengeluaran per kategori untuk rentang waktu [start, end)."""
    rows = db.execute(
        select(
            ReceiptItem.category_id,
            func.coalesce(func.sum(ReceiptItem.item_price), 0),
            func.count(ReceiptItem.id),
        )
        .join(Receipt, Receipt.id == ReceiptItem.receipt_id)
        .where(Receipt.user_id == user.id, Receipt.transaction_date >= start, Receipt.transaction_date < end)
        .group_by(ReceiptItem.category_id)
    ).all()
    spent = {cid: (float(amount or 0), int(count)) for cid, amount, count in rows}
    grand_total = sum(amount for amount, _ in spent.values())

    categories: list[Category] = category_service.list_active(db)
    known_ids = {c.id for c in categories}
    extra_ids = [cid for cid in spent if cid is not None and cid not in known_ids]
    if extra_ids:  # kategori nonaktif yang masih punya transaksi
        categories += list(db.scalars(select(Category).where(Category.id.in_(extra_ids))))

    def entry(category: Category | None, amount: float, count: int) -> CategorySpendingOut:
        return CategorySpendingOut(
            category=CategoryBrief.model_validate(category) if category else None,
            description=category.description if category else "Barang yang belum diberi kategori",
            amount=round(amount, 2),
            percentage=round(amount / grand_total * 100, 1) if grand_total else 0.0,
            item_count=count,
        )

    result = [entry(c, *spent.get(c.id, (0.0, 0))) for c in categories]
    if None in spent and spent[None][0] > 0:
        result.append(entry(None, *spent[None]))
    order = {c.id: c.sort_order for c in categories}
    result.sort(key=lambda e: (-e.amount, order.get(e.category.id if e.category else None, 999)))
    return result, grand_total


def category_breakdown(db: Session, user: User, month: date) -> CategoryBreakdownOut:
    start, end = month_range(month)
    result, grand_total = _category_spending(db, user, start, end)
    return CategoryBreakdownOut(
        month=month_key(month),
        month_label=month_label(month),
        total_amount=round(grand_total, 2),
        categories=result,
    )


MAX_PERIOD_RECEIPTS = 3000


def period_summary(db: Session, user: User, date_from: date, date_to: date) -> PeriodOut:
    """Ringkasan rentang tanggal bebas (inklusif): total, kategori, dan daftar struk.

    Dipakai halaman Analisis (periode hari / bulan / tahun) dan Anggaran.
    """
    start = datetime.combine(date_from, time.min)
    end = datetime.combine(date_to + timedelta(days=1), time.min)
    categories, _ = _category_spending(db, user, start, end)
    rows = db.execute(
        select(Receipt.id, Receipt.merchant_name, Receipt.transaction_date, Receipt.total_amount)
        .where(Receipt.user_id == user.id, Receipt.transaction_date >= start, Receipt.transaction_date < end)
        .order_by(Receipt.transaction_date.desc(), Receipt.id.desc())
        .limit(MAX_PERIOD_RECEIPTS)
    ).all()
    receipts = [
        PeriodReceiptOut(
            id=rid,
            merchant_name=merchant,
            transaction_date=when,
            total_amount=float(total or 0),
        )
        for rid, merchant, when, total in rows
    ]
    return PeriodOut(
        date_from=date_from,
        date_to=date_to,
        total_spent=round(sum(r.total_amount for r in receipts), 2),
        receipt_count=len(receipts),
        categories=[c for c in categories if c.amount > 0],
        receipts=receipts,
    )


def yearly_trend(db: Session, user: User) -> list[YearlyPointOut]:
    """Total pengeluaran per tahun (semua tahun yang punya struk)."""
    year = func.extract("year", Receipt.transaction_date)
    rows = db.execute(
        select(year, func.coalesce(func.sum(Receipt.total_amount), 0), func.count(Receipt.id))
        .where(Receipt.user_id == user.id, Receipt.transaction_date.is_not(None))
        .group_by(year)
        .order_by(year)
    ).all()
    return [
        YearlyPointOut(year=int(y), total_spent=round(float(total or 0), 2), receipt_count=int(count))
        for y, total, count in rows
        if y is not None
    ]


def monthly_trend(db: Session, user: User, end_month: date, months: int) -> list[MonthlyPointOut]:
    points = []
    for offset in range(months - 1, -1, -1):
        month = shift_month(end_month, -offset)
        total, count = _receipt_totals(db, user, month)
        points.append(
            MonthlyPointOut(month=month_key(month), month_label=month_label(month), total_spent=total, receipt_count=count)
        )
    return points


def dashboard(db: Session, user: User, month: date, recent_limit: int = 5) -> DashboardOut:
    total, count = _receipt_totals(db, user, month)
    previous_total, _ = _receipt_totals(db, user, shift_month(month, -1))
    breakdown = category_breakdown(db, user, month)
    start, end = month_range(month)
    recent = receipt_service.list_receipts(db, user, page=1, page_size=recent_limit, date_from=start, date_to=end)
    change = round((total - previous_total) / previous_total * 100, 1) if previous_total else None
    return DashboardOut(
        month=breakdown.month,
        month_label=breakdown.month_label,
        total_spent=round(total, 2),
        receipt_count=count,
        item_count=sum(c.item_count for c in breakdown.categories),
        previous_month_total=round(previous_total, 2),
        change_percent=change,
        categories=breakdown.categories,
        recent_receipts=recent.items,
    )
