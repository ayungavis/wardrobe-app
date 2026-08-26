use sqlx::PgPool;

#[sqlx::test(migrations = "../../migrations")]
async fn every_image_capability_leads_with_seedream_5_0_pro(pool: PgPool) -> sqlx::Result<()> {
    for capability in ["illustration", "outfit_template"] {
        let row: Option<(String, Option<String>)> = sqlx::query_as(
            "select active_model, alternate_model from ai_model_config where capability = $1",
        )
        .bind(capability)
        .fetch_optional(&pool)
        .await?;

        let (active, alternate) = row.unwrap_or_else(|| {
            panic!("{capability} has no configuration, so the worker cannot run it at all")
        });
        assert_eq!(
            active, "bytedance-seed/seedream-5-0-pro",
            "{capability} must lead with the model we actually use"
        );
        assert_eq!(alternate.as_deref(), Some("bytedance-seed/seedream-4.5"));
    }
    Ok(())
}
