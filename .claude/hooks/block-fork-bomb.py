#!/usr/bin/env python3
"""PreToolUse hook: block fork-bomb-style Bash commands.

Reads the hook payload as JSON on stdin, inspects the Bash command, and
emits a PreToolUse "deny" decision if it matches a fork-bomb signature.
Anything else is passed through (exit 0, no output).

Detection is heuristic — a fork bomb is a recursive function that pipes
copies of itself into the background. We match that structural shape
rather than one literal string, so `:(){ :|:& };:` and named variants
like `f(){ f|f& };f` are both caught. This is a safety net, not a proof:
it deliberately errs toward catching the classic shapes.
"""
import json
import re
import sys

# A defined function whose body contains BOTH a pipe and a background '&'
# — e.g. `:(){ :|:& }` or `bomb(){ bomb|bomb& }`. The name may be the `:`
# builtin or a normal identifier.
FN_PIPE_BG = re.compile(r"[:\w]+\s*\(\s*\)\s*\{[^{}]*\|[^{}]*&[^{}]*\}")

# Redefining the `:` builtin as a function is essentially never legitimate
# and is the hallmark of the classic fork bomb.
COLON_FN = re.compile(r":\s*\(\s*\)\s*\{")

PATTERNS = (FN_PIPE_BG, COLON_FN)


def is_fork_bomb(command: str) -> bool:
    return any(p.search(command) for p in PATTERNS)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Malformed payload: don't block, let normal handling proceed.
        return 0

    command = (payload.get("tool_input") or {}).get("command", "") or ""

    if is_fork_bomb(command):
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    "Blocked: command matches a fork-bomb pattern "
                    "(recursive function piping copies of itself into the "
                    "background). Refusing to run."
                ),
            }
        }))

    return 0


if __name__ == "__main__":
    sys.exit(main())
