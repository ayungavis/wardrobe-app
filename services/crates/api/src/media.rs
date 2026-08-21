use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_storage::Storage;

use crate::error::Error;

pub const KINDS: &[&str] = &[
    "original",
    "derivative",
    "cutout",
    "illustration",
    "document",
    "history",
];

pub const MAX_CONTENT_TYPE: usize = 100;

pub struct Reservation {
    pub media_id: Uuid,
    pub kind: String,
    pub content_type: String,
    pub byte_size: Option<i64>,
}

pub struct Granted {
    pub media_id: Uuid,
    pub url: String,
    pub expires_at: DateTime<Utc>,
    pub byte_size: Option<i64>,
}

#[derive(sqlx::FromRow)]
struct Stored {
    account_id: Uuid,
    storage_key: String,
    content_type: String,
    byte_size: Option<i64>,
    uploaded_at: Option<DateTime<Utc>>,
}

fn expires_at(storage: &Storage) -> DateTime<Utc> {
    Utc::now()
        + chrono::Duration::from_std(storage.presign_ttl())
            .unwrap_or_else(|_| chrono::Duration::seconds(300))
}

async fn stored(pool: &PgPool, media_id: Uuid, account_id: Uuid) -> Result<Option<Stored>, Error> {
    let found: Option<Stored> = sqlx::query_as(
        "select account_id, storage_key, content_type, byte_size, uploaded_at
           from media_object
          where id = $1",
    )
    .bind(media_id)
    .fetch_optional(pool)
    .await?;

    match found {
        Some(row) if row.account_id != account_id => Err(Error::Conflict),
        other => Ok(other),
    }
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for an unknown kind or an oversize content
/// type, and [`Error::Conflict`] when the id belongs to another account.
pub async fn reserve(
    pool: &PgPool,
    storage: &Storage,
    account_id: Uuid,
    request: &Reservation,
) -> Result<Granted, Error> {
    if !KINDS.contains(&request.kind.as_str()) || request.content_type.len() > MAX_CONTENT_TYPE {
        return Err(Error::BadRequest);
    }

    let key = format!("{account_id}/{}/{}", request.kind, request.media_id);
    let content_type = if let Some(row) = stored(pool, request.media_id, account_id).await? {
        row.content_type
    } else {
        sqlx::query(
            "insert into media_object
                     (id, account_id, kind, storage_key, content_type, byte_size)
                 values ($1, $2, $3, $4, $5, $6)",
        )
        .bind(request.media_id)
        .bind(account_id)
        .bind(&request.kind)
        .bind(&key)
        .bind(&request.content_type)
        .bind(request.byte_size)
        .execute(pool)
        .await?;
        request.content_type.clone()
    };

    Ok(Granted {
        media_id: request.media_id,
        url: storage.presign_put(&key, &content_type).await?,
        expires_at: expires_at(storage),
        byte_size: request.byte_size,
    })
}

/// # Errors
///
/// Returns [`Error::NotFound`] when the account has no such media, or when the
/// bytes were never uploaded.
pub async fn download(
    pool: &PgPool,
    storage: &Storage,
    account_id: Uuid,
    media_id: Uuid,
) -> Result<Granted, Error> {
    let row = match stored(pool, media_id, account_id).await {
        Ok(Some(row)) => row,
        Ok(None) | Err(Error::Conflict) => return Err(Error::NotFound),
        Err(other) => return Err(other),
    };

    let byte_size = if row.uploaded_at.is_some() {
        row.byte_size
    } else {
        let Some(size) = storage.head(&row.storage_key).await? else {
            return Err(Error::NotFound);
        };
        let size = i64::try_from(size).unwrap_or(i64::MAX);
        sqlx::query("update media_object set uploaded_at = now(), byte_size = $2 where id = $1")
            .bind(media_id)
            .bind(size)
            .execute(pool)
            .await?;
        Some(size)
    };

    Ok(Granted {
        media_id,
        url: storage.presign_get(&row.storage_key).await?,
        expires_at: expires_at(storage),
        byte_size,
    })
}

impl From<wardrobe_storage::Error> for Error {
    fn from(error: wardrobe_storage::Error) -> Self {
        match error {
            wardrobe_storage::Error::NotFound => Self::NotFound,
            wardrobe_storage::Error::Rejected => {
                tracing::error!(storage.kind = "rejected", "object store failure");
                Self::Unavailable
            }
            wardrobe_storage::Error::Unavailable => {
                tracing::error!(storage.kind = "unreachable", "object store failure");
                Self::Unavailable
            }
        }
    }
}
