use std::time::{Duration, Instant};

use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode, decode_header};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use tokio::sync::RwLock;

const ISSUER: &str = "https://appleid.apple.com";
const JWKS_URL: &str = "https://appleid.apple.com/auth/keys";
const CACHE_TTL: Duration = Duration::from_secs(60 * 60);
const REFETCH_FLOOR: Duration = Duration::from_secs(60);

#[derive(Debug, PartialEq, Eq)]
pub struct AppleIdentity {
    pub subject: String,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum AppleError {
    #[error("the identity token could not be verified")]
    Rejected,
    #[error("no signing key matches the token")]
    UnknownKey,
    #[error("Apple sign-in is not configured")]
    NotConfigured,
    #[error("Apple's signing keys are unavailable")]
    KeysUnavailable,
}

#[derive(Clone, Debug, Deserialize)]
pub struct AppleKey {
    pub kid: String,
    pub n: String,
    pub e: String,
}

#[derive(Deserialize)]
struct Jwks {
    keys: Vec<AppleKey>,
}

#[derive(Deserialize)]
struct Claims {
    sub: String,
    nonce: Option<String>,
}

/// # Errors
///
/// Returns [`AppleError::UnknownKey`] when no key matches the token's `kid`, and
/// [`AppleError::Rejected`] for every other failure — the caller learns nothing
/// about which check failed.
pub fn verify(
    token: &str,
    keys: &[AppleKey],
    audience: &str,
    nonce: &str,
) -> Result<AppleIdentity, AppleError> {
    let header = decode_header(token).map_err(|_| AppleError::Rejected)?;
    let kid = header.kid.ok_or(AppleError::Rejected)?;
    let key = keys
        .iter()
        .find(|candidate| candidate.kid == kid)
        .ok_or(AppleError::UnknownKey)?;

    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_issuer(&[ISSUER]);
    validation.set_audience(&[audience]);
    validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);

    let decoding =
        DecodingKey::from_rsa_components(&key.n, &key.e).map_err(|_| AppleError::UnknownKey)?;
    let claims = decode::<Claims>(token, &decoding, &validation)
        .map_err(|_| AppleError::Rejected)?
        .claims;

    let presented = claims.nonce.ok_or(AppleError::Rejected)?;
    if presented != hash_nonce(nonce) {
        return Err(AppleError::Rejected);
    }

    Ok(AppleIdentity {
        subject: claims.sub,
    })
}

#[must_use]
pub fn hash_nonce(nonce: &str) -> String {
    let digest = Sha256::digest(nonce.as_bytes());
    digest.iter().fold(String::new(), |mut out, byte| {
        use std::fmt::Write;
        let _ = write!(out, "{byte:02x}");
        out
    })
}

pub struct Verifier {
    audience: Option<String>,
    keys: RwLock<Cached>,
    client: reqwest::Client,
}

struct Cached {
    keys: Vec<AppleKey>,
    fetched_at: Option<Instant>,
}

impl Verifier {
    #[must_use]
    pub fn new(audience: Option<String>) -> Self {
        Self {
            audience,
            keys: RwLock::new(Cached {
                keys: Vec::new(),
                fetched_at: None,
            }),
            client: reqwest::Client::new(),
        }
    }

    /// # Errors
    ///
    /// Returns [`AppleError`] when the token fails any check, when Apple's keys
    /// cannot be reached, or when no bundle id is configured.
    pub async fn verify(&self, token: &str, nonce: &str) -> Result<AppleIdentity, AppleError> {
        let audience = self.audience.clone().ok_or(AppleError::NotConfigured)?;

        match verify(token, &self.cached_keys().await?, &audience, nonce) {
            Err(AppleError::UnknownKey) => {
                verify(token, &self.refreshed_keys().await?, &audience, nonce)
            }
            outcome => outcome,
        }
    }

    async fn cached_keys(&self) -> Result<Vec<AppleKey>, AppleError> {
        let cached = self.keys.read().await;
        match cached.fetched_at {
            Some(at) if at.elapsed() < CACHE_TTL => Ok(cached.keys.clone()),
            _ => {
                drop(cached);
                self.refreshed_keys().await
            }
        }
    }

    async fn refreshed_keys(&self) -> Result<Vec<AppleKey>, AppleError> {
        let mut cached = self.keys.write().await;
        if cached
            .fetched_at
            .is_some_and(|at| at.elapsed() < REFETCH_FLOOR)
        {
            return Ok(cached.keys.clone());
        }

        let jwks: Jwks = self
            .client
            .get(JWKS_URL)
            .send()
            .await
            .map_err(|_| AppleError::KeysUnavailable)?
            .json()
            .await
            .map_err(|_| AppleError::KeysUnavailable)?;

        cached.keys = jwks.keys;
        cached.fetched_at = Some(Instant::now());
        Ok(cached.keys.clone())
    }
}

#[cfg(test)]
mod tests {
    use std::sync::OnceLock;

    use jsonwebtoken::{EncodingKey, Header, encode};
    use rsa::pkcs1::EncodeRsaPrivateKey;
    use rsa::traits::PublicKeyParts;
    use rsa::{RsaPrivateKey, rand_core::OsRng};
    use serde::Serialize;

    use super::*;

    const AUDIENCE: &str = "com.ayungavis.WardrobeApp";
    const KID: &str = "test-key";
    const NONCE: &str = "a-client-generated-nonce";

    #[derive(Serialize)]
    struct TestClaims {
        iss: String,
        aud: String,
        sub: String,
        exp: i64,
        nonce: String,
    }

    fn keypair() -> &'static (RsaPrivateKey, AppleKey) {
        static PAIR: OnceLock<(RsaPrivateKey, AppleKey)> = OnceLock::new();
        PAIR.get_or_init(|| {
            let private = RsaPrivateKey::new(&mut OsRng, 2048).expect("generated key");
            let public = private.to_public_key();
            let jwk = AppleKey {
                kid: KID.to_owned(),
                n: base64url(&public.n().to_bytes_be()),
                e: base64url(&public.e().to_bytes_be()),
            };
            (private, jwk)
        })
    }

    fn base64url(bytes: &[u8]) -> String {
        const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let mut out = String::new();
        for chunk in bytes.chunks(3) {
            let b = [
                chunk[0],
                *chunk.get(1).unwrap_or(&0),
                *chunk.get(2).unwrap_or(&0),
            ];
            let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
            for i in 0..=chunk.len() {
                out.push(ALPHABET[((n >> (18 - 6 * i)) & 0x3f) as usize] as char);
            }
        }
        out
    }

    fn claims() -> TestClaims {
        TestClaims {
            iss: ISSUER.to_owned(),
            aud: AUDIENCE.to_owned(),
            sub: "001234.abcdef.5678".to_owned(),
            exp: (chrono::Utc::now() + chrono::Duration::hours(1)).timestamp(),
            nonce: hash_nonce(NONCE),
        }
    }

    fn sign(claims: &TestClaims, header: &Header) -> String {
        let pem = keypair()
            .0
            .to_pkcs1_pem(rsa::pkcs1::LineEnding::LF)
            .expect("pem");
        let key = EncodingKey::from_rsa_pem(pem.as_bytes()).expect("encoding key");
        encode(header, claims, &key).expect("signed token")
    }

    fn rs256() -> Header {
        Header {
            kid: Some(KID.to_owned()),
            ..Header::new(Algorithm::RS256)
        }
    }

    fn keys() -> Vec<AppleKey> {
        vec![keypair().1.clone()]
    }

    #[test]
    fn a_well_formed_token_yields_its_subject() {
        let token = sign(&claims(), &rs256());

        let identity = verify(&token, &keys(), AUDIENCE, NONCE).expect("verified");

        assert_eq!(identity.subject, "001234.abcdef.5678");
    }

    #[test]
    fn a_token_signed_by_another_key_is_rejected() {
        let token = sign(&claims(), &rs256());
        let other = RsaPrivateKey::new(&mut OsRng, 2048).expect("second key");
        let impostor = AppleKey {
            kid: KID.to_owned(),
            n: base64url(&other.to_public_key().n().to_bytes_be()),
            e: base64url(&other.to_public_key().e().to_bytes_be()),
        };

        assert_eq!(
            verify(&token, &[impostor], AUDIENCE, NONCE),
            Err(AppleError::Rejected)
        );
    }

    #[test]
    fn an_hs256_token_cannot_borrow_the_public_key_as_its_secret() {
        let key = EncodingKey::from_secret(keypair().1.n.as_bytes());
        let header = Header {
            kid: Some(KID.to_owned()),
            ..Header::new(Algorithm::HS256)
        };
        let token = encode(&header, &claims(), &key).expect("hs256 token");

        assert_eq!(
            verify(&token, &keys(), AUDIENCE, NONCE),
            Err(AppleError::Rejected)
        );
    }

    #[test]
    fn a_token_from_another_issuer_is_rejected() {
        let token = sign(
            &TestClaims {
                iss: "https://accounts.google.com".to_owned(),
                ..claims()
            },
            &rs256(),
        );

        assert_eq!(
            verify(&token, &keys(), AUDIENCE, NONCE),
            Err(AppleError::Rejected)
        );
    }

    #[test]
    fn a_token_for_another_app_is_rejected() {
        let token = sign(
            &TestClaims {
                aud: "com.someone.else".to_owned(),
                ..claims()
            },
            &rs256(),
        );

        assert_eq!(
            verify(&token, &keys(), AUDIENCE, NONCE),
            Err(AppleError::Rejected)
        );
    }

    #[test]
    fn an_expired_token_is_rejected() {
        let token = sign(
            &TestClaims {
                exp: (chrono::Utc::now() - chrono::Duration::hours(1)).timestamp(),
                ..claims()
            },
            &rs256(),
        );

        assert_eq!(
            verify(&token, &keys(), AUDIENCE, NONCE),
            Err(AppleError::Rejected)
        );
    }

    #[test]
    fn the_nonce_digest_is_lowercase_hex_of_the_raw_bytes() {
        assert_eq!(
            hash_nonce(NONCE),
            "6a264878f1535f17aff4db3feda236163ac2e1fd1b7d9374772d5228b458a0eb",
            "SignInNonceTests on iOS pins the same pair; changing one side alone \
             turns every Apple sign-in into an unexplained rejection"
        );
    }

    #[test]
    fn a_replayed_token_fails_because_its_nonce_belongs_to_another_sign_in() {
        let token = sign(&claims(), &rs256());

        assert_eq!(
            verify(&token, &keys(), AUDIENCE, "a-different-nonce"),
            Err(AppleError::Rejected)
        );
    }

    #[test]
    fn a_token_without_a_nonce_is_rejected() {
        #[derive(Serialize)]
        struct NoNonce {
            iss: String,
            aud: String,
            sub: String,
            exp: i64,
        }
        let base = claims();
        let pem = keypair()
            .0
            .to_pkcs1_pem(rsa::pkcs1::LineEnding::LF)
            .expect("pem");
        let key = EncodingKey::from_rsa_pem(pem.as_bytes()).expect("encoding key");
        let token = encode(
            &rs256(),
            &NoNonce {
                iss: base.iss,
                aud: base.aud,
                sub: base.sub,
                exp: base.exp,
            },
            &key,
        )
        .expect("token");

        assert_eq!(
            verify(&token, &keys(), AUDIENCE, NONCE),
            Err(AppleError::Rejected)
        );
    }

    #[test]
    fn an_unknown_kid_is_distinguishable_so_the_cache_can_refresh() {
        let token = sign(&claims(), &rs256());
        let rotated = AppleKey {
            kid: "some-newer-key".to_owned(),
            ..keypair().1.clone()
        };

        assert_eq!(
            verify(&token, &[rotated], AUDIENCE, NONCE),
            Err(AppleError::UnknownKey)
        );
    }

    #[test]
    fn no_error_message_repeats_the_token() {
        let token = sign(&claims(), &rs256());
        let failures = [
            verify(&token, &keys(), "com.someone.else", NONCE).unwrap_err(),
            verify(&token, &keys(), AUDIENCE, "wrong").unwrap_err(),
            verify(&token, &[], AUDIENCE, NONCE).unwrap_err(),
            verify("not-a-token", &keys(), AUDIENCE, NONCE).unwrap_err(),
        ];

        for failure in failures {
            let rendered = failure.to_string();
            assert!(
                !rendered.contains(&token) && !rendered.contains("eyJ"),
                "a credential must never reach a message: {rendered}"
            );
        }
    }
}
