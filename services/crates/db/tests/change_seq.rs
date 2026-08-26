use sqlx::PgPool;
use uuid::Uuid;

async fn account(pool: &PgPool) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(id)
}

#[sqlx::test(migrations = "../../migrations")]
async fn concurrent_writers_never_receive_the_same_position(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;

    let mut writers = Vec::new();
    for _ in 0..16 {
        let pool = pool.clone();
        writers.push(tokio::spawn(async move {
            let mut tx = pool.begin().await.expect("a transaction");
            let seq = wardrobe_db::next_change_seq(&mut tx, account_id)
                .await
                .expect("a position");
            tx.commit().await.expect("a commit");
            seq
        }));
    }

    let mut issued = Vec::new();
    for writer in writers {
        issued.push(writer.await.expect("a finished writer"));
    }
    issued.sort_unstable();

    assert_eq!(
        issued,
        (1..=16).collect::<Vec<i64>>(),
        "the whole pull cursor rests on positions being unique and gapless per account"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_accounts_positions_do_not_disturb_anothers(pool: PgPool) -> sqlx::Result<()> {
    let first = account(&pool).await?;
    let second = account(&pool).await?;

    let mut conn = pool.acquire().await?;
    for _ in 0..3 {
        wardrobe_db::next_change_seq(&mut conn, first).await?;
    }
    let theirs = wardrobe_db::next_change_seq(&mut conn, second).await?;

    assert_eq!(
        theirs, 1,
        "the counter is per account, so a busy neighbour costs nothing"
    );
    Ok(())
}
