//! C FFI functions for shelter-core
//!
//! These functions are exposed via the C ABI for LuaJIT FFI.

use crate::types::{ShelterEntry, ShelterParseOptions, ShelterResult};
use korni::Entry;
use std::ffi::{c_char, CString};
use std::slice;

/// Library version string
const VERSION: &[u8] = b"0.1.0\0";

// =============================================================================
//  Parsing Functions
// =============================================================================

/// Binary search to find line number from byte offset
/// Returns 1-based line number
#[inline]
fn offset_to_line_binary(line_starts: &[usize], offset: usize) -> usize {
    match line_starts.binary_search(&offset) {
        // Exact match: offset is at start of this line
        Ok(line) => line + 1,
        // Not found: offset is within the line before insert point
        Err(line) => line,
    }
}

/// Parse EDF content and return entries
///
/// # Safety
/// - `input` must be a valid pointer to a UTF-8 string
/// - `input_len` must be the exact length of the string
/// - Caller must free the result using `shelter_free_result`
#[no_mangle]
pub unsafe extern "C" fn shelter_parse(
    input: *const c_char,
    input_len: usize,
    options: ShelterParseOptions,
) -> *mut ShelterResult {
    // Validate input
    if input.is_null() {
        return ShelterResult::err("Input is null");
    }

    // Convert to Rust string
    let input_slice = slice::from_raw_parts(input as *const u8, input_len);
    let input_str = match std::str::from_utf8(input_slice) {
        Ok(s) => s,
        Err(e) => return ShelterResult::err(&format!("Invalid UTF-8: {}", e)),
    };

    // Parse using korni
    let korni_opts = korni::ParseOptions::from(options);
    let parsed_entries = korni::parse_with_options(input_str, korni_opts);

    // Build line_starts array: indices where each line begins
    // Pre-allocate with estimated capacity (avg line length ~30 chars)
    let estimated_lines = input_len / 30 + 1;
    let mut line_starts: Vec<usize> = Vec::with_capacity(estimated_lines);
    line_starts.push(0); // Line 1 starts at offset 0

    for (i, b) in input_str.bytes().enumerate() {
        if b == b'\n' {
            line_starts.push(i + 1);
        }
    }

    // Convert entries - pre-allocate based on parsed count
    let mut entries = Vec::with_capacity(parsed_entries.len());

    for entry in parsed_entries {
        match entry {
            Entry::Pair(kv) => {
                let line_number = kv
                    .key_span
                    .map(|s| offset_to_line_binary(&line_starts, s.start.offset))
                    .unwrap_or(0);

                // Calculate end line for multi-line values using binary search
                let value_end_line = kv
                    .value_span
                    .map(|s| offset_to_line_binary(&line_starts, s.end.offset.saturating_sub(1)))
                    .unwrap_or(line_number);

                entries.push(ShelterEntry::from_korni(&kv, line_number, value_end_line));
            }
            Entry::Comment(_) => {
                // Skip comments for now, we only care about key-value pairs
            }
            Entry::Error(_) => {
                // Silently skip parse errors - expected during editing
            }
        }
    }

    // Return entries and line_starts together - Lua gets pre-computed offsets
    ShelterResult::ok(entries, line_starts)
}

/// Free a parse result
///
/// # Safety
/// - `result` must be a valid pointer returned by `shelter_parse`
/// - Must not be called more than once on the same pointer
#[no_mangle]
pub unsafe extern "C" fn shelter_free_result(result: *mut ShelterResult) {
    if result.is_null() {
        return;
    }

    let result = Box::from_raw(result);

    // Free entries
    if !result.entries.is_null() && result.count > 0 {
        let entries = Vec::from_raw_parts(result.entries, result.count, result.count);
        for entry in entries {
            // Free key and value strings
            if !entry.key.is_null() {
                drop(CString::from_raw(entry.key));
            }
            if !entry.value.is_null() {
                drop(CString::from_raw(entry.value));
            }
        }
    }

    // Free line_offsets array
    if !result.line_offsets.is_null() && result.line_count > 0 {
        drop(Vec::from_raw_parts(
            result.line_offsets,
            result.line_count,
            result.line_count,
        ));
    }

    // Free error message if present
    if !result.error.is_null() {
        drop(CString::from_raw(result.error));
    }
}

// =============================================================================
//  Utility Functions
// =============================================================================

/// Get library version string
///
/// # Safety
/// The returned pointer points to static memory and must not be freed.
#[no_mangle]
pub extern "C" fn shelter_version() -> *const c_char {
    VERSION.as_ptr() as *const c_char
}
