use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde::Deserialize;

pub const DEFAULT_BASE_URL: &str = "https://openrouter.ai/api/v1";
pub const DEFAULT_RESOLUTION: &str = "1K";
pub const DEFAULT_ASPECT_RATIO: &str = "1:1";

pub struct Ask<'a> {
    pub model: &'a str,
    pub prompt: &'a str,
    pub cutout: &'a [u8],
    pub content_type: &'a str,
    pub resolution: &'a str,
    pub aspect_ratio: &'a str,
    pub seed: i64,
}

pub struct Rendered {
    pub image: Vec<u8>,
    pub content_type: String,
    pub provider_route: Option<String>,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Failure {
    Refused,
    Ineligible,
    InvalidOutput,
    Unavailable,
}

impl Failure {
    #[must_use]
    pub fn status(self) -> &'static str {
        match self {
            Self::Refused => "refused",
            Self::InvalidOutput => "invalid_output",
            Self::Ineligible | Self::Unavailable => "failed",
        }
    }

    #[must_use]
    pub fn may_try_another_model(self) -> bool {
        matches!(self, Self::Refused | Self::InvalidOutput)
    }
}

#[derive(Deserialize)]
struct Body {
    #[serde(default)]
    data: Vec<Image>,
    #[serde(default)]
    provider: Option<String>,
    #[serde(default)]
    usage: Option<Usage>,
}

#[derive(Deserialize)]
struct Image {
    #[serde(default)]
    b64_json: Option<String>,
}

#[derive(Deserialize)]
struct Usage {
    #[serde(default)]
    prompt_tokens: Option<i64>,
    #[serde(default)]
    completion_tokens: Option<i64>,
}

/// # Errors
///
/// Returns [`Failure::Ineligible`] when no approved zero-retention route can
/// serve the request, [`Failure::Refused`] when the provider declines the
/// content, [`Failure::Unavailable`] when it asks to be retried, and
/// [`Failure::InvalidOutput`] when the reply carries no usable image.
pub async fn render(
    client: &reqwest::Client,
    base_url: &str,
    api_key: &str,
    ask: &Ask<'_>,
) -> Result<Rendered, Failure> {
    let data_uri = format!(
        "data:{};base64,{}",
        ask.content_type,
        STANDARD.encode(ask.cutout)
    );
    let payload = serde_json::json!({
        "model": ask.model,
        "prompt": ask.prompt,
        "resolution": ask.resolution,
        "aspect_ratio": ask.aspect_ratio,
        "n": 1,
        "seed": ask.seed,
        "input_references": [
            { "type": "image_url", "image_url": { "url": data_uri } }
        ],
        "provider": { "zdr": true }
    });

    let response = client
        .post(format!("{base_url}/images"))
        .bearer_auth(api_key)
        .json(&payload)
        .send()
        .await
        .map_err(|_| Failure::Unavailable)?;

    let status = response.status().as_u16();
    if !(200..300).contains(&status) {
        return Err(classify(status));
    }

    let body: Body = response.json().await.map_err(|_| Failure::InvalidOutput)?;
    let [image] = body.data.as_slice() else {
        return Err(Failure::InvalidOutput);
    };
    let encoded = image.b64_json.as_deref().ok_or(Failure::InvalidOutput)?;
    let bytes = STANDARD
        .decode(encoded)
        .ok()
        .filter(|bytes| !bytes.is_empty())
        .ok_or(Failure::InvalidOutput)?;
    let content_type = sniff(&bytes).ok_or(Failure::InvalidOutput)?;

    Ok(Rendered {
        image: bytes,
        content_type: content_type.to_owned(),
        provider_route: body.provider,
        input_tokens: body.usage.as_ref().and_then(|usage| usage.prompt_tokens),
        output_tokens: body
            .usage
            .as_ref()
            .and_then(|usage| usage.completion_tokens),
    })
}

fn classify(status: u16) -> Failure {
    match status {
        402 | 403 => Failure::Ineligible,
        429 => Failure::Unavailable,
        400..=499 => Failure::Refused,
        _ => Failure::Unavailable,
    }
}

fn sniff(bytes: &[u8]) -> Option<&'static str> {
    const PNG: &[u8] = b"\x89PNG\r\n\x1a\n";
    const JPEG: &[u8] = b"\xff\xd8\xff";

    if bytes.starts_with(PNG) {
        Some("image/png")
    } else if bytes.starts_with(JPEG) {
        Some("image/jpeg")
    } else if bytes.len() > 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        Some("image/webp")
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::{Failure, classify, sniff};

    #[test]
    fn a_files_own_signature_decides_its_type() {
        assert_eq!(sniff(b"\x89PNG\r\n\x1a\nrest"), Some("image/png"));
        assert_eq!(sniff(b"\xff\xd8\xffrest"), Some("image/jpeg"));
        assert_eq!(sniff(b"RIFF____WEBPrest"), Some("image/webp"));
    }

    #[test]
    fn anything_without_an_image_signature_is_refused() {
        for bytes in [&b"not an image at all"[..], &b""[..], &b"\x89PNG"[..]] {
            assert_eq!(sniff(bytes), None);
        }
    }

    #[test]
    fn a_policy_refusal_never_becomes_a_retry() {
        assert_eq!(classify(403), Failure::Ineligible);
        assert_eq!(classify(402), Failure::Ineligible);
        assert!(!Failure::Ineligible.may_try_another_model());
    }

    #[test]
    fn only_a_transient_answer_asks_to_be_retried() {
        assert_eq!(classify(429), Failure::Unavailable);
        assert_eq!(classify(502), Failure::Unavailable);
        assert_eq!(classify(400), Failure::Refused);
    }
}
