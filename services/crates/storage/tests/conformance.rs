use std::time::Duration;

use uuid::Uuid;
use wardrobe_storage::{Error, Settings, Storage};

fn settings(presign_ttl: Duration) -> Settings {
    fn env(name: &str, fallback: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| fallback.to_owned())
    }
    Settings {
        endpoint: env("TEST_S3_ENDPOINT", "http://localhost:9100"),
        region: env("TEST_S3_REGION", "us-east-1"),
        bucket: env("TEST_S3_BUCKET", "wardrobe"),
        access_key_id: env("TEST_S3_ACCESS_KEY_ID", "wardrobe"),
        secret_access_key: env("TEST_S3_SECRET_ACCESS_KEY", "wardrobe-dev-secret"),
        path_style: true,
        presign_ttl,
    }
}

async fn store(presign_ttl: Duration) -> Storage {
    let storage = Storage::new(&settings(presign_ttl));
    storage.ensure_bucket().await.expect("a usable bucket");
    storage
}

fn key() -> String {
    format!("conformance/{}", Uuid::now_v7())
}

const TTL: Duration = Duration::from_secs(300);

// ------------------------------------------------------------------ the basics

#[tokio::test]
async fn bytes_survive_a_round_trip() {
    let storage = store(TTL).await;
    let key = key();

    storage
        .put(&key, b"a blue shirt".to_vec(), "image/jpeg")
        .await
        .expect("put");
    assert_eq!(storage.get(&key).await.expect("get"), b"a blue shirt");
}

#[tokio::test]
async fn head_measures_what_is_there_and_stays_quiet_about_what_is_not() {
    let storage = store(TTL).await;
    let key = key();

    assert_eq!(
        storage.head(&key).await.expect("head"),
        None,
        "an absent key is an answer, not a failure"
    );

    storage
        .put(&key, vec![0_u8; 1234], "application/octet-stream")
        .await
        .expect("put");
    assert_eq!(storage.head(&key).await.expect("head"), Some(1234));
}

#[tokio::test]
async fn delete_removes_the_object() {
    let storage = store(TTL).await;
    let key = key();

    storage
        .put(&key, b"gone soon".to_vec(), "text/plain")
        .await
        .expect("put");
    storage.delete(&key).await.expect("delete");

    assert_eq!(storage.head(&key).await.expect("head"), None);
    assert!(matches!(storage.get(&key).await, Err(Error::NotFound)));
}

// --------------------------------------------------------------- signed URLs

#[tokio::test]
async fn a_signed_get_really_fetches_the_bytes() {
    let storage = store(TTL).await;
    let key = key();
    storage
        .put(&key, b"through a signed url".to_vec(), "text/plain")
        .await
        .expect("put");

    let url = storage.presign_get(&key).await.expect("presign");
    let body = reqwest::get(&url)
        .await
        .expect("the signed url is reachable")
        .error_for_status()
        .expect("the signature is accepted")
        .bytes()
        .await
        .expect("bytes");

    assert_eq!(body.as_ref(), b"through a signed url");
}

#[tokio::test]
async fn a_signed_put_really_uploads() {
    let storage = store(TTL).await;
    let key = key();

    let url = storage
        .presign_put(&key, "text/plain")
        .await
        .expect("presign");
    reqwest::Client::new()
        .put(&url)
        .header("content-type", "text/plain")
        .body("uploaded by the client")
        .send()
        .await
        .expect("the signed url is reachable")
        .error_for_status()
        .expect("the signature is accepted");

    assert_eq!(
        storage.get(&key).await.expect("get"),
        b"uploaded by the client",
        "bytes must never travel through the API itself"
    );
}

#[tokio::test]
async fn a_signed_url_stops_working_once_it_expires() {
    let storage = store(Duration::from_secs(1)).await;
    let key = key();
    storage
        .put(&key, b"briefly yours".to_vec(), "text/plain")
        .await
        .expect("put");

    let url = storage.presign_get(&key).await.expect("presign");
    tokio::time::sleep(Duration::from_secs(3)).await;

    let refused = reqwest::get(&url).await.expect("reachable");
    assert!(
        refused.status().is_client_error(),
        "an expiry that never expires is a permanent public url, not a grant"
    );
}

#[tokio::test]
async fn a_signed_url_pointed_at_another_key_is_refused() {
    let storage = store(TTL).await;
    let mine = key();
    let theirs = key();
    storage
        .put(&mine, b"mine".to_vec(), "text/plain")
        .await
        .expect("put");
    storage
        .put(&theirs, b"theirs".to_vec(), "text/plain")
        .await
        .expect("put");

    let url = storage.presign_get(&mine).await.expect("presign");
    let tampered = url.replace(&mine, &theirs);
    assert_ne!(
        tampered, url,
        "the key must appear in the url for this to test anything"
    );

    let refused = reqwest::get(&tampered).await.expect("reachable");
    assert!(
        refused.status().is_client_error(),
        "a signature covers the key, so swapping it must not grant access"
    );
}
