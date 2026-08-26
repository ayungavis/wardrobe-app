mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use chrono::Duration;
use sqlx::PgPool;
use uuid::Uuid;

use common::{
    body_json, call, call_with, call_without_storage, recorded, session, storage, storage_in,
};

// ------------------------------------------------------------------- fixtures

fn delete_me(token: &str) -> Request<Body> {
    Request::builder()
        .method("DELETE")
        .uri("/v1/users/me")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .expect("request")
}

struct Owned {
    token: String,
    account: Uuid,
    key: String,
    item: Uuid,
}

async fn owned(pool: &PgPool) -> sqlx::Result<Owned> {
    let (token, account) = session(pool, Duration::days(1), false).await?;
    let media = Uuid::now_v7();
    let key = format!("{account}/original/{media}");

    storage()
        .await
        .put(&key, b"a photo".to_vec(), "image/jpeg")
        .await
        .expect("the object lands");

    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, 'original', $3, 'image/jpeg')",
    )
    .bind(media)
    .bind(account)
    .bind(&key)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into photo (id, account_id, media_object_id, source, change_seq)
         values ($1, $2, $3, 'capture', 1)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(media)
    .execute(pool)
    .await?;

    let item = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq, deleted_at)
         values ($1, $2, 'top', 2, now())",
    )
    .bind(item)
    .bind(account)
    .execute(pool)
    .await?;

    Ok(Owned {
        token,
        account,
        key,
        item,
    })
}

async fn rows(pool: &PgPool, table: &str, account: Uuid) -> i64 {
    sqlx::query_scalar(&format!(
        "select count(*) from {table} where account_id = $1"
    ))
    .bind(account)
    .fetch_one(pool)
    .await
    .expect("count")
}

// ----------------------------------------------------------------- the happy path

#[sqlx::test(migrations = "../../migrations")]
async fn deleting_an_account_takes_its_rows_and_its_objects(pool: PgPool) -> sqlx::Result<()> {
    let mine = owned(&pool).await?;

    let response = call(pool.clone(), delete_me(&mine.token)).await;
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    for table in ["media_object", "photo", "wardrobe_item", "session"] {
        assert_eq!(
            rows(&pool, table, mine.account).await,
            0,
            "{table} survived"
        );
    }
    let account: i64 = sqlx::query_scalar("select count(*) from account where id = $1")
        .bind(mine.account)
        .fetch_one(&pool)
        .await?;
    assert_eq!(account, 0);

    assert_eq!(
        storage().await.head(&mine.key).await.expect("head"),
        None,
        "rows without objects is not deletion, it is a rename of the problem"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn deletion_outranks_a_tombstone(pool: PgPool) -> sqlx::Result<()> {
    let mine = owned(&pool).await?;
    call(pool.clone(), delete_me(&mine.token)).await;

    let left: i64 = sqlx::query_scalar("select count(*) from wardrobe_item where id = $1")
        .bind(mine.item)
        .fetch_one(&pool)
        .await?;
    assert_eq!(
        left, 0,
        "a soft-deleted row is still a row, and FR-071 says none remain"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_token_stops_working_afterwards(pool: PgPool) -> sqlx::Result<()> {
    let mine = owned(&pool).await?;
    call(pool.clone(), delete_me(&mine.token)).await;

    let response = call(
        pool.clone(),
        Request::builder()
            .uri("/v1/whoami")
            .header("authorization", format!("Bearer {}", mine.token))
            .body(Body::empty())
            .expect("request"),
    )
    .await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_account_is_untouched(pool: PgPool) -> sqlx::Result<()> {
    let mine = owned(&pool).await?;
    let theirs = owned(&pool).await?;

    call(pool.clone(), delete_me(&mine.token)).await;

    assert_eq!(rows(&pool, "photo", theirs.account).await, 1);
    assert!(
        storage()
            .await
            .head(&theirs.key)
            .await
            .expect("head")
            .is_some()
    );
    Ok(())
}

// ------------------------------------------------------------ when it cannot

#[sqlx::test(migrations = "../../migrations")]
async fn a_store_that_refuses_leaves_everything_retryable(pool: PgPool) -> sqlx::Result<()> {
    let mine = owned(&pool).await?;

    let response: Response = call_with(
        pool.clone(),
        delete_me(&mine.token),
        Some(storage_in("a-bucket-that-does-not-exist")),
    )
    .await;
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(body_json(response).await["error"]["code"], "unavailable");

    for table in ["media_object", "photo", "session"] {
        assert_eq!(
            rows(&pool, table, mine.account).await,
            1,
            "{table} must survive so the caller can try again"
        );
    }

    let second = call(pool.clone(), delete_me(&mine.token)).await;
    assert_eq!(
        second.status(),
        StatusCode::NO_CONTENT,
        "the retry is the whole point of leaving the rows behind"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn without_a_store_an_account_holding_objects_is_not_deleted(
    pool: PgPool,
) -> sqlx::Result<()> {
    let mine = owned(&pool).await?;

    let response = call_without_storage(pool.clone(), delete_me(&mine.token)).await;
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(rows(&pool, "media_object", mine.account).await, 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn deleting_without_a_token_is_unauthenticated(pool: PgPool) {
    let response = call(
        pool,
        Request::builder()
            .method("DELETE")
            .uri("/v1/users/me")
            .body(Body::empty())
            .expect("request"),
    )
    .await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_refused_store_is_recorded_rather_than_swallowed(pool: PgPool) -> sqlx::Result<()> {
    common::events();
    let mine = owned(&pool).await?;

    call_with(
        pool.clone(),
        delete_me(&mine.token),
        Some(storage_in("a-bucket-that-does-not-exist")),
    )
    .await;

    assert!(
        recorded("storage.kind"),
        "a 503 with no log line means a misconfigured bucket looks exactly like a healthy one"
    );
    Ok(())
}
