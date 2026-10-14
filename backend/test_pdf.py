import pymupdf
from pathlib import Path

pdf_path = "tes.pdf"
output_dir = Path("hasil_gambar")
output_dir.mkdir(exist_ok=True)

with pymupdf.open(pdf_path) as doc:
    for page_number, page in enumerate(doc, start=1):
        print(f"Halaman {page_number}: {len(page.get_images())} gambar terdeteksi")
        for image_number, image_info in enumerate(page.get_images(), start=1):
            xref = image_info[0]
            image_data = doc.extract_image(xref)
            extension = image_data["ext"]
            image_bytes = image_data["image"]
            image_path = output_dir / f"halaman_{page_number}_gambar_{image_number}.{extension}"
            image_path.write_bytes(image_bytes)
            print(f" Tersimpan: {image_path}")