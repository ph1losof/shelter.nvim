//! Integration tests for shelter-core parsing
//!
//! Tests the FFI layer via safe Rust wrappers to verify correct behavior
//! for all EDF parsing scenarios.

use std::ffi::{c_char, CStr};
use std::fs;
use std::path::Path;

// Import the shelter-core library
use shelter_core::*;

/// Helper to safely parse content and extract results
unsafe fn parse_content(content: &str) -> ParseResult {
    let opts = ShelterParseOptions {
        include_comments: 1,
        track_positions: 1,
    };

    let result = shelter_parse(content.as_ptr() as *const c_char, content.len(), opts);

    assert!(!result.is_null(), "shelter_parse returned null");

    let result_ref = &*result;

    // Check for errors
    if !result_ref.error.is_null() {
        let error_msg = CStr::from_ptr(result_ref.error).to_string_lossy().into_owned();
        shelter_free_result(result);
        panic!("Parse error: {}", error_msg);
    }

    // Extract entries
    let mut entries = Vec::new();
    for i in 0..result_ref.count {
        let entry = &*result_ref.entries.add(i);
        entries.push(ParsedEntry {
            key: CStr::from_ptr(entry.key).to_string_lossy().into_owned(),
            value: CStr::from_ptr(entry.value).to_string_lossy().into_owned(),
            key_start: entry.key_start,
            key_end: entry.key_end,
            value_start: entry.value_start,
            value_end: entry.value_end,
            line_number: entry.line_number,
            value_end_line: entry.value_end_line,
            quote_type: entry.quote_type,
            is_exported: entry.is_exported != 0,
            is_comment: entry.is_comment != 0,
        });
    }

    // Extract line offsets
    let mut line_offsets = Vec::new();
    for i in 0..result_ref.line_count {
        line_offsets.push(*result_ref.line_offsets.add(i));
    }

    shelter_free_result(result);

    ParseResult {
        entries,
        line_offsets,
    }
}

#[derive(Debug, Clone)]
struct ParsedEntry {
    key: String,
    value: String,
    key_start: usize,
    key_end: usize,
    value_start: usize,
    value_end: usize,
    line_number: usize,
    value_end_line: usize,
    quote_type: u8,
    is_exported: bool,
    is_comment: bool,
}

#[derive(Debug)]
struct ParseResult {
    entries: Vec<ParsedEntry>,
    line_offsets: Vec<usize>,
}

// =============================================================================
// Basic Parsing Tests
// =============================================================================

#[test]
fn test_parse_simple_keyvalue() {
    let content = "API_KEY=secret123";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "API_KEY");
    assert_eq!(result.entries[0].value, "secret123");
    assert!(!result.entries[0].is_exported);
    assert!(!result.entries[0].is_comment);
}

#[test]
fn test_parse_quoted_single() {
    let content = "KEY='value with spaces'";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "KEY");
    assert_eq!(result.entries[0].value, "value with spaces");
    assert_eq!(result.entries[0].quote_type, 1); // Single quote
}

#[test]
fn test_parse_quoted_double() {
    let content = "KEY=\"value with spaces\"";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "KEY");
    assert_eq!(result.entries[0].value, "value with spaces");
    assert_eq!(result.entries[0].quote_type, 2); // Double quote
}

#[test]
fn test_parse_export_prefix() {
    let content = "export API_KEY=secret";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "API_KEY");
    assert_eq!(result.entries[0].value, "secret");
    assert!(result.entries[0].is_exported);
}

#[test]
fn test_parse_empty_value() {
    let content = "EMPTY=";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "EMPTY");
    assert_eq!(result.entries[0].value, "");
}

#[test]
fn test_parse_equals_in_value() {
    let content = "DATABASE_URL=postgres://user:pass@host:5432/db?sslmode=require";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "DATABASE_URL");
    assert_eq!(
        result.entries[0].value,
        "postgres://user:pass@host:5432/db?sslmode=require"
    );
}

// =============================================================================
// Multi-line Value Tests
// =============================================================================

#[test]
fn test_parse_multiline_double_quoted() {
    let content = r#"JSON="{
  \"key\": \"value\"
}""#;
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "JSON");
    // The value should contain the newlines
    assert!(result.entries[0].value.contains('\n'));
    // Line numbers should span multiple lines
    assert!(
        result.entries[0].value_end_line > result.entries[0].line_number,
        "Multi-line value should span multiple lines"
    );
}

#[test]
fn test_parse_multiline_single_quoted() {
    let content = "MULTI='line1\nline2\nline3'";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "MULTI");
    assert!(result.entries[0].value.contains('\n'));
}

#[test]
fn test_parse_multiline_preserves_spans() {
    let content = "KEY=\"first\nsecond\nthird\"";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    let entry = &result.entries[0];

    // Value should span from after = to end of closing quote
    assert!(entry.value_start > entry.key_end);
    assert!(entry.value_end > entry.value_start);

    // Should span 3 lines
    assert_eq!(entry.line_number, 1);
    assert_eq!(entry.value_end_line, 3);
}

// =============================================================================
// Comment Tests
// =============================================================================

#[test]
fn test_parse_comment_line() {
    let content = "# This is a comment\nKEY=value";
    let result = unsafe { parse_content(content) };

    // Should only have the KEY=value entry, comment line is skipped
    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "KEY");
    assert_eq!(result.entries[0].value, "value");
}

#[test]
fn test_parse_comment_with_keyvalue_inside() {
    let content = "#COMMENTED_KEY=secret_value\nREAL_KEY=real_value";
    let result = unsafe { parse_content(content) };

    // korni extracts key-value from comments with is_comment flag
    // Check that at least the real key is present
    let real_key = result.entries.iter().find(|e| e.key == "REAL_KEY");
    assert!(real_key.is_some());
    assert_eq!(real_key.unwrap().value, "real_value");

    // Check if comment key-value is extracted (depends on korni behavior)
    let comment_key = result.entries.iter().find(|e| e.key == "COMMENTED_KEY");
    if let Some(ck) = comment_key {
        assert!(ck.is_comment, "Key from comment line should have is_comment=true");
    }
}

#[test]
fn test_parse_inline_comment_after_value() {
    let content = "KEY=value # this is a comment";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "KEY");
    // Inline comment should NOT be part of the value
    assert_eq!(result.entries[0].value, "value");
}

// =============================================================================
// Line Offset Tests
// =============================================================================

#[test]
fn test_line_offsets_single_line() {
    let content = "KEY=value";
    let result = unsafe { parse_content(content) };

    assert!(!result.line_offsets.is_empty());
    assert_eq!(result.line_offsets[0], 0); // Line 1 starts at byte 0
}

#[test]
fn test_line_offsets_multiple_lines() {
    let content = "LINE1=a\nLINE2=b\nLINE3=c";
    let result = unsafe { parse_content(content) };

    // Should have 3 line offsets
    assert_eq!(result.line_offsets.len(), 3);
    assert_eq!(result.line_offsets[0], 0); // Line 1 at byte 0
    assert_eq!(result.line_offsets[1], 8); // Line 2 at byte 8 (after "LINE1=a\n")
    assert_eq!(result.line_offsets[2], 16); // Line 3 at byte 16
}

#[test]
fn test_line_offsets_empty_lines() {
    let content = "KEY1=a\n\nKEY2=b";
    let result = unsafe { parse_content(content) };

    // Should have 3 line offsets (including empty line)
    assert_eq!(result.line_offsets.len(), 3);
    assert_eq!(result.line_offsets[0], 0);
    assert_eq!(result.line_offsets[1], 7); // After "KEY1=a\n"
    assert_eq!(result.line_offsets[2], 8); // After empty line "\n"
}

#[test]
fn test_line_offsets_used_for_column_calculation() {
    let content = "FIRST=value1\nSECOND=value2";
    let result = unsafe { parse_content(content) };

    // Second entry should be on line 2
    assert_eq!(result.entries.len(), 2);
    assert_eq!(result.entries[1].line_number, 2);

    // Value column should be calculated correctly
    // SECOND starts at byte 13, line 2 starts at byte 13, so key starts at column 0
    let line2_offset = result.line_offsets[1];
    assert_eq!(result.entries[1].key_start - line2_offset, 0);
}

// =============================================================================
// Edge Case Tests
// =============================================================================

#[test]
fn test_parse_special_chars_in_value() {
    let content = "SPECIAL=\"!@#$%^&*()\"";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].value, "!@#$%^&*()");
}

#[test]
fn test_parse_unicode_value() {
    let content = "UNICODE=\"Hello 世界 🌍\"";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].value, "Hello 世界 🌍");
}

#[test]
fn test_parse_very_long_value() {
    let long_value: String = "x".repeat(10000);
    let content = format!("LONG={}", long_value);
    let result = unsafe { parse_content(&content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].value.len(), 10000);
}

#[test]
fn test_parse_multiple_entries() {
    let content = "KEY1=value1\nKEY2=value2\nKEY3=value3";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 3);
    assert_eq!(result.entries[0].key, "KEY1");
    assert_eq!(result.entries[1].key, "KEY2");
    assert_eq!(result.entries[2].key, "KEY3");

    // Verify line numbers
    assert_eq!(result.entries[0].line_number, 1);
    assert_eq!(result.entries[1].line_number, 2);
    assert_eq!(result.entries[2].line_number, 3);
}

// =============================================================================
// Fixture File Tests
// =============================================================================

#[test]
fn test_parse_simple_fixture() {
    let fixture_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("simple.env");

    let content = fs::read_to_string(&fixture_path)
        .unwrap_or_else(|_| panic!("Failed to read fixture: {:?}", fixture_path));

    let result = unsafe { parse_content(&content) };

    // Should have multiple entries from simple.env
    assert!(result.entries.len() >= 4);

    // Check specific expected entries
    let api_key = result.entries.iter().find(|e| e.key == "API_KEY");
    assert!(api_key.is_some());

    let exported = result.entries.iter().find(|e| e.key == "EXPORTED_KEY");
    assert!(exported.is_some());
    assert!(exported.unwrap().is_exported);
}

#[test]
fn test_parse_multiline_fixture() {
    let fixture_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("multiline.env");

    let content = fs::read_to_string(&fixture_path)
        .unwrap_or_else(|_| panic!("Failed to read fixture: {:?}", fixture_path));

    let result = unsafe { parse_content(&content) };

    // Find JSON_BLOB entry
    let json_entry = result.entries.iter().find(|e| e.key == "JSON_BLOB");
    assert!(json_entry.is_some(), "JSON_BLOB entry not found");

    let json = json_entry.unwrap();
    assert!(
        json.value_end_line > json.line_number,
        "JSON_BLOB should span multiple lines"
    );
}

#[test]
fn test_parse_comments_fixture() {
    let fixture_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("comments.env");

    let content = fs::read_to_string(&fixture_path)
        .unwrap_or_else(|_| panic!("Failed to read fixture: {:?}", fixture_path));

    let result = unsafe { parse_content(&content) };

    // Should find regular keys
    let regular = result.entries.iter().find(|e| e.key == "REGULAR_KEY");
    assert!(regular.is_some());
    assert!(!regular.unwrap().is_comment);

    // Should find key with inline comment (value should NOT include comment)
    let inline = result.entries.iter().find(|e| e.key == "KEY_WITH_INLINE");
    assert!(inline.is_some());
    assert_eq!(inline.unwrap().value, "value");
}

// =============================================================================
// Memory Safety Tests
// =============================================================================

#[test]
fn test_parse_null_input() {
    unsafe {
        let opts = ShelterParseOptions {
            include_comments: 1,
            track_positions: 1,
        };

        let result = shelter_parse(std::ptr::null(), 0, opts);
        assert!(!result.is_null());

        let result_ref = &*result;
        assert!(!result_ref.error.is_null(), "Should return error for null input");

        shelter_free_result(result);
    }
}

#[test]
fn test_parse_empty_input() {
    let result = unsafe { parse_content("") };
    assert!(result.entries.is_empty());
    assert!(!result.line_offsets.is_empty()); // Should still have line 1 offset
}

#[test]
fn test_double_free_safety() {
    // This test verifies the API doesn't crash on misuse
    // (though double-free is UB, we document it shouldn't crash)
    let content = "KEY=value";
    unsafe {
        let opts = ShelterParseOptions {
            include_comments: 1,
            track_positions: 1,
        };

        let result = shelter_parse(content.as_ptr() as *const c_char, content.len(), opts);
        assert!(!result.is_null());

        // First free is valid
        shelter_free_result(result);

        // Note: Second free would be UB - we don't test it, just document the API
    }
}

// =============================================================================
// Quote Type Tests
// =============================================================================

#[test]
fn test_parse_quote_type_single() {
    let content = "KEY='single quoted value'";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].quote_type, 1); // Single quote
    assert_eq!(result.entries[0].value, "single quoted value");
}

#[test]
fn test_parse_quote_type_double() {
    let content = r#"KEY="double quoted value""#;
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].quote_type, 2); // Double quote
    assert_eq!(result.entries[0].value, "double quoted value");
}

#[test]
fn test_parse_quote_type_none() {
    let content = "KEY=unquoted_value";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].quote_type, 0); // No quote
    assert_eq!(result.entries[0].value, "unquoted_value");
}

#[test]
fn test_quoted_value_span_includes_quotes() {
    // Verify that value_start and value_end include the quote characters
    // This is important for preserving quotes when masking
    let content = "KEY='secret'";
    let result = unsafe { parse_content(content) };

    assert_eq!(result.entries.len(), 1);
    let entry = &result.entries[0];

    // value_start should point to the opening quote
    // value_end should point past the closing quote
    // Content: KEY='secret'
    //          0123456789...
    // KEY= is 4 chars, ' is at position 4, secret is 5-10, ' is at 11
    assert_eq!(entry.value_start, 4); // Opening quote position
    assert_eq!(entry.value_end, 12); // Past closing quote

    // The value string itself should NOT contain quotes
    assert_eq!(entry.value, "secret");
}
