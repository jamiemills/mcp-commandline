# Transport Type Inference Implementation Plan

**Created:** 2025-12-26
**Last Updated:** 2025-12-26

## Objective

Implement automatic transport type inference based on configuration structure, allowing users to omit the explicit `type` field when the transport is unambiguous.

### Inference Rules

- **stdio transport**: Inferred when `command` field is present and `url` is absent
- **HTTP/SSE transport**: Inferred when `url` field is present and `command` is absent

### User Preferences Applied

1. **Type Field Requirement**: The `type` field can be omitted if structure unambiguously indicates transport type; it will be inferred automatically
2. **Conflict Resolution**: If explicit `type` is provided, it takes precedence over inferred structure (backwards compatible)

## Implementation Steps

### 1. Add Type Inference Function (Before Process Server Function)

**Location**: Insert new function before `process_server()` function (around line 212)

**Purpose**: Infer transport type from configuration structure

**Behaviour**:
- Take config object as input
- Check for `command` field → return "stdio"
- Check for `url` field → return "http" (default for remote transports)
- If neither found → return empty string (will be caught by validation)
- If both present → return empty string (ambiguous, require explicit type)

### 2. Modify Type Extraction Logic (Flat Format Section, Line 489)

**Current behaviour**: `type=$(echo "$JSON_INPUT" | jq -r '.type // empty')`

**New behaviour**:
- Extract explicit type field
- If type is empty, call inference function with full config
- Assign inferred type to variable

### 3. Modify Type Extraction Logic (Claude Desktop Format Section, Line 476)

**Current behaviour**: `type=$(echo "$server_config" | jq -r '.type // empty')`

**New behaviour**:
- Extract explicit type field
- If type is empty, call inference function with server_config
- Assign inferred type to variable

### 4. Update Type Validation Message (Line 241-244)

**Current error**: "Error: 'type' must be one of: http, sse, stdio"

**New error logic**:
- If explicit type was provided but invalid → show current error
- If type inference failed (ambiguous or missing required fields) → show new error message explaining inference rules

### 5. Update Usage Documentation (Lines 6-53)

**Updates**:
- Add section explaining transport type inference
- Update format examples to show optional `type` field
- Document inference rules clearly:
  - `command` present → stdio
  - `url` present → http (or sse if explicitly stated)
  - Both or neither → type required

### 6. Add Validation for Ambiguous Configurations

**Location**: In type inference or validation phase

**Check**:
- If both `command` and `url` are present and no explicit type is provided → require explicit type

## Implementation Details

### New Function: `infer_transport_type()`

```bash
infer_transport_type() {
    local config="$1"

    # Extract both fields
    local has_command=$(echo "$config" | jq 'has("command")' 2>/dev/null)
    local has_url=$(echo "$config" | jq 'has("url")' 2>/dev/null)

    # Both present → ambiguous, require explicit type
    if [ "$has_command" = "true" ] && [ "$has_url" = "true" ]; then
        return 1  # Will be caught as inference failure
    fi

    # Only command present → stdio
    if [ "$has_command" = "true" ]; then
        echo "stdio"
        return 0
    fi

    # Only url present → http (default remote transport)
    if [ "$has_url" = "true" ]; then
        echo "http"
        return 0
    fi

    # Neither present → inference failed
    return 1
}
```

### Modified Type Extraction (Flat Format)

```bash
type=$(echo "$JSON_INPUT" | jq -r '.type // empty')
if [ -z "$type" ]; then
    inferred=$(infer_transport_type "$JSON_INPUT")
    if [ $? -eq 0 ]; then
        type="$inferred"
    fi
fi
```

### Modified Type Extraction (Claude Desktop Format)

```bash
type=$(echo "$server_config" | jq -r '.type // empty')
if [ -z "$type" ]; then
    inferred=$(infer_transport_type "$server_config")
    if [ $? -eq 0 ]; then
        type="$inferred"
    fi
fi
```

## Testing Considerations

Test cases to verify:

1. **Stdio inference**: Config with `command` only, no explicit type → infer as stdio
2. **HTTP inference**: Config with `url` only, no explicit type → infer as http
3. **Explicit type precedence**: Config with both `command` and `url`, explicit `type` provided → use explicit type
4. **Ambiguous detection**: Config with both `command` and `url`, no explicit type → error requiring explicit type
5. **Missing inference**: Config with neither `command` nor `url`, no explicit type → error requiring type
6. **Backwards compatibility**: All existing configs with explicit type field continue to work unchanged

## Documentation Updates Required

1. Usage help text (lines 6-53)
2. README.md examples section
3. Comments explaining inference logic
4. Error messages for ambiguous/missing type scenarios

## Backwards Compatibility

✓ All existing configurations with explicit `type` field remain fully compatible
✓ New inference only activates when `type` field is absent
✓ Explicit type always takes precedence if provided
✓ No breaking changes to configuration format or CLI interface

## Progress Tracking

- [x] 1. Add `infer_transport_type()` function
- [x] 2. Update flat format type extraction
- [x] 3. Update Claude Desktop format type extraction
- [x] 4. Update type validation and error messages
- [x] 5. Update usage documentation
- [x] 6. Add validation for ambiguous configurations
- [x] 7. Test all scenarios
- [x] 8. Update README.md with inference documentation

## Implementation Complete

All steps completed successfully. Transport type inference is now fully implemented and tested.
