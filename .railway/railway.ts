import { defineRailway, github, postgres, preserve, project, service } from "railway/iac";

export default defineRailway(() => {
  const db = postgres("postgres");
  const source = github("ayungavis/wardrobe-app", {
    branch: "feat/llm-service",
    rootDirectory: "services",
  });

  const api = service("api", {
    source,
    healthcheck: "/health",
    healthcheckTimeout: 60,
    env: {
      DATABASE_URL: db.env.DATABASE_URL,
      TRUSTED_PROXY_HOPS: "1",
      APPLE_BUNDLE_ID: "com.ayungavis.WardrobeApp",
      SENTRY_ENVIRONMENT: "production",
      SENTRY_DSN: preserve(),
      S3_ENDPOINT: preserve(),
      S3_REGION: "auto",
      S3_BUCKET: preserve(),
      S3_ACCESS_KEY_ID: preserve(),
      S3_SECRET_ACCESS_KEY: preserve(),
    },
  });

  const worker = service("worker", {
    source,
    start: "wardrobe-worker",
    env: {
      DATABASE_URL: db.env.DATABASE_URL,
      SENTRY_ENVIRONMENT: "production",
      SENTRY_DSN: preserve(),
      S3_ENDPOINT: preserve(),
      S3_REGION: "auto",
      S3_BUCKET: preserve(),
      S3_ACCESS_KEY_ID: preserve(),
      S3_SECRET_ACCESS_KEY: preserve(),
      OPENROUTER_API_KEY: preserve(),
    },
  });

  return project("wardrobe-app", { resources: [api, worker, db] });
});
