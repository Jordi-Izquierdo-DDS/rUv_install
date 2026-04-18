// @ruvector/ruvllm-native — NAPI binding for ruvllm ReasoningBank + VerdictAnalyzer
// Built by ruflo v5 Fix 18 via scripts/rebuild-ruvllm.sh
const { platform, arch } = process;
const triples = {
  'linux-x64': 'ruvllm.linux-x64-gnu.node',
};
const key = `${platform}-${arch}`;
const file = triples[key];
if (!file) throw new Error(`@ruvector/ruvllm-native: unsupported platform ${key}`);
module.exports = require(`./${file}`);
