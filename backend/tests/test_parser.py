from datetime import datetime

import pytest

from app.integrations.parser.regex_parser import RegexReceiptParser, parse_money


@pytest.mark.parametrize(
    "text,expected",
    [
        ("22.500", 22500), ("22,500", 22500), ("1.250.000", 1250000), ("22.500,00", 22500),
        ("22,500.00", 22500), ("Rp15.000", 15000), ("15000", 15000), ("abc", None),
    ],
)
def test_parse_money(text, expected):
    assert parse_money(text) == expected


def test_two_line_items_and_text_date():
    text = """ALFAMART
Tgl. 03 Nov 2026 19:05
VITAMIN C 10 TABLET
  2 x 15.000   30.000
AQUA 600ML      4.000
SUBTOTAL       34.000
DISKON         -2.000
TOTAL BELANJA  32.000
"""
    parsed = RegexReceiptParser().parse(text)
    assert parsed.merchant_name == "ALFAMART"
    assert parsed.transaction_date == datetime(2026, 11, 3, 19, 5)
    assert parsed.total_amount == 32000
    assert [(i.name, i.quantity, i.price) for i in parsed.items] == [
        ("VITAMIN C 10 TABLET", 2, 30000),
        ("AQUA 600ML", 1, 4000),
    ]


def test_ignores_payment_lines():
    parsed = RegexReceiptParser().parse("TOKO A\nGULA 1KG 15.000\nTOTAL 15.000\nTUNAI 20.000\nKEMBALI 5.000\n")
    assert len(parsed.items) == 1 and parsed.total_amount == 15000


NUMBERED_RECEIPT = """ELEKTRONIK PLUS
Tanggal : 01-10-2026 15:37
No. Nama Barang Qty Harga Jumlah
Al Headphone Bluetooth al 299.000 299.000
(JBL T510BT)
2 USB Flash Drive 64GB 1 89.000 89.000
(Sandisk)
3 Kabel Data Type-C il 49.000 49.000
Subtotal 437.000
Total 437.000
"""


def test_numbered_rows_and_misread_qty_are_removed_from_names():
    parsed = RegexReceiptParser().parse(NUMBERED_RECEIPT)
    assert [i.name for i in parsed.items] == [
        "Headphone Bluetooth",
        "USB Flash Drive 64GB",
        "Kabel Data Type-C",
    ]
    assert [i.quantity for i in parsed.items] == [1, 1, 1]
    assert [i.price for i in parsed.items] == [299000, 89000, 49000]
    assert parsed.total_amount == 437000


def test_numbered_rows_without_header_when_sequential():
    text = """TOKO MAJU
1. Sabun Mandi 2 5.000 10.000
2. Pasta Gigi 1 12.000 12.000
3. Shampoo Sachet 3 1.000 3.000
TOTAL 25.000
"""
    parsed = RegexReceiptParser().parse(text)
    assert [i.name for i in parsed.items] == ["Sabun Mandi", "Pasta Gigi", "Shampoo Sachet"]
    assert [i.quantity for i in parsed.items] == [2, 1, 3]


def test_leading_quantity_is_not_mistaken_for_row_number():
    text = """WARUNG BU SRI
2 INDOMIE GORENG 7.000
4 TELUR AYAM 10.000
TOTAL 17.000
"""
    parsed = RegexReceiptParser().parse(text)
    # Bukan nomor urut (2, 4 tidak berurutan) -> qty di depan nama, format warung/kafe.
    assert [i.name for i in parsed.items] == ["INDOMIE GORENG", "TELUR AYAM"]
    assert [i.quantity for i in parsed.items] == [2, 4]
    assert [i.unit_price for i in parsed.items] == [3500, 2500]


# --- Regresi dari foto struk nyata (teks hasil OCR) ---------------------------

FRESHMART = """FreshMart
Jl. Melati No. 12, Malang
Tanggal : 01 Oktober 2026
No Nama Barang Qty Harga Total
1 Beras 5kg 1 62.000 62.000
2 Minyak Goreng 1L 1 18.500 18.500
5 Mie Instan (isi 5) il 12.500 12.500
6 Susu UHT 1L 2 15.000 30.000
Subtotal : 123.000
Total 8 123.000
"""

SEJAHTERA_RP = """Toko Sejahtera
Jl. Melati No. 12, Jakarta Selatan
5 Tepung Terigu 1 kg 1 Rp 12.500 Rp 12.500
Tanggal : 02-10-2025
No. Nama Barang Qty Harga Total
1 Beras 5 kg 1 Rp 62.000 Rp 62.000
2 Minyak Goreng 1 L 2 Rp 15.500 Rp 31.000
3 Telur Ayam 1 kg 1 Rp 28.000 Rp 28.000
4 Gula Pasir 1 kg 1 Rp 14.000 Rp 14.000
Subtotal Rp 147.500
Pajak (PPN 11%) Rp 16.225
Total Rp 163.725
"""


def test_header_with_total_column_does_not_hide_items():
    parsed = RegexReceiptParser().parse(FRESHMART)
    assert [i.name for i in parsed.items] == ["Beras 5kg", "Minyak Goreng 1L", "Mie Instan (isi 5)", "Susu UHT 1L"]
    assert parsed.items[-1].quantity == 2 and parsed.total_amount == 123000


def test_separate_rp_tokens_and_out_of_order_rows():
    parsed = RegexReceiptParser().parse(SEJAHTERA_RP)
    assert [i.name for i in parsed.items] == [
        "Tepung Terigu 1 kg", "Beras 5 kg", "Minyak Goreng 1 L", "Telur Ayam 1 kg", "Gula Pasir 1 kg"]
    assert [i.quantity for i in parsed.items] == [1, 1, 2, 1, 1]
    assert sum(i.price for i in parsed.items) == 147500
    assert parsed.total_amount == 163725 and parsed.merchant_address.startswith("Jl. Melati")


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("] Toko Sejahtera", "Toko Sejahtera"), ("�EJ Toko Sejahtera", "Toko Sejahtera"),
     ("UD Sinar Jaya", "UD Sinar Jaya"), ("7-Eleven", "7-Eleven")],
)
def test_merchant_name_cleanup(raw, expected):
    assert RegexReceiptParser().parse(f"{raw}\nBeras 5kg 62.000\nTotal 62.000").merchant_name == expected
