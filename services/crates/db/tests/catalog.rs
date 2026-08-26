use sqlx::PgPool;
use uuid::{Uuid, uuid};

const FREESTYLE: Uuid = uuid!("019205f0-0000-7000-8000-000000000001");

#[sqlx::test(migrations = "../../migrations")]
async fn the_curated_catalog_is_seeded(pool: PgPool) -> sqlx::Result<()> {
    let cards: Vec<(Uuid, String, String, Option<Uuid>)> =
        sqlx::query_as("select id, source, locale, account_id from challenge_card order by id")
            .fetch_all(&pool)
            .await?;

    assert!(
        !cards.is_empty(),
        "an empty catalog breaks completeChallenge's card_id foreign key on every fresh database"
    );
    assert!(
        cards.iter().any(|(id, _, _, _)| *id == FREESTYLE),
        "freestyle completions bind this fixed id"
    );
    assert!(
        cards.iter().all(|(_, source, _, _)| source == "curated"),
        "seeded rows are the permanent fallback catalog (FR-008)"
    );
    assert!(
        cards.iter().all(|(_, _, _, account)| account.is_none()),
        "the curated catalog is global; an account-scoped seed would leak between users"
    );
    Ok(())
}
