use image::imageops::blur;
use image::{GrayImage, Luma, Rgba, RgbaImage};

const ORTHOGONAL: u16 = 3;
const DIAGONAL: u16 = 4;

#[derive(Debug, Clone, Copy)]
pub struct Style {
    pub border_permille: u32,
    pub outline_permille: u32,
    pub shadow_blur_permille: u32,
    pub shadow_offset_permille: u32,
    pub shadow_opacity_percent: u32,
    pub tolerance: u32,
}

impl Default for Style {
    fn default() -> Self {
        Self {
            border_permille: 23,
            outline_permille: 4,
            shadow_blur_permille: 12,
            shadow_offset_permille: 7,
            shadow_opacity_percent: 17,
            tolerance: 24,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct MaskBounds {
    pub min_coverage_permille: u32,
    pub max_coverage_permille: u32,
}

impl Default for MaskBounds {
    fn default() -> Self {
        Self {
            min_coverage_permille: 20,
            max_coverage_permille: 850,
        }
    }
}

// --- What `inspect` refuses, said in words a model can follow. It lives beside
// the rule it mirrors so the two cannot drift apart unnoticed.
pub const FRAMING_RULE: &str = "Centre the garment with clear empty margin on all four sides: it \
     must not touch or run off any edge, and must not fill the frame.";

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Rejection {
    Empty,
    FillsTheCanvas,
    TouchesTheEdge,
    Fragmented,
}

impl Rejection {
    #[must_use]
    pub fn code(self) -> &'static str {
        match self {
            Self::Empty => "mask_empty",
            Self::FillsTheCanvas => "mask_fills_the_canvas",
            Self::TouchesTheEdge => "mask_touches_the_edge",
            Self::Fragmented => "mask_fragmented",
        }
    }
}

pub struct Mask {
    width: u32,
    height: u32,
    garment: Vec<bool>,
}

#[derive(Debug, Clone, Copy)]
pub struct MaskReport {
    pub coverage_permille: u32,
    pub touches_edge: bool,
    pub components: usize,
    pub dominant_share_permille: u32,
}

impl Mask {
    #[must_use]
    pub fn report(&self) -> MaskReport {
        let (components, largest, total) = shapes(self);
        MaskReport {
            coverage_permille: self.coverage_permille(),
            touches_edge: touches_edge(self),
            components,
            dominant_share_permille: u32::try_from(
                (largest * 1000).checked_div(total).unwrap_or(0),
            )
            .unwrap_or(1000),
        }
    }

    fn at(&self, x: u32, y: u32) -> bool {
        self.garment[(y * self.width + x) as usize]
    }

    fn coverage_permille(&self) -> u32 {
        let painted = self.garment.iter().filter(|kept| **kept).count();
        u32::try_from(
            (painted * 1000)
                .checked_div(self.garment.len())
                .unwrap_or(0),
        )
        .unwrap_or(1000)
    }
}

#[must_use]
pub fn separate(canvas: &RgbaImage, tolerance: u32) -> Mask {
    let (width, height) = canvas.dimensions();
    let reference = corner_average(canvas);

    let mut background = vec![false; (width * height) as usize];
    let mut queue: Vec<(u32, u32)> = corners(width, height)
        .into_iter()
        .filter(|(x, y)| near(*canvas.get_pixel(*x, *y), reference, tolerance))
        .collect();
    for (x, y) in &queue {
        background[(y * width + x) as usize] = true;
    }

    while let Some((x, y)) = queue.pop() {
        for (nx, ny) in neighbours(x, y, width, height) {
            let index = (ny * width + nx) as usize;
            if background[index] || !near(*canvas.get_pixel(nx, ny), reference, tolerance) {
                continue;
            }
            background[index] = true;
            queue.push((nx, ny));
        }
    }

    Mask {
        width,
        height,
        garment: background.into_iter().map(|outside| !outside).collect(),
    }
}

/// # Errors
///
/// Returns [`Rejection`] when the separated shape cannot be a single garment on
/// a background this pipeline is able to remove.
pub fn inspect(mask: &Mask, bounds: MaskBounds) -> Result<(), Rejection> {
    let coverage = mask.coverage_permille();
    if coverage < bounds.min_coverage_permille {
        return Err(Rejection::Empty);
    }
    if coverage > bounds.max_coverage_permille {
        return Err(Rejection::FillsTheCanvas);
    }
    if touches_edge(mask) {
        return Err(Rejection::TouchesTheEdge);
    }
    if !one_dominant_shape(mask) {
        return Err(Rejection::Fragmented);
    }
    Ok(())
}

#[must_use]
pub fn compose(canvas: &RgbaImage, mask: &Mask, style: Style) -> RgbaImage {
    let side = mask.width.min(mask.height);
    let border = scaled(style.border_permille, side);
    let outline = scaled(style.outline_permille, side);
    let distance = distance_from_garment(mask);

    let sticker = |index: usize| distance[index] <= (border + outline) * ORTHOGONAL;
    let mut painted = RgbaImage::new(mask.width, mask.height);
    paint_shadow(&mut painted, mask, &sticker, style, side);

    for y in 0..mask.height {
        for x in 0..mask.width {
            let index = (y * mask.width + x) as usize;
            let steps = distance[index];
            let pixel = if steps == 0 {
                let source = canvas.get_pixel(x, y);
                Rgba([source[0], source[1], source[2], 255])
            } else if steps <= border * ORTHOGONAL {
                Rgba([255, 255, 255, 255])
            } else if sticker(index) {
                Rgba([31, 31, 36, 255])
            } else {
                continue;
            };
            painted.put_pixel(x, y, pixel);
        }
    }
    painted
}

fn paint_shadow(
    painted: &mut RgbaImage,
    mask: &Mask,
    sticker: &impl Fn(usize) -> bool,
    style: Style,
    side: u32,
) {
    let mut silhouette = GrayImage::new(mask.width, mask.height);
    let offset = u32::from(scaled(style.shadow_offset_permille, side));
    for y in 0..mask.height {
        for x in 0..mask.width {
            if sticker((y * mask.width + x) as usize) && y + offset < mask.height {
                silhouette.put_pixel(x, y + offset, Luma([255]));
            }
        }
    }

    let sigma = f32::from(scaled(style.shadow_blur_permille, side));
    for (x, y, shade) in blur(&silhouette, sigma).enumerate_pixels() {
        let alpha = u32::from(shade[0]) * style.shadow_opacity_percent / 100;
        if alpha > 0 {
            let alpha = u8::try_from(alpha.min(255)).unwrap_or(u8::MAX);
            painted.put_pixel(x, y, Rgba([0, 0, 0, alpha]));
        }
    }
}

fn distance_from_garment(mask: &Mask) -> Vec<u16> {
    let far = u16::MAX - DIAGONAL;
    let mut distance: Vec<u16> = mask
        .garment
        .iter()
        .map(|kept| if *kept { 0 } else { far })
        .collect();
    let width = mask.width as usize;

    for y in 0..mask.height as usize {
        for x in 0..width {
            let index = y * width + x;
            let mut best = distance[index];
            if y > 0 {
                best = best.min(distance[index - width] + ORTHOGONAL);
                if x > 0 {
                    best = best.min(distance[index - width - 1] + DIAGONAL);
                }
                if x + 1 < width {
                    best = best.min(distance[index - width + 1] + DIAGONAL);
                }
            }
            if x > 0 {
                best = best.min(distance[index - 1] + ORTHOGONAL);
            }
            distance[index] = best;
        }
    }

    for y in (0..mask.height as usize).rev() {
        for x in (0..width).rev() {
            let index = y * width + x;
            let mut best = distance[index];
            if y + 1 < mask.height as usize {
                best = best.min(distance[index + width] + ORTHOGONAL);
                if x > 0 {
                    best = best.min(distance[index + width - 1] + DIAGONAL);
                }
                if x + 1 < width {
                    best = best.min(distance[index + width + 1] + DIAGONAL);
                }
            }
            if x + 1 < width {
                best = best.min(distance[index + 1] + ORTHOGONAL);
            }
            distance[index] = best;
        }
    }
    distance
}

fn one_dominant_shape(mask: &Mask) -> bool {
    let (_, largest, total) = shapes(mask);
    total > 0 && largest * 10 >= total * 9
}

fn shapes(mask: &Mask) -> (usize, usize, usize) {
    let mut seen = vec![false; mask.garment.len()];
    let mut components = 0usize;
    let mut largest = 0usize;
    let mut total = 0usize;

    for start in 0..mask.garment.len() {
        if !mask.garment[start] || seen[start] {
            continue;
        }
        components += 1;
        let mut queue = vec![start];
        seen[start] = true;
        let mut size = 0usize;
        while let Some(index) = queue.pop() {
            size += 1;
            let position = u32::try_from(index).unwrap_or(u32::MAX);
            let (x, y) = (position % mask.width, position / mask.width);
            for (nx, ny) in neighbours(x, y, mask.width, mask.height) {
                let next = (ny * mask.width + nx) as usize;
                if mask.garment[next] && !seen[next] {
                    seen[next] = true;
                    queue.push(next);
                }
            }
        }
        total += size;
        largest = largest.max(size);
    }
    (components, largest, total)
}

fn touches_edge(mask: &Mask) -> bool {
    (0..mask.width).any(|x| mask.at(x, 0) || mask.at(x, mask.height - 1))
        || (0..mask.height).any(|y| mask.at(0, y) || mask.at(mask.width - 1, y))
}

fn corner_average(canvas: &RgbaImage) -> [u32; 3] {
    let (width, height) = canvas.dimensions();
    let mut total = [0u32; 3];
    for (x, y) in corners(width, height) {
        let pixel = canvas.get_pixel(x, y);
        for channel in 0..3 {
            total[channel] += u32::from(pixel[channel]);
        }
    }
    [total[0] / 4, total[1] / 4, total[2] / 4]
}

fn corners(width: u32, height: u32) -> [(u32, u32); 4] {
    [
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1),
    ]
}

fn near(pixel: Rgba<u8>, reference: [u32; 3], tolerance: u32) -> bool {
    (0..3).all(|channel| u32::from(pixel[channel]).abs_diff(reference[channel]) <= tolerance)
}

fn neighbours(x: u32, y: u32, width: u32, height: u32) -> Vec<(u32, u32)> {
    let mut around = Vec::with_capacity(4);
    if x > 0 {
        around.push((x - 1, y));
    }
    if y > 0 {
        around.push((x, y - 1));
    }
    if x + 1 < width {
        around.push((x + 1, y));
    }
    if y + 1 < height {
        around.push((x, y + 1));
    }
    around
}

fn scaled(permille: u32, side: u32) -> u16 {
    u16::try_from((side * permille / 1000).max(1)).unwrap_or(u16::MAX)
}

/// # Errors
///
/// Returns the classified reason when the generation cannot be decoded or the
/// separated shape is not a single garment this pipeline can dress.
pub fn stylise(bytes: &[u8], style: Style, bounds: MaskBounds) -> Result<Vec<u8>, &'static str> {
    let canvas = image::load_from_memory(bytes)
        .map_err(|_| "generation_undecodable")?
        .to_rgba8();
    let mask = separate(&canvas, style.tolerance);
    inspect(&mask, bounds).map_err(Rejection::code)?;

    let painted = compose(&canvas, &mask, style);
    let mut png = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgba8(painted)
        .write_to(&mut png, image::ImageFormat::Png)
        .map_err(|_| "generation_unencodable")?;
    Ok(png.into_inner())
}

#[cfg(test)]
mod tests {
    use super::{Mask, MaskBounds, Rejection, Rgba, RgbaImage, Style, compose, inspect, separate};

    const BACKDROP: [u8; 4] = [240, 240, 238, 255];
    const GARMENT: [u8; 4] = [40, 90, 160, 255];

    fn canvas(side: u32, shapes: &[(u32, u32, u32, u32)]) -> RgbaImage {
        let mut canvas = RgbaImage::from_pixel(side, side, Rgba(BACKDROP));
        for (left, top, width, height) in shapes {
            for y in *top..top + height {
                for x in *left..left + width {
                    canvas.put_pixel(x, y, Rgba(GARMENT));
                }
            }
        }
        canvas
    }

    fn centred(side: u32) -> RgbaImage {
        let box_side = side / 2;
        canvas(side, &[(side / 4, side / 4, box_side, box_side)])
    }

    #[test]
    fn an_empty_mask_reports_zeroes_instead_of_dividing_by_nothing() {
        let empty = Mask {
            width: 0,
            height: 0,
            garment: Vec::new(),
        };

        let report = empty.report();

        assert_eq!(report.coverage_permille, 0);
        assert_eq!(report.dominant_share_permille, 0);
        assert_eq!(report.components, 0);
    }

    fn mask_of(canvas: &RgbaImage) -> Mask {
        separate(canvas, Style::default().tolerance)
    }

    fn band_widths(painted: &RgbaImage, side: u32) -> (u32, u32) {
        let row = side / 2;
        let mut white = 0;
        let mut dark = 0;
        for x in 0..side {
            let pixel = painted.get_pixel(x, row);
            if pixel[3] < 255 {
                continue;
            }
            if pixel[0] > 200 && pixel[1] > 200 && pixel[2] > 200 {
                white += 1;
            } else if pixel[0] < 60 && pixel[1] < 60 && pixel[2] < 60 {
                dark += 1;
            }
        }
        (white / 2, dark / 2)
    }

    #[test]
    fn a_flat_backdrop_leaves_only_the_garment() {
        let mask = mask_of(&centred(200));

        assert_eq!(inspect(&mask, MaskBounds::default()), Ok(()));
        assert!(mask.at(100, 100), "the middle is the garment");
        assert!(!mask.at(2, 2), "the corner is not");
    }

    #[test]
    fn the_bands_sit_outside_the_garment_in_order() {
        let side = 400;
        let source = centred(side);
        let painted = compose(&source, &mask_of(&source), Style::default());

        let middle = painted.get_pixel(side / 2, side / 2);
        assert_eq!([middle[0], middle[1], middle[2]], GARMENT[..3]);
        assert_eq!(middle[3], 255);

        let (white, dark) = band_widths(&painted, side);
        assert!(white > dark, "the white border is the wider of the two");
        assert!(dark > 0, "and the dark outline exists at all");
        assert_eq!(painted.get_pixel(1, 1)[3], 0, "the far corner stays clear");
    }

    #[test]
    fn the_bands_scale_with_the_canvas() {
        let small = centred(400);
        let large = centred(800);
        let (small_white, _) =
            band_widths(&compose(&small, &mask_of(&small), Style::default()), 400);
        let (large_white, _) =
            band_widths(&compose(&large, &mask_of(&large), Style::default()), 800);

        assert!(
            large_white.abs_diff(small_white * 2) <= 2,
            "a 2K sticker has to look like a 1K one, so the border doubles: {small_white} then {large_white}"
        );
    }

    #[test]
    fn a_backdrop_with_nothing_on_it_is_refused() {
        let empty = canvas(200, &[]);

        assert_eq!(
            inspect(&mask_of(&empty), MaskBounds::default()),
            Err(Rejection::Empty)
        );
    }

    #[test]
    fn a_garment_covering_the_canvas_is_refused() {
        let full = canvas(200, &[(1, 1, 198, 198)]);

        assert_eq!(
            inspect(&mask_of(&full), MaskBounds::default()),
            Err(Rejection::FillsTheCanvas)
        );
    }

    #[test]
    fn a_garment_running_off_the_canvas_is_refused() {
        let clipped = canvas(200, &[(0, 60, 90, 80)]);

        assert_eq!(
            inspect(&mask_of(&clipped), MaskBounds::default()),
            Err(Rejection::TouchesTheEdge)
        );
    }

    #[test]
    fn two_separate_blobs_are_refused() {
        let scattered = canvas(200, &[(30, 30, 50, 50), (120, 120, 50, 50)]);

        assert_eq!(
            inspect(&mask_of(&scattered), MaskBounds::default()),
            Err(Rejection::Fragmented)
        );
    }

    #[test]
    fn thin_straps_and_wide_silhouettes_survive() {
        let strappy = canvas(200, &[(90, 40, 4, 120), (60, 100, 80, 60)]);
        let wide = canvas(200, &[(20, 80, 160, 40)]);

        assert_eq!(inspect(&mask_of(&strappy), MaskBounds::default()), Ok(()));
        assert_eq!(inspect(&mask_of(&wide), MaskBounds::default()), Ok(()));
    }
}
