/* @ruvector/ruvllm-native — Fix 18 NAPI types */

export interface JsTrajectoryStep {
  action: string
  success: boolean
  confidence?: number
  latencyMs?: number
  error?: string
  rationale?: string
}

export interface JsVerdictAnalysis {
  qualityScore: number
  isSuccessful: boolean
  rootCause?: string
  contributingFactors: string[]
  recoveryStrategies: string[]
  lessons: string[]
  patternCategory: string
  confidence: number
  improvements: string[]
}

export interface JsPattern {
  id: string
  embedding: number[]
  category: string
  confidence: number
  usageCount: number
  successCount: number
  avgQuality: number
  lessons: string[]
  exampleActions: string[]
  tags: string[]
  source: string
  similarity: number
}

export declare class JsReasoningBank {
  constructor(embeddingDim: number, storagePath: string)
  storeAndAnalyze(queryEmbedding: number[], steps: JsTrajectoryStep[], quality: number, modelRoute?: string): JsVerdictAnalysis
  analyzeOnly(steps: JsTrajectoryStep[], quality: number): JsVerdictAnalysis
  searchSimilar(embedding: number[], k: number): JsPattern[]
  pruneLowQuality(minQuality: number): number
  exportPatterns(): string
  importPatterns(json: string): number
  stats(): string
}
