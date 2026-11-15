"""Evaluasi kinerja prediksi kategori berdasarkan koreksi pengguna.

Barang dianggap "diprediksi benar" bila kategori prediksi sistem tidak diubah
pengguna, dan "salah" bila pengguna mengoreksinya (is_user_corrected).
"""
from collections import defaultdict

from sqlalchemy import select
from sqlalchemy.orm import Session, aliased

from app.core.timeutils import month_key, month_label, shift_month, local_now
from app.integrations.providers import get_id_model
from app.models import Category, Receipt, ReceiptItem, User
from app.schemas.model_report import (
    CategoryAccuracyOut,
    CorrectionOut,
    ModelReportOut,
    MonthlyAccuracyOut,
    SourceAccuracyOut,
)

SOURCE_LABELS = {
    "user_history": "Riwayat koreksi Anda",
    "keyword_rules": "Kata kunci",
    "id_model": "Model Indonesia (TF-IDF + NB)",
    "ml_model": "Model BigBasket (TF-IDF + NB)",
}


def _acc(correct: int, total: int) -> float | None:
    return round(correct / total * 100, 1) if total else None


def report(db: Session, user: User, months: int = 6) -> ModelReportOut:
    predicted = aliased(Category)
    final = aliased(Category)
    rows = db.execute(
        select(
            ReceiptItem.item_name,
            ReceiptItem.is_user_corrected,
            ReceiptItem.prediction_source,
            predicted.name,
            predicted.display_name,
            final.display_name,
            final.name,
            Receipt.transaction_date,
        )
        .join(Receipt, Receipt.id == ReceiptItem.receipt_id)
        .join(predicted, predicted.id == ReceiptItem.predicted_category_id)
        .outerjoin(final, final.id == ReceiptItem.category_id)
        .where(Receipt.user_id == user.id)
    ).all()

    total = len(rows)
    corrected = sum(1 for r in rows if r[1])

    by_cat: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    by_source: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    by_month: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    fixes: dict[tuple[str, str, str], int] = defaultdict(int)
    for name, is_corrected, source, pred_key, pred_label, final_label, final_key, when in rows:
        pred_label = pred_label or pred_key.replace("_", " ")
        final_label = final_label or (final_key.replace("_", " ") if final_key else None)
        ok = 0 if is_corrected else 1
        by_cat[pred_label][0] += 1
        by_cat[pred_label][1] += ok
        src = source or "lainnya"
        by_source[src][0] += 1
        by_source[src][1] += ok
        if when is not None:
            mk = month_key(when.date())
            by_month[mk][0] += 1
            by_month[mk][1] += ok
        if is_corrected:
            fixes[(" ".join(name.upper().split()), pred_label, final_label or "-")] += 1

    this_month = local_now().date().replace(day=1)
    trend = []
    for offset in range(months - 1, -1, -1):
        m = shift_month(this_month, -offset)
        n, ok = by_month.get(month_key(m), [0, 0])
        trend.append(MonthlyAccuracyOut(month=month_key(m), month_label=month_label(m), items=n, accuracy=_acc(ok, n)))

    model = get_id_model()
    return ModelReportOut(
        total_items=total,
        corrected_items=corrected,
        accuracy=_acc(total - corrected, total),
        categories=sorted(
            (CategoryAccuracyOut(category=k, items=v[0], corrected=v[0] - v[1], accuracy=_acc(v[1], v[0]))
             for k, v in by_cat.items()),
            key=lambda c: -c.items,
        ),
        sources=sorted(
            (SourceAccuracyOut(source=k, label=SOURCE_LABELS.get(k, k), items=v[0], accuracy=_acc(v[1], v[0]))
             for k, v in by_source.items()),
            key=lambda s: -s.items,
        ),
        top_corrections=[
            CorrectionOut(item_name=k[0], predicted=k[1], corrected_to=k[2], count=c)
            for k, c in sorted(fixes.items(), key=lambda kv: -kv[1])[:10]
        ],
        monthly=trend,
        learned_corrections=model.learned_count,
        training_samples=model.sample_count,
        trained_at=model.trained_at,
    )
