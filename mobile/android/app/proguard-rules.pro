# ML Kit Text Recognition mereferensikan model bahasa opsional (Cina, Jepang, Korea, Devanagari)
# yang tidak dipakai STRUKKU (hanya huruf Latin). Abaikan agar build release (R8) tidak gagal.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
