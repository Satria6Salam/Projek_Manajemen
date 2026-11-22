"""Regresi: format struk yang berbeda dan salah baca OCR yang umum."""
from app.integrations.parser.regex_parser import RegexReceiptParser, confusion_variants, normalize_line


def parse(text: str):
    return RegexReceiptParser().parse(text)


def test_alfamart_name_then_qty_line_with_comma_thousands():
    r = parse("""ALFAMART
JL. SOEKARNO HATTA NO.9 MALANG
22.11.2026-14:05 2.1.37 A1/KSR01
TEH BTL SOSRO 450ML
2 x 5,200 10,400
ABC SMBL ASLI 335
2 xX 12,700 25,400
TOTAL ITEM 2
TOTAL BELANJA 35,800
TUNAI 50,000
KEMBALIAN 14,200
""")
    assert [(i.name, i.quantity, i.price) for i in r.items] == [
        ("TEH BTL SOSRO 450ML", 2, 10400), ("ABC SMBL ASLI 335", 2, 25400)]
    assert r.total_amount == 35800
    assert r.transaction_date.strftime("%Y-%m-%d %H:%M") == "2026-11-22 14:05"


def test_rp_equals_format():
    r = parse("""TOKO BERKAH JAYA
Jl. Mawar No. 3, Blitar
Tanggal : 22/11/2026 08:41
Kecap Bango 520ml
1 pcs x Rp 24.800 = Rp 24.800
Kopi Kapal Api 165g
2 pcs x Rp 13.000 = Rp 26.000
Total : Rp 50.800
Bayar : Rp 60.000
Kembali : Rp 9.200
""")
    assert [(i.name, i.quantity, i.unit_price, i.price) for i in r.items] == [
        ("Kecap Bango 520ml", 1, 24800, 24800), ("Kopi Kapal Api 165g", 2, 13000, 26000)]
    assert r.total_amount == 50800


def test_cafe_quantity_in_front_and_subtotal_with_charges():
    r = parse("""KOPI SENJA
Jl. Ijen No. 21, Malang
Sab, 22 Nov 2026 19:03
2 Air Mineral 16.000
1 Americano 22.000
Subtotal 38.000
Service 5% 1.900
PB1 10% 3.990
Grand Total 43.890
""")
    assert [(i.name, i.quantity, i.price) for i in r.items] == [("Air Mineral", 2, 16000), ("Americano", 1, 22000)]
    assert r.subtotal_amount == 38000 and r.total_amount == 43890 and r.has_charges


def test_size_number_at_end_of_name_is_not_quantity():
    r = parse("WARUNG BU SRI\nMinyak Kayu Putih 60 21.500\nJUMLAH 21.500\n")
    assert r.items[0].quantity == 1
    assert r.items[0].name == "Minyak Kayu Putih 60"


def test_split_numbers_and_decimals_are_joined():
    assert normalize_line("TOTAL 84, 300") == "TOTAL 84,300"
    assert normalize_line("TOTAL 49 .500,00") == "TOTAL 49.500,00"
    assert normalize_line("Antangin 3 4.000,00 12.000, 00") == "Antangin 3 4.000,00 12.000,00"
    assert normalize_line("Telp. (@341) 58O123") == "Telp. (0341) 580123"


def test_one_misread_digit_is_fixed_by_subtotal():
    r = parse("""KOPI SENJA
2 Air Mineral 16.000
2 Croissant Butter 144.000
Subtotal 60.000
PB1 10% 6.000
Grand Total 66.000
""")
    assert [i.price for i in r.items] == [16000, 44000]
    assert r.corrections


def test_two_misread_digits_fixed_with_confusable_pairs():
    r = parse("""KOPI SENJA
1 Matcha Latte 28.088
1 Roti Bakar Coklat 13.000
1 Es Teh Manis 8.000
Subtotal 54.000
Grand Total 54.000
""")
    assert [i.price for i in r.items] == [28000, 18000, 8000]


def test_misread_total_is_fixed_when_items_agree():
    r = parse("""APOTEK SEHAT
Paracetamol 500mg 1 5.000,00 5.000,00
Vitamin C 1000mg 1 35.000,00 35.000,00
TOTAL 49.000,00
TUNAI 40.000,00
""")
    assert r.total_amount == 40000


def test_qty_line_misread_when_unit_equals_total():
    r = parse("No Nama Barang Qty Harga Total\n1 Beras 5kg 4, 62.000 62.000\nTotal 62.000\n")
    assert (r.items[0].quantity, r.items[0].price) == (1, 62000)


def test_time_line_is_not_an_item():
    r = parse("Toko A\nWaktu 1024\nGula 1kg 16.000\nTotal 16.000\n")
    assert [i.name for i in r.items] == ["Gula 1kg"]


def test_merchant_name_split_over_two_lines():
    r = parse("J Toko\nSejahtera\nBelanja Hemat, Hidup Lebih Baik\nJl. Melati No. 12, Malang\nGula 16.000\nTotal 16.000")
    assert r.merchant_name == "Toko Sejahtera"


def test_address_is_not_used_as_merchant():
    r = parse("JL, Melati No. 12, Malang\nTelp. 0341-555123\nGula 16.000\nTotal 16.000")
    assert r.merchant_name is None or "melati" not in r.merchant_name.lower()


def test_confusion_variants():
    v = confusion_variants(28088)
    assert v[28000] == 2 and v[28080] == 1


def test_plu_code_before_name_is_removed():
    r = parse("SUPERINDO\n8994330348 TEH BTL SOSRO 450ML\n1 @ 5,200 5,200\nTOTAL 5,200\n")
    assert r.items[0].name == "TEH BTL SOSRO 450ML"
