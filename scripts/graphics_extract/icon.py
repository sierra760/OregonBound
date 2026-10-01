"""Separate monochrome ICON bitmap, drawn with srcOr by CD CODE1."""
from PIL import Image
from .models import DecodeDiagnostic, DecodeImage, DecodeStatus, ResourceInfo


def decode_icon(resource: ResourceInfo, data: bytes) -> list[DecodeImage]:
    if len(data) != 128:
        return [DecodeImage(resource=resource, status=DecodeStatus.FAILED,
                            image_path=None, width=None, height=None, mode=None,
                            diagnostics=[DecodeDiagnostic('error', 'icon.decode_failed',
                                                          'ICON must contain exactly 128 bytes')])]
    image = Image.new('RGBA', (32, 32))
    image.putdata([(0, 0, 0, 255 if data[i // 8] & (0x80 >> (i % 8)) else 0)
                   for i in range(1024)])
    return [DecodeImage(resource=resource, status=DecodeStatus.OK, image_path=None,
                        width=32, height=32, mode='RGBA', frame_index=0, frame_count=1,
                        byte_ranges={'pixels': [0, 128]}, image=image)]
