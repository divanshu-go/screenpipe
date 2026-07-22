# 02. Provider x harness presets (CEO ask)

Status: not started. Research verified 2026-07-20 against org source clones in external/acp.

## Goal
One preset = model PROVIDER (ollama, anthropic key, openai key, screenpipe cloud, custom) x HARNESS (built-in chat, pi, codex, claude code, opencode, gemini, cursor). Examples: "ollama with codex", "screenpipe cloud with claude".

## Where the coupling lives today
- store.rs AIProviderType mixes providers with harness choices ("acp"); acpAgent rides on AIPreset.
- buildProviderConfig sets backend:"acp" iff provider === "acp" (use-pi-session-lifecycle.ts:190-196); pi_start_inner branches on backend (pi.rs:1851).
- The wire type PiProviderConfig is ALREADY orthogonal: it carries backend AND provider/url/model/apiKey (pi.rs:1368-1392); when backend=acp the provider fields are dead today.
- Raw pi provider config: generated models.json (openai->openai-byok, native-ollama->ollama, anthropic->anthropic-byok, screenpipe with inlined cloud JWT; pi.rs:1459-1523), --provider/--model flags, api-key envs (pi.rs:2331-2364).
- ACP config flows via SCREENPIPE_ACP_* env (pi.rs:2119-2161) into RuntimeConfig (acp_runtime.rs:146+).

## Per-harness BYO mechanism (source-verified)
- codex-acp: env only, no config file needed. MODEL_PROVIDER=<id> + CODEX_CONFIG='{"model_providers":{"ollama":{"name":"Ollama","base_url":"http://localhost:11434/v1","wire_api":"chat"}},"model":"..."}'. CODEX_CONFIG is JSON.parse'd and spread unvalidated. Reserved keys the adapter overwrites: projects, sandbox_workspace_write.writable_roots (merged), mcp_servers (replaced when client passes servers). Also DEFAULT_AUTH_REQUEST (auto-applied auth), INITIAL_AGENT_MODE (read-only|agent|agent-full-access); local providers can skip OpenAI auth (requiresOpenaiAuth false).
- claude-agent-acp: does NOT read ANTHROPIC_BASE_URL/API_KEY itself (transitively passes env to the CLI which does). First-class mechanism: gateway/providers flow. Requires clientCapabilities.auth._meta.gateway=true at initialize; then either the "gateway" auth method (client passes _meta.gateway.{baseUrl,headers} on authenticate) or the newer providers/list + providers/set (which takes precedence). CLAUDE_MODEL_CONFIG env (JSON {modelOverrides, availableModels}) remaps/restricts the model list, but is ignored entirely when _meta.claudeCode.options.settings is supplied in session/new.
- opencode: config file only (opencode.json provider block, @ai-sdk/openai-compatible + baseURL + models map); secrets referencable as {env:VAR} so values can still flow through AcpAgentConfig.env. Generate/merge before spawn; use merge-or-isolated-dir discipline (see pi models.json merge, pi.rs:1589-1615).
- gemini-cli: NO BYO (Google models only, stated policy). Account-bound.
- cursor: NO BYO, account-bound; model via --model arg at spawn only.
- pi: native path already does all providers.

## Cloud JWT constraint (do not weaken)
SCREENPIPE_API_KEY is stripped from every ACP process (pi.rs:2109, 2379-2381; acp_runtime.rs is_forbidden_acp_env + cloud_token_is_forbidden test) because adapters are third-party npm run via bun x with terminal rights. For screenpipe-cloud x harness: run a localhost proxy inside the trusted desktop process that injects the JWT server-side; hand adapters only the local base URL (claude via providers/set or gateway auth, codex via CODEX_CONFIG base_url). Requires the cloud gateway to speak the target protocol (Anthropic Messages for claude, OpenAI for codex).

## Change set
1. Schema: keep AIProviderType as pure providers; harness discriminator = explicit field or acpAgent.is_some(). Migration in sanitize_legacy_fields (store.rs:1464-1526): provider=="acp" -> {harness: acp, provider: "agent-default"} (new variant meaning "use the agent's own login"). Regenerate bindings.
2. Backend: in pi_start_inner's use_acp branch, translation table keyed by (agent_id, provider) -> adapter env/config as above. Fix the builtin-args gap (acp_runtime.rs:157-162): allow preset args to APPEND to builtin agent args so flag-based config works without custom commands.
3. UI: two rows in the preset editor: provider cards (unchanged) + harness picker (existing agent listbox). Grey out unsupported combos (gemini/cursor BYO). Gate model picker/diagnostics on harness, not provider.
4. Secrets story: injecting preset.apiKey into third-party adapters is provider-scoped exposure; surface in UI copy like the existing "use agents you trust" note.

## Risks
- Concurrent sessions writing generated configs: merge, never clobber.
- codex MCP name-collision filtering: client servers dropped if name exists in user codex config unless DISABLE_MCP_CONFIG_FILTERING=true.
