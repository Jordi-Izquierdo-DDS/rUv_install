//! Simplified NAPI-RS bindings for ruvllm ReasoningBank + VerdictAnalyzer
//! Enable with feature flag: `napi`
//!
//! Added by ruflo v5 Fix 18 — exposes the "car" (ruvllm) not just the "motor" (sona).
//! Provides VerdictAnalyzer for quality judgment + PatternStore with full metadata.

#![cfg(feature = "napi")]

use napi_derive::napi;
use std::sync::Mutex;

use crate::reasoning_bank::{
    ReasoningBank, ReasoningBankConfig,
    trajectory::{Trajectory, TrajectoryId, TrajectoryStep, TrajectoryMetadata, StepMetadata, StepOutcome},
    verdicts::{Verdict, RootCause, VerdictAnalysis},
    pattern_store::{Pattern, PatternSearchResult},
};

/// ruvllm ReasoningBank wrapper for Node.js
#[napi]
pub struct JsReasoningBank {
    inner: Mutex<ReasoningBank>,
}

#[napi]
impl JsReasoningBank {
    /// Create a new ReasoningBank
    #[napi(constructor)]
    pub fn new(embedding_dim: u32, storage_path: String) -> napi::Result<Self> {
        let dim = embedding_dim as usize;
        let mut config = ReasoningBankConfig {
            embedding_dim: dim,
            storage_path,
            ..Default::default()
        };
        config.pattern_config.embedding_dim = dim;
        let bank = ReasoningBank::new(config)
            .map_err(|e| napi::Error::from_reason(format!("ReasoningBank init: {}", e)))?;
        Ok(Self { inner: Mutex::new(bank) })
    }

    /// Store a trajectory and get its verdict analysis
    #[napi]
    pub fn store_and_analyze(
        &self,
        query_embedding: Vec<f64>,
        steps: Vec<JsTrajectoryStep>,
        quality: f64,
        model_route: Option<String>,
    ) -> napi::Result<JsVerdictAnalysis> {
        let emb: Vec<f32> = query_embedding.iter().map(|&x| x as f32).collect();

        let traj_steps: Vec<TrajectoryStep> = steps.iter().enumerate().map(|(i, s)| {
            TrajectoryStep {
                index: i,
                action: s.action.clone(),
                rationale: s.rationale.clone(),
                outcome: if s.success {
                    StepOutcome::Success
                } else {
                    let err = if s.error.is_empty() { "unknown".to_string() } else { s.error.clone() };
                    StepOutcome::Failure { error: err }
                },
                confidence: s.confidence.unwrap_or(0.5) as f32,
                latency_ms: s.latency_ms.unwrap_or(0) as u64,
                timestamp: chrono::Utc::now(),
                context_embedding: None,
                metadata: None,
            }
        }).collect();

        let verdict = if quality >= 0.5 {
            Verdict::Success
        } else {
            Verdict::Failure(RootCause::InsufficientContext {
                missing: vec!["quality below threshold".into()],
            })
        };

        let mut traj_meta = TrajectoryMetadata::default();
        if let Some(ref route) = model_route {
            traj_meta.models_used.push(route.clone());
        }

        let trajectory = Trajectory {
            id: TrajectoryId::new(),
            uuid: uuid::Uuid::new_v4(),
            query_embedding: emb,
            response_embedding: None,
            steps: traj_steps,
            verdict: verdict.clone(),
            quality: quality as f32,
            total_latency_ms: 0,
            started_at: chrono::Utc::now(),
            completed_at: chrono::Utc::now(),
            metadata: traj_meta,
            lessons: vec![],
        };

        // Analyze verdict
        let bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let analysis = bank.analyze_verdict(&trajectory);

        // Store trajectory
        drop(bank);
        let mut bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let _ = bank.store_trajectory(trajectory);

        Ok(JsVerdictAnalysis::from(analysis))
    }

    /// Analyze a trajectory without storing it
    #[napi]
    pub fn analyze_only(
        &self,
        steps: Vec<JsTrajectoryStep>,
        quality: f64,
    ) -> napi::Result<JsVerdictAnalysis> {
        let traj_steps: Vec<TrajectoryStep> = steps.iter().enumerate().map(|(i, s)| {
            TrajectoryStep {
                index: i,
                action: s.action.clone(),
                rationale: s.rationale.clone(),
                outcome: if s.success { StepOutcome::Success }
                else { let err = if s.error.is_empty() { "unknown".to_string() } else { s.error.clone() }; StepOutcome::Failure { error: err } },
                confidence: s.confidence.unwrap_or(0.5) as f32,
                latency_ms: s.latency_ms.unwrap_or(0) as u64,
                timestamp: chrono::Utc::now(),
                context_embedding: None,
                metadata: None,
            }
        }).collect();

        let verdict = if quality >= 0.5 { Verdict::Success }
        else { Verdict::Failure(RootCause::InsufficientContext { missing: vec![] }) };

        let trajectory = Trajectory {
            id: TrajectoryId::new(), uuid: uuid::Uuid::new_v4(),
            query_embedding: vec![], response_embedding: None,
            steps: traj_steps, verdict, quality: quality as f32,
            total_latency_ms: 0, started_at: chrono::Utc::now(), completed_at: chrono::Utc::now(),
            metadata: TrajectoryMetadata::default(), lessons: vec![],
        };

        let bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        Ok(JsVerdictAnalysis::from(bank.analyze_verdict(&trajectory)))
    }

    /// Search for similar patterns by embedding
    #[napi]
    pub fn search_similar(&self, embedding: Vec<f64>, k: u32) -> napi::Result<Vec<JsPattern>> {
        let emb: Vec<f32> = embedding.iter().map(|&x| x as f32).collect();
        let bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let results = bank.search_similar(&emb, k as usize)
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        Ok(results.into_iter().map(JsPattern::from_result).collect())
    }

    /// Prune low-quality patterns
    #[napi]
    pub fn prune_low_quality(&self, min_quality: f64) -> napi::Result<u32> {
        let mut bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let pruned = bank.prune_low_quality(min_quality as f32)
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        Ok(pruned as u32)
    }

    /// Export all patterns as JSON
    #[napi]
    pub fn export_patterns(&self) -> napi::Result<String> {
        let bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let patterns = bank.export_patterns()
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        serde_json::to_string(&patterns).map_err(|e| napi::Error::from_reason(e.to_string()))
    }

    /// Import patterns from JSON
    #[napi]
    pub fn import_patterns(&self, json: String) -> napi::Result<u32> {
        let patterns: Vec<Pattern> = serde_json::from_str(&json)
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let mut bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        let count = bank.import_patterns(patterns)
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        Ok(count as u32)
    }

    /// Get statistics as JSON
    #[napi]
    pub fn stats(&self) -> napi::Result<String> {
        let bank = self.inner.lock().map_err(|e| napi::Error::from_reason(e.to_string()))?;
        serde_json::to_string(&bank.stats()).map_err(|e| napi::Error::from_reason(e.to_string()))
    }
}

// ─── JS-friendly types ─────────────────────────────────────────────────────

/// Trajectory step — NAPI-RS 2.16 doesn't convert JS null → Option<String>::None
/// in #[napi(object)] structs. Use String with empty = no error as workaround.
#[napi(object)]
pub struct JsTrajectoryStep {
    pub action: String,
    pub success: bool,
    pub confidence: Option<f64>,
    pub latency_ms: Option<i64>,
    /// Empty string = no error. NAPI-RS null handling limitation.
    pub error: String,
    pub rationale: String,
}

#[napi(object)]
pub struct JsVerdictAnalysis {
    pub quality_score: f64,
    pub is_successful: bool,
    pub root_cause: Option<String>,
    pub contributing_factors: Vec<String>,
    pub recovery_strategies: Vec<String>,
    pub lessons: Vec<String>,
    pub pattern_category: String,
    pub confidence: f64,
    pub improvements: Vec<String>,
}

impl From<VerdictAnalysis> for JsVerdictAnalysis {
    fn from(a: VerdictAnalysis) -> Self {
        Self {
            quality_score: a.verdict.quality_score() as f64,
            is_successful: a.verdict.is_success(),
            root_cause: a.root_cause.map(|r| format!("{:?}", r)),
            contributing_factors: a.contributing_factors,
            recovery_strategies: a.recovery_strategies.iter().map(|s| s.description.clone()).collect(),
            lessons: a.lessons,
            pattern_category: format!("{:?}", a.pattern_category),
            confidence: a.confidence as f64,
            improvements: a.improvements,
        }
    }
}

#[napi(object)]
pub struct JsPattern {
    pub id: String,
    pub embedding: Vec<f64>,
    pub category: String,
    pub confidence: f64,
    pub usage_count: u32,
    pub success_count: u32,
    pub avg_quality: f64,
    pub lessons: Vec<String>,
    pub example_actions: Vec<String>,
    pub tags: Vec<String>,
    pub source: String,
    pub similarity: f64,
}

impl JsPattern {
    fn from_result(r: PatternSearchResult) -> Self {
        Self {
            id: r.pattern.uuid.to_string(),
            embedding: r.pattern.embedding.iter().map(|&x| x as f64).collect(),
            category: format!("{:?}", r.pattern.category),
            confidence: r.pattern.confidence as f64,
            usage_count: r.pattern.usage_count,
            success_count: r.pattern.success_count,
            avg_quality: r.pattern.avg_quality as f64,
            lessons: r.pattern.lessons.clone(),
            example_actions: r.pattern.example_actions.clone(),
            tags: r.pattern.metadata.tags.clone(),
            source: r.pattern.metadata.source.clone(),
            similarity: r.similarity as f64,
        }
    }
}
