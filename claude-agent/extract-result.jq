# Extract the agent's final result from Claude Code stream-json output.
# Input: array of JSON objects (read with jq -s flag)
# Fallback chain:
#   1. Last .result string from type=="result" events
#   2. Last non-empty text concatenation from type=="assistant" events
#   3. Literal "Output not parseable" (must match PARSE_FAILED_RESULT in lib/constants.sh)

# Strategy 1: last .result string from type=="result" events
  ([.[] | select(.type == "result" and .result != null) | .result | strings] | last)
# Strategy 2: last non-empty concatenation of text blocks from type=="assistant"
# // is jq's "alternative" operator (like ?? in other languages)
  // (
    [.[]
      | select(.type == "assistant")
      | .message.content // []          # default to empty array if null
      | map(select(.type == "text") | .text)
      | join("")
    ]
    | map(select(length > 0))           # drop empty strings
    | last
  )
# Strategy 3: hardcoded fallback (must match PARSE_FAILED_RESULT in constants.sh)
  // "Output not parseable"
