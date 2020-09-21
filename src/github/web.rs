/// holds the address to a shared actor that manages all the benchmarking
/// we need to restrict the app to a single actor to ensure that we don't run more than one bench
/// at a time
pub struct AppState {
    pub actor: actix::Addr<crate::bench::actor::Actor>,
}

/// https://docs.github.com/en/developers/webhooks-and-events/webhook-events-and-payloads#push
#[derive(serde::Deserialize, Debug)]
pub(crate) struct PushEvent {
    #[serde(rename = "ref")]
    // The full git ref that was pushed. Example: refs/heads/master.
    pub reference: String,
    // The SHA of the most recent commit on ref before the push.
    pub before: String,
    // The SHA of the most recent commit on ref after the push.
    pub after: String,
}

pub(crate) async fn push(
    data: actix_web::web::Data<crate::bench::web::AppState>,
    request: actix_web::HttpRequest,
    body: String,
) -> impl actix_web::Responder {
    match super::signature::verify(&request, &body) {
        Ok(_) => {
            let push_event: Result<PushEvent, ()> = serde_json::from_str(&body).map_err(|_| ());
            match push_event {
                Ok(push) => {
                    data.actor
                        .do_send(crate::bench::actor::Commit::from(push.after.clone()));
                    actix_web::Responder::with_status("", actix_web::http::StatusCode::ACCEPTED)
                }
                Err(_) => {
                    actix_web::Responder::with_status("", actix_web::http::StatusCode::BAD_REQUEST)
                }
            }
        }
        Err(_) => actix_web::Responder::with_status("", actix_web::http::StatusCode::FORBIDDEN),
    }
}
