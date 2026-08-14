//! Prints the `OpenAPI` document. `make backend-openapi` redirects it into
//! `services/openapi.json`, which is committed so the iOS side and any client
//! generator can read the contract without running the server.

fn main() {
    print!("{}", wardrobe_api::openapi::document());
}
