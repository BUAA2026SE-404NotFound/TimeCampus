import os
import tempfile
from pathlib import Path

from PIL import Image, ImageOps

INPUT_ROOT = Path(".")  # 递归处理的根目录
MAX_SIZE_KB = 300  # 最大文件大小（KB）
DEFAULT_QUALITY = 85  # 起始质量
MIN_QUALITY = 35  # 最低质量
QUALITY_STEP = 5  # 每次降低的质量
RESIZE_STEP = 0.9  # 降到最低质量仍超限时，每轮缩小比例
# =================================================================

MAX_SIZE_BYTES = MAX_SIZE_KB * 1024
SUPPORTED_FORMATS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tiff"}
JPEG_FORMATS = {".jpg", ".jpeg"}


def to_rgb_image(img):
    """
    将各种图片模式转为 JPEG 可保存的 RGB；透明背景使用白色填充。
    """
    img = ImageOps.exif_transpose(img)

    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        img = img.convert("RGBA")
        background = Image.new("RGBA", img.size, (255, 255, 255, 255))
        background.alpha_composite(img)
        return background.convert("RGB")

    return img.convert("RGB")


def write_jpeg(img, output_path, quality):
    img.save(
        output_path,
        "JPEG",
        quality=quality,
        optimize=True,
        progressive=True,
    )


def save_with_size_limit(img, output_path, max_size):
    """
    先逐步降低 JPEG 质量；若仍超出 300KB，再按比例缩小图片尺寸。
    """
    working_img = to_rgb_image(img)
    quality = DEFAULT_QUALITY

    while True:
        while quality >= MIN_QUALITY:
            write_jpeg(working_img, output_path, quality)
            if output_path.stat().st_size <= max_size:
                return quality, working_img.size
            quality -= QUALITY_STEP

        width, height = working_img.size
        next_size = (
            max(1, int(width * RESIZE_STEP)),
            max(1, int(height * RESIZE_STEP)),
        )
        if next_size == working_img.size:
            return quality, working_img.size

        working_img = working_img.resize(next_size, Image.Resampling.LANCZOS)
        quality = DEFAULT_QUALITY


def compress_image(file_path):
    ext = file_path.suffix.lower()
    output_path = file_path if ext in JPEG_FORMATS else file_path.with_suffix(".jpg")

    if output_path == file_path and file_path.stat().st_size <= MAX_SIZE_BYTES:
        size_kb = file_path.stat().st_size / 1024
        print(f"跳过: {file_path} | 已小于 {MAX_SIZE_KB}KB | 大小: {size_kb:.1f}KB")
        return

    temp_file = None
    try:
        with Image.open(file_path) as img:
            with tempfile.NamedTemporaryFile(
                delete=False,
                suffix=".jpg",
                dir=str(output_path.parent),
            ) as tmp:
                temp_file = Path(tmp.name)

            final_quality, final_size = save_with_size_limit(
                img, temp_file, MAX_SIZE_BYTES
            )
            os.replace(temp_file, output_path)

            size_kb = output_path.stat().st_size / 1024
            print(
                f"完成: {file_path} -> {output_path} | "
                f"质量: {final_quality} | 尺寸: {final_size[0]}x{final_size[1]} | "
                f"大小: {size_kb:.1f}KB"
            )
    except Exception as exc:
        if temp_file and temp_file.exists():
            temp_file.unlink()
        print(f"失败: {file_path} | 错误: {exc}")


def main():
    root = INPUT_ROOT.resolve()
    total = 0

    for file_path in root.rglob("*"):
        if not file_path.is_file():
            continue
        if file_path.name == Path(__file__).name:
            continue
        if file_path.suffix.lower() not in SUPPORTED_FORMATS:
            continue

        total += 1
        compress_image(file_path)

    print(f"\n全部处理完成，共扫描图片 {total} 张。")


if __name__ == "__main__":
    main()
