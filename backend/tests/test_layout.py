"""Penyusunan baris dari posisi kotak teks (foto miring, harga terpisah baris)."""
from app.integrations.ocr.layout import Box, layout_lines
from app.services.receipt_reader import _vote_words


def test_tilted_photo_keeps_price_on_item_line():
    tilt = 0.03
    boxes = []
    for y, name, price in [(100, "Indomie Goreng", "3.500"), (140, "Aqua 600ml", "4.000"), (180, "Teh Botol", "5.000")]:
        boxes.append(Box(y, 10, 200, 20, name))
        boxes.append(Box(y + tilt * 600, 550, 650, 20, price))
    assert layout_lines(boxes).splitlines() == ["Indomie Goreng 3.500", "Aqua 600ml 4.000", "Teh Botol 5.000"]


def test_orphan_price_joins_line_above():
    boxes = [Box(100, 10, 120, 20, "TOTAL"), Box(125, 550, 650, 20, "12.500"), Box(170, 10, 120, 20, "TUNAI")]
    assert layout_lines(boxes).splitlines() == ["TOTAL 12.500", "TUNAI"]


def test_word_vote_takes_known_word_from_other_engine():
    assert _vote_words("Kabel Segar t Keci1", ["Kabel Serabut Kecil"]) == "Kabel Serabut Kecil"
    # Kata yang sudah dikenal tidak diganti.
    assert _vote_words("INDOMIE GORENG", ["1NDOMIE G0RENG"]) == "INDOMIE GORENG"
