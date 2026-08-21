use std::time::Duration;

use aws_sdk_s3::Client;
use aws_sdk_s3::config::{Credentials, Region};
use aws_sdk_s3::error::SdkError;
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::types::{Delete, ObjectIdentifier};

const BATCH: usize = 1000;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("no object at that key")]
    NotFound,
    #[error("the object store refused the request")]
    Rejected,
    #[error("the object store is unreachable")]
    Unavailable,
}

#[derive(Clone)]
pub struct Settings {
    pub endpoint: String,
    pub region: String,
    pub bucket: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub path_style: bool,
    pub presign_ttl: Duration,
}

impl std::fmt::Debug for Settings {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("Settings")
            .field("endpoint", &self.endpoint)
            .field("region", &self.region)
            .field("bucket", &self.bucket)
            .field("access_key_id", &"[redacted]")
            .field("secret_access_key", &"[redacted]")
            .field("path_style", &self.path_style)
            .field("presign_ttl", &self.presign_ttl)
            .finish()
    }
}

#[derive(Clone)]
pub struct Storage {
    client: Client,
    bucket: String,
    presign_ttl: Duration,
}

impl std::fmt::Debug for Storage {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("Storage")
            .field("bucket", &self.bucket)
            .finish_non_exhaustive()
    }
}

impl Storage {
    #[must_use]
    pub fn new(settings: &Settings) -> Self {
        let credentials = Credentials::new(
            &settings.access_key_id,
            &settings.secret_access_key,
            None,
            None,
            "wardrobe",
        );
        let config = aws_sdk_s3::Config::builder()
            .behavior_version_latest()
            .http_client(
                aws_smithy_http_client::Builder::new()
                    .tls_provider(aws_smithy_http_client::tls::Provider::Rustls(
                        aws_smithy_http_client::tls::rustls_provider::CryptoMode::Ring,
                    ))
                    .build_https(),
            )
            .region(Region::new(settings.region.clone()))
            .endpoint_url(&settings.endpoint)
            .credentials_provider(credentials)
            .force_path_style(settings.path_style)
            .build();

        Self {
            client: Client::from_conf(config),
            bucket: settings.bucket.clone(),
            presign_ttl: settings.presign_ttl,
        }
    }

    /// # Errors
    ///
    /// Returns [`Error::Rejected`] when the store refuses the request.
    pub async fn ensure_bucket(&self) -> Result<(), Error> {
        if self
            .client
            .head_bucket()
            .bucket(&self.bucket)
            .send()
            .await
            .is_ok()
        {
            return Ok(());
        }
        if self
            .client
            .create_bucket()
            .bucket(&self.bucket)
            .send()
            .await
            .is_ok()
        {
            return Ok(());
        }

        self.client
            .head_bucket()
            .bucket(&self.bucket)
            .send()
            .await
            .map(|_| ())
            .map_err(|error| classify(&error))
    }

    /// # Errors
    ///
    /// Returns [`Error::Rejected`] when the store refuses the write.
    pub async fn put(&self, key: &str, bytes: Vec<u8>, content_type: &str) -> Result<(), Error> {
        self.client
            .put_object()
            .bucket(&self.bucket)
            .key(key)
            .content_type(content_type)
            .body(ByteStream::from(bytes))
            .send()
            .await
            .map(|_| ())
            .map_err(|error| classify(&error))
    }

    /// # Errors
    ///
    /// Returns [`Error::NotFound`] when nothing is stored at that key.
    pub async fn get(&self, key: &str) -> Result<Vec<u8>, Error> {
        let object = self
            .client
            .get_object()
            .bucket(&self.bucket)
            .key(key)
            .send()
            .await
            .map_err(|error| classify(&error))?;

        object
            .body
            .collect()
            .await
            .map(|body| body.into_bytes().to_vec())
            .map_err(|_| Error::Unavailable)
    }

    /// # Errors
    ///
    /// Returns [`Error::Rejected`] when the store refuses the request. A key
    /// that holds nothing is reported as `Ok(None)`, not as an error.
    pub async fn head(&self, key: &str) -> Result<Option<u64>, Error> {
        match self
            .client
            .head_object()
            .bucket(&self.bucket)
            .key(key)
            .send()
            .await
        {
            Ok(object) => Ok(Some(
                object.content_length().unwrap_or_default().unsigned_abs(),
            )),
            Err(error) => match classify(&error) {
                Error::NotFound => Ok(None),
                other => Err(other),
            },
        }
    }

    /// # Errors
    ///
    /// Returns [`Error::Rejected`] when the store refuses the delete.
    pub async fn delete(&self, key: &str) -> Result<(), Error> {
        self.client
            .delete_object()
            .bucket(&self.bucket)
            .key(key)
            .send()
            .await
            .map(|_| ())
            .map_err(|error| refusal(&error))
    }

    /// # Errors
    ///
    /// Returns [`Error::Rejected`] when the store refuses any key. Deleting a
    /// key that holds nothing succeeds, so a retry is safe.
    pub async fn delete_many(&self, keys: &[String]) -> Result<(), Error> {
        for batch in keys.chunks(BATCH) {
            let objects = batch
                .iter()
                .map(|key| ObjectIdentifier::builder().key(key).build())
                .collect::<Result<Vec<_>, _>>()
                .map_err(|_| Error::Rejected)?;
            let request = Delete::builder()
                .set_objects(Some(objects))
                .build()
                .map_err(|_| Error::Rejected)?;

            let outcome = self
                .client
                .delete_objects()
                .bucket(&self.bucket)
                .delete(request)
                .send()
                .await
                .map_err(|error| refusal(&error))?;

            if !outcome.errors().is_empty() {
                return Err(Error::Rejected);
            }
        }
        Ok(())
    }

    /// # Errors
    ///
    /// Returns [`Error::Rejected`] when the request cannot be signed.
    pub async fn presign_get(&self, key: &str) -> Result<String, Error> {
        self.client
            .get_object()
            .bucket(&self.bucket)
            .key(key)
            .presigned(self.presigning()?)
            .await
            .map(|request| request.uri().to_owned())
            .map_err(|error| classify(&error))
    }

    /// # Errors
    ///
    /// Returns [`Error::Rejected`] when the request cannot be signed.
    pub async fn presign_put(&self, key: &str, content_type: &str) -> Result<String, Error> {
        self.client
            .put_object()
            .bucket(&self.bucket)
            .key(key)
            .content_type(content_type)
            .presigned(self.presigning()?)
            .await
            .map(|request| request.uri().to_owned())
            .map_err(|error| classify(&error))
    }

    fn presigning(&self) -> Result<PresigningConfig, Error> {
        PresigningConfig::expires_in(self.presign_ttl).map_err(|_| Error::Rejected)
    }

    #[must_use]
    pub fn presign_ttl(&self) -> Duration {
        self.presign_ttl
    }
}

fn refusal<E>(error: &SdkError<E>) -> Error {
    match classify(error) {
        Error::NotFound => Error::Rejected,
        other => other,
    }
}

fn classify<E>(error: &SdkError<E>) -> Error {
    match error {
        SdkError::ServiceError(service) => {
            if service.raw().status().as_u16() == 404 {
                Error::NotFound
            } else {
                Error::Rejected
            }
        }
        SdkError::TimeoutError(_) | SdkError::DispatchFailure(_) => Error::Unavailable,
        _ => Error::Rejected,
    }
}
