use std::io::Cursor;

use image::{ImageFormat, ImageReader, Limits};

pub const DEFAULT_MAX_BYTES: u64 = 8 * 1024 * 1024;
pub const DEFAULT_MAX_PIXELS: u64 = 4096 * 4096;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub struct Bounds {
    pub max_bytes: u64,
    pub max_pixels: u64,
}

impl Default for Bounds {
    fn default() -> Self {
        Self {
            max_bytes: DEFAULT_MAX_BYTES,
            max_pixels: DEFAULT_MAX_PIXELS,
        }
    }
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Rejection {
    TooManyBytes,
    TooManyPixels,
    NotSquare,
    Undecodable,
    WrongCanvas,
}

impl Rejection {
    #[must_use]
    pub fn code(self) -> &'static str {
        match self {
            Self::TooManyBytes => "cutout_too_large",
            Self::TooManyPixels => "cutout_too_many_pixels",
            Self::NotSquare => "cutout_not_square",
            Self::Undecodable => "cutout_undecodable",
            Self::WrongCanvas => "generation_wrong_canvas",
        }
    }
}

/// # Errors
///
/// Returns [`Rejection`] when the cut-out is larger than the bounds allow, is
/// not a square image, or cannot be decoded.
pub fn prepare(bytes: &[u8], bounds: Bounds) -> Result<Vec<u8>, Rejection> {
    if bytes.len() as u64 > bounds.max_bytes {
        return Err(Rejection::TooManyBytes);
    }

    let (width, height) = dimensions(bytes)?;
    if u64::from(width) * u64::from(height) > bounds.max_pixels {
        return Err(Rejection::TooManyPixels);
    }
    if width != height {
        return Err(Rejection::NotSquare);
    }

    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| Rejection::Undecodable)?;
    reader.limits(bounds.limits());
    let decoded = reader.decode().map_err(|_| Rejection::Undecodable)?;

    let mut png = Cursor::new(Vec::new());
    decoded
        .write_to(&mut png, ImageFormat::Png)
        .map_err(|_| Rejection::Undecodable)?;
    Ok(png.into_inner())
}

/// # Errors
///
/// Returns [`Rejection`] when the generated image cannot be decoded or does not
/// land on the canvas the capability was configured for.
pub fn verify_generation(
    bytes: &[u8],
    resolution: &str,
    aspect_ratio: &str,
) -> Result<(), Rejection> {
    let (width, height) = dimensions(bytes)?;

    let Some((expected_width, expected_height)) = expected_canvas(resolution, aspect_ratio) else {
        return Ok(());
    };
    if (width, height) == (expected_width, expected_height) {
        Ok(())
    } else {
        Err(Rejection::WrongCanvas)
    }
}

// ponytail: only the square canvases are pinned to exact pixels, because 1K and
// 2K are measured for 1:1 and guessed for everything else. Add a ratio here once
// a real render has been measured at that shape.
fn expected_canvas(resolution: &str, aspect_ratio: &str) -> Option<(u32, u32)> {
    if aspect_ratio != "1:1" {
        return None;
    }
    match resolution {
        "1K" => Some((1024, 1024)),
        "2K" => Some((2048, 2048)),
        _ => None,
    }
}

fn dimensions(bytes: &[u8]) -> Result<(u32, u32), Rejection> {
    ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| Rejection::Undecodable)?
        .into_dimensions()
        .map_err(|_| Rejection::Undecodable)
}

impl Bounds {
    fn limits(self) -> Limits {
        let side = u32::try_from(self.max_pixels.isqrt()).unwrap_or(u32::MAX);
        let mut limits = Limits::no_limits();
        limits.max_image_width = Some(side);
        limits.max_image_height = Some(side);
        limits.max_alloc = Some(self.max_pixels.saturating_mul(4));
        limits
    }
}

#[cfg(test)]
mod tests {
    use super::{Bounds, Cursor, ImageFormat, Rejection, expected_canvas, prepare};

    fn flat(width: u32, height: u32) -> Vec<u8> {
        let canvas = ::image::RgbImage::from_pixel(width, height, ::image::Rgb([1, 2, 3]));
        let mut bytes = Cursor::new(Vec::new());
        ::image::DynamicImage::ImageRgb8(canvas)
            .write_to(&mut bytes, ImageFormat::Png)
            .expect("a png");
        bytes.into_inner()
    }

    fn claiming(width: u32, height: u32) -> Vec<u8> {
        let mut bytes = flat(8, 8);
        bytes[16..20].copy_from_slice(&width.to_be_bytes());
        bytes[20..24].copy_from_slice(&height.to_be_bytes());
        let crc = crc32fast(&bytes[12..29]);
        bytes[29..33].copy_from_slice(&crc.to_be_bytes());
        bytes
    }

    fn crc32fast(bytes: &[u8]) -> u32 {
        let mut crc = 0xffff_ffff_u32;
        for byte in bytes {
            crc ^= u32::from(*byte);
            for _ in 0..8 {
                crc = if crc & 1 == 1 {
                    (crc >> 1) ^ 0xedb8_8320
                } else {
                    crc >> 1
                };
            }
        }
        !crc
    }

    #[test]
    fn a_square_png_survives_and_stays_a_png() {
        let prepared = prepare(&flat(64, 64), Bounds::default()).expect("prepared");
        assert_eq!(&prepared[..8], b"\x89PNG\r\n\x1a\n");
    }

    #[test]
    fn each_refusal_names_itself() {
        assert_eq!(
            prepare(
                &flat(64, 64),
                Bounds {
                    max_bytes: 4,
                    ..Bounds::default()
                }
            ),
            Err(Rejection::TooManyBytes)
        );
        assert_eq!(
            prepare(&flat(64, 48), Bounds::default()),
            Err(Rejection::NotSquare)
        );
        assert_eq!(
            prepare(b"not an image", Bounds::default()),
            Err(Rejection::Undecodable)
        );
    }

    #[test]
    fn a_header_claiming_more_pixels_than_allowed_is_named_before_any_decode() {
        assert_eq!(
            prepare(&claiming(60_000, 60_000), Bounds::default()),
            Err(Rejection::TooManyPixels)
        );
    }

    #[test]
    fn only_the_measured_canvases_are_pinned_to_pixels() {
        assert_eq!(expected_canvas("1K", "1:1"), Some((1024, 1024)));
        assert_eq!(expected_canvas("2K", "1:1"), Some((2048, 2048)));
        assert_eq!(expected_canvas("1K", "3:4"), None);
        assert_eq!(expected_canvas("4K", "1:1"), None);
    }
}
