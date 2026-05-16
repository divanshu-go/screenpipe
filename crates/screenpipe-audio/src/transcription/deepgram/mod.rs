pub mod batch;

const DEFAULT_DEEPGRAM_API_URL: &str = "https://api.deepgram.com/v1/listen";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeepgramTranscriptionConfig {
    pub endpoint: String,
    pub auth_token: String,
    pub auth_header_prefix: &'static str,
}

impl DeepgramTranscriptionConfig {
    pub fn direct(api_key: String) -> Self {
        Self {
            endpoint: DEFAULT_DEEPGRAM_API_URL.to_string(),
            auth_token: api_key,
            auth_header_prefix: "Token",
        }
    }

    pub fn screenpipe_cloud(token: String) -> Self {
        Self {
            endpoint: "https://api.screenpi.pe/v1/listen".to_string(),
            auth_token: token,
            auth_header_prefix: "Bearer",
        }
    }

    pub fn is_ready(&self) -> bool {
        !self.endpoint.trim().is_empty() && !self.auth_token.trim().is_empty()
    }

    pub fn authorization_header(&self) -> String {
        format!("{} {}", self.auth_header_prefix, self.auth_token)
    }
}
