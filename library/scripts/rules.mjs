// Rules shared by the index builder (reviewed entries) and Enterm's Library server (community shares).
// Zero dependencies, Node 20+.

export const PROGRAMS = ["claude", "codex", "gemini", "opencode", "copilot", "cursor"];
export const RACE_PROGRAMS = ["claude", "codex", "gemini"]; // the programs Enterm can race

// Phrases a prompt in this library must never contain. They are bait for prompt injection or
// plainly destructive; a maintainer can still reject anything else by hand.
export const FORBIDDEN = [
  [/ignore (all |any )?(the )?(previous|prior|above) (instructions|messages|rules)/i, "prompt-injection bait"],
  [/disregard (all |any )?(the )?(previous|prior|above|system)/i, "prompt-injection bait"],
  [/(önceki|yukarıdaki) (tüm |bütün )?talimatları (yok say|görmezden gel|unut)/i, "prompt-injection bait"],
  [/rm\s+-rf\s+(\/|~|\$HOME)(\s|$)/i, "destructive command"],
  [/(curl|wget)[^\n|]*\|\s*(ba|z)?sh/i, "pipes a download into a shell"],
  [/--dangerously-skip-permissions|--yolo\b|--dangerously-bypass/i, "turns off the agent's permission checks"],
  [/git push\s+(-f|--force)/i, "force push"],
  [/base64\s+(-d|--decode)[^\n]*\|\s*(ba|z)?sh/i, "runs hidden code"],
];

// Things that look like credentials. A shared prompt must not carry one.
export const SECRETS = [
  [/\bsk-(ant-|proj-)?[A-Za-z0-9_-]{20,}/, "an API key"],
  [/\bgh[pousr]_[A-Za-z0-9]{30,}/, "a GitHub token"],
  [/\bAKIA[0-9A-Z]{16}\b/, "an AWS key"],
  [/\bAIza[0-9A-Za-z_-]{35}\b/, "a Google API key"],
  [/\bxox[abposr]-[A-Za-z0-9-]{10,}/, "a Slack token"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "a private key"],
];

/** The first rule a text breaks, as a short reason, or null. */
export function unsafe(text) {
  for (const [re, why] of FORBIDDEN) if (re.test(text)) return `contains ${why} (${text.match(re)[0]})`;
  for (const [re, why] of SECRETS) if (re.test(text)) return `contains what looks like ${why}`;
  return null;
}

/** The tags TAGS.md allows: its table rows like | `review` | ... |. */
export function parseTags(markdown) {
  return [...markdown.matchAll(/^\|\s*`([a-z0-9-]+)`\s*\|/gm)].map((m) => m[1]);
}
