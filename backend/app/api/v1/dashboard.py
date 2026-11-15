from datetime import date

from fastapi import APIRouter, Query

from app.api.deps import DB, CurrentUser
from app.core.timeutils import parse_month
from app.core.exceptions import BadRequestError
from app.schemas.dashboard import CategoryBreakdownOut, DashboardOut, MonthlyPointOut, PeriodOut, YearlyPointOut
from app.schemas.model_report import ModelReportOut
from app.schemas.price import PriceHistoryOut
from app.schemas.store import StoreOut
from app.services import dashboard_service, model_report_service, price_service, store_service

router = APIRouter(tags=["Dashboard & Analitik"])
MONTH_QUERY = Query(None, description="Bulan YYYY-MM. Kosong = bulan ini.", examples=["2026-10"])


@router.get("/dashboard", response_model=DashboardOut)
def get_dashboard(db: DB, user: CurrentUser, month: str | None = MONTH_QUERY):
    """Semua data layar **Beranda** dalam satu panggilan."""
    return dashboard_service.dashboard(db, user, parse_month(month))


@router.get("/analytics/categories", response_model=CategoryBreakdownOut)
def category_breakdown(db: DB, user: CurrentUser, month: str | None = MONTH_QUERY):
    """Data layar **Kategori Pengeluaran**: nominal & persentase per kategori."""
    return dashboard_service.category_breakdown(db, user, parse_month(month))


@router.get("/analytics/monthly", response_model=list[MonthlyPointOut])
def monthly_trend(
    db: DB,
    user: CurrentUser,
    month: str | None = Query(None, description="Bulan terakhir (YYYY-MM). Kosong = bulan ini."),
    months: int = Query(6, ge=1, le=24, description="Jumlah bulan ke belakang"),
):
    """Tren total pengeluaran per bulan (untuk grafik)."""
    return dashboard_service.monthly_trend(db, user, parse_month(month), months)


@router.get("/analytics/period", response_model=PeriodOut)
def period_summary(
    db: DB,
    user: CurrentUser,
    date_from: date = Query(..., description="Tanggal awal (inklusif)", examples=["2026-11-01"]),
    date_to: date = Query(..., description="Tanggal akhir (inklusif)", examples=["2026-11-30"]),
):
    """Ringkasan rentang tanggal (hari / bulan / tahun): total, kategori, dan daftar struk."""
    if date_from > date_to:
        raise BadRequestError("date_from tidak boleh setelah date_to.", code="INVALID_DATE_RANGE")
    if (date_to - date_from).days > 366:
        raise BadRequestError("Rentang maksimal 1 tahun.", code="INVALID_DATE_RANGE")
    return dashboard_service.period_summary(db, user, date_from, date_to)


@router.get("/analytics/yearly", response_model=list[YearlyPointOut])
def yearly_trend(db: DB, user: CurrentUser):
    """Total pengeluaran per tahun (untuk tren tahunan)."""
    return dashboard_service.yearly_trend(db, user)


@router.get("/analytics/model", response_model=ModelReportOut)
def model_report(db: DB, user: CurrentUser):
    """Kinerja prediksi kategori menurut koreksi Anda (akurasi, per kategori & sumber)."""
    return model_report_service.report(db, user)


@router.get("/items/price-history", response_model=PriceHistoryOut)
def item_price_history(db: DB, user: CurrentUser, q: str = Query(..., min_length=2, max_length=100)):
    """Riwayat harga satuan barang yang namanya memuat semua kata pada `q`, dibandingkan antar toko."""
    return price_service.price_history(db, user, q)


@router.get("/stores", response_model=list[StoreOut])
def stores(db: DB, user: CurrentUser):
    """Toko tempat Anda berbelanja (alamat dari struk), paling sering dikunjungi lebih dulu."""
    return store_service.list_stores(db, user)
