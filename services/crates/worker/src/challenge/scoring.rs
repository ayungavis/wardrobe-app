use uuid::Uuid;

pub const NEUTRAL: f64 = 0.5;

#[derive(Debug, Clone)]
pub struct Garment {
    pub id: Uuid,
    pub category: String,
    pub garment_type: Option<String>,
    pub color: Option<String>,
    pub days_since_worn: Option<i64>,
    pub wear_count: i64,
    pub renderable: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct Weather {
    pub high_c: i16,
    pub low_c: i16,
    pub wet: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct Weights {
    pub neglect: f64,
    pub rarity: f64,
    pub novelty: f64,
    pub weather: f64,
    pub colour: f64,
    pub renderable: f64,
    pub reuse: f64,
}

impl Default for Weights {
    fn default() -> Self {
        Self {
            neglect: 1.0,
            rarity: 0.6,
            novelty: 0.9,
            weather: 1.2,
            colour: 0.5,
            renderable: 0.4,
            reuse: 0.8,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Pairing {
    pub top: Uuid,
    pub bottom: Uuid,
}

pub struct Wardrobe {
    pub garments: Vec<Garment>,
    pub last_together: Vec<(Uuid, Uuid, i64)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Family {
    Neutral,
    Warm,
    Cool,
    Unknown,
}

const WARM_WORDS: &[&str] = &[
    "red", "orange", "yellow", "pink", "gold", "brown", "maroon", "burgundy", "peach", "coral",
    "merah", "oranye", "kuning", "cokelat", "coklat", "emas",
];
const COOL_WORDS: &[&str] = &[
    "blue", "green", "purple", "teal", "navy", "mint", "lilac", "lavender", "olive", "biru",
    "hijau", "ungu", "tosca",
];
const NEUTRAL_WORDS: &[&str] = &[
    "black", "white", "grey", "gray", "beige", "cream", "denim", "khaki", "ivory", "charcoal",
    "hitam", "putih", "abu", "krem", "netral",
];

const COLOUR_WORDS: &[&str] = &[
    "red", "orange", "yellow", "pink", "gold", "brown", "maroon", "burgundy", "peach", "coral",
    "blue", "green", "purple", "teal", "navy", "mint", "lilac", "lavender", "olive", "silver",
    "black", "white", "grey", "gray", "beige", "cream", "denim", "khaki", "ivory", "charcoal",
    "pastel", "dark", "light", "merah", "oranye", "kuning", "cokelat", "coklat", "emas", "biru",
    "hijau", "ungu", "tosca", "hitam", "putih", "abu", "krem", "muda", "tua",
];

const GARMENT_WORDS: &[&str] = &[
    "shirt",
    "t-shirt",
    "tee",
    "top",
    "blouse",
    "sweater",
    "hoodie",
    "cardigan",
    "jacket",
    "coat",
    "blazer",
    "tank",
    "camisole",
    "vest",
    "knit",
    "flannel",
    "polo",
    "sweatshirt",
    "crop",
    "jeans",
    "trousers",
    "pants",
    "shorts",
    "skirt",
    "leggings",
    "joggers",
    "chinos",
    "cargo",
    "culottes",
    "denim",
    "pleated",
    "oversized",
    "sleeveless",
    "linen",
    "puffer",
    "kaos",
    "kemeja",
    "blus",
    "rok",
    "celana",
    "jaket",
    "sweter",
    "rajut",
    "kulot",
    "plisket",
    "pendek",
    "panjang",
    "singlet",
    "mantel",
];

const HEAVY_WORDS: &[&str] = &[
    "coat", "jacket", "sweater", "hoodie", "knit", "cardigan", "blazer", "puffer", "flannel",
    "jaket", "mantel", "rajut", "sweter",
];
const LIGHT_WORDS: &[&str] = &[
    "shorts",
    "tank",
    "camisole",
    "sleeveless",
    "linen",
    "crop",
    "singlet",
    "pendek",
    "kaos",
    "tipis",
];

fn clean(raw: Option<&str>) -> Option<String> {
    let cleaned: String = raw?
        .to_lowercase()
        .chars()
        .map(|character| {
            if character.is_ascii_alphabetic() || character == ' ' || character == '-' {
                character
            } else {
                ' '
            }
        })
        .collect();
    let cleaned = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    (!cleaned.is_empty()).then_some(cleaned)
}

fn vocabulary(raw: Option<&str>, allowed: &[&str]) -> Option<String> {
    let cleaned = clean(raw)?;
    let kept: Vec<&str> = cleaned
        .split(' ')
        .filter(|word| allowed.contains(word))
        .take(2)
        .collect();
    (!kept.is_empty()).then(|| kept.join(" "))
}

#[must_use]
pub fn safe_colour(raw: Option<&str>) -> Option<String> {
    vocabulary(raw, COLOUR_WORDS)
}

#[must_use]
pub fn safe_type(raw: Option<&str>) -> Option<String> {
    vocabulary(raw, GARMENT_WORDS)
}

fn family(color: Option<&str>) -> Family {
    let Some(color) = clean(color) else {
        return Family::Unknown;
    };
    let hit = |words: &[&str]| words.iter().any(|word| color.contains(word));
    if hit(NEUTRAL_WORDS) {
        Family::Neutral
    } else if hit(WARM_WORDS) {
        Family::Warm
    } else if hit(COOL_WORDS) {
        Family::Cool
    } else {
        Family::Unknown
    }
}

#[must_use]
pub fn warmth(garment_type: Option<&str>) -> f64 {
    let Some(kind) = clean(garment_type) else {
        return NEUTRAL;
    };
    let hit = |words: &[&str]| words.iter().any(|word| kind.contains(word));
    if hit(HEAVY_WORDS) {
        0.9
    } else if hit(LIGHT_WORDS) {
        0.1
    } else {
        NEUTRAL
    }
}

#[must_use]
pub fn weather_fit(garment: &Garment, weather: Option<Weather>) -> f64 {
    let Some(weather) = weather else {
        return NEUTRAL;
    };
    let mean = f64::midpoint(f64::from(weather.high_c), f64::from(weather.low_c));
    let wanted = ((24.0 - mean) / 16.0 + if weather.wet { 0.15 } else { 0.0 }).clamp(0.0, 1.0);
    1.0 - (warmth(garment.garment_type.as_deref()) - wanted).abs()
}

#[must_use]
pub fn colour_harmony(top: &Garment, bottom: &Garment) -> f64 {
    let (left, right) = (
        family(top.color.as_deref()),
        family(bottom.color.as_deref()),
    );
    match (left, right) {
        (Family::Unknown, _) | (_, Family::Unknown) => NEUTRAL,
        (Family::Neutral, Family::Neutral) => 0.7,
        (Family::Neutral, _) | (_, Family::Neutral) => 1.0,
        (left, right) if left == right => 0.65,
        _ => 0.8,
    }
}

fn scale(value: i64) -> f64 {
    f64::from(i32::try_from(value).unwrap_or(i32::MAX))
}

fn normalised(value: Option<i64>, ceiling: i64) -> f64 {
    match value {
        None => 1.0,
        Some(days) if ceiling <= 0 => f64::from(u8::from(days > 0)),
        Some(days) => (scale(days) / scale(ceiling)).clamp(0.0, 1.0),
    }
}

impl Wardrobe {
    fn together(&self, top: Uuid, bottom: Uuid) -> Option<i64> {
        let (low, high) = if top < bottom {
            (top, bottom)
        } else {
            (bottom, top)
        };
        self.last_together
            .iter()
            .find(|(x, y, _)| *x == low && *y == high)
            .map(|(_, _, days)| *days)
    }

    fn ceilings(&self) -> (i64, i64) {
        let neglect = self
            .garments
            .iter()
            .filter_map(|garment| garment.days_since_worn)
            .max()
            .unwrap_or(0);
        let novelty = self
            .last_together
            .iter()
            .map(|(_, _, days)| *days)
            .max()
            .unwrap_or(0);
        (neglect.max(1), novelty.max(1))
    }
}

fn merit(
    wardrobe: &Wardrobe,
    top: &Garment,
    bottom: &Garment,
    weather: Option<Weather>,
    weights: &Weights,
    ceilings: (i64, i64),
) -> f64 {
    let (neglect_ceiling, novelty_ceiling) = ceilings;
    let neglect = f64::midpoint(
        normalised(top.days_since_worn, neglect_ceiling),
        normalised(bottom.days_since_worn, neglect_ceiling),
    );
    let rarity = f64::midpoint(
        1.0 / (1.0 + scale(top.wear_count)),
        1.0 / (1.0 + scale(bottom.wear_count)),
    );
    let novelty = normalised(wardrobe.together(top.id, bottom.id), novelty_ceiling);
    let weather_fit = f64::midpoint(weather_fit(top, weather), weather_fit(bottom, weather));
    let renderable =
        f64::from(u8::from(top.renderable)) / 2.0 + f64::from(u8::from(bottom.renderable)) / 2.0;

    weights.neglect * neglect
        + weights.rarity * rarity
        + weights.novelty * novelty
        + weights.weather * weather_fit
        + weights.colour * colour_harmony(top, bottom)
        + weights.renderable * renderable
}

#[must_use]
pub fn choose(
    wardrobe: &Wardrobe,
    weather: Option<Weather>,
    weights: &Weights,
    wanted: usize,
) -> Vec<Pairing> {
    let tops: Vec<&Garment> = wardrobe
        .garments
        .iter()
        .filter(|garment| garment.category == "top")
        .collect();
    let bottoms: Vec<&Garment> = wardrobe
        .garments
        .iter()
        .filter(|garment| garment.category == "bottom")
        .collect();
    if tops.is_empty() || bottoms.is_empty() {
        return Vec::new();
    }

    let ceilings = wardrobe.ceilings();
    let mut scored: Vec<(f64, Pairing)> = Vec::with_capacity(tops.len() * bottoms.len());
    for top in &tops {
        for bottom in &bottoms {
            scored.push((
                merit(wardrobe, top, bottom, weather, weights, ceilings),
                Pairing {
                    top: top.id,
                    bottom: bottom.id,
                },
            ));
        }
    }

    let mut used: Vec<Uuid> = Vec::new();
    let mut chosen: Vec<Pairing> = Vec::new();
    while chosen.len() < wanted {
        let count = |id: Uuid| {
            let seen = used.iter().filter(|seen| **seen == id).count();
            f64::from(u32::try_from(seen).unwrap_or(u32::MAX))
        };
        let best = scored
            .iter()
            .filter(|(_, pairing)| !chosen.contains(pairing))
            .max_by(|(left, one), (right, other)| {
                let left = left - weights.reuse * (count(one.top) + count(one.bottom));
                let right = right - weights.reuse * (count(other.top) + count(other.bottom));
                left.total_cmp(&right)
            })
            .map(|(_, pairing)| *pairing);
        let Some(best) = best else { break };
        used.push(best.top);
        used.push(best.bottom);
        chosen.push(best);
    }
    chosen
}
