//! Comprehensive tests for shelter-core masking functions
//!
//! Tests both the internal Rust API and FFI layer for all masking scenarios.

use std::ffi::{c_char, CStr};

use shelter_core::*;

// =============================================================================
// Helper Functions
// =============================================================================

/// Safely call shelter_mask_full via FFI and return the result
unsafe fn ffi_mask_full(value: &str, mask_char: char) -> Option<String> {
    let result = shelter_mask_full(
        value.as_ptr() as *const c_char,
        value.len(),
        mask_char as c_char,
    );

    if result.is_null() {
        return None;
    }

    let masked = CStr::from_ptr(result).to_string_lossy().into_owned();
    shelter_free_string(result);
    Some(masked)
}

/// Safely call shelter_mask_partial via FFI and return the result
unsafe fn ffi_mask_partial(
    value: &str,
    mask_char: char,
    show_start: usize,
    show_end: usize,
    min_mask: usize,
) -> Option<String> {
    let result = shelter_mask_partial(
        value.as_ptr() as *const c_char,
        value.len(),
        mask_char as c_char,
        show_start,
        show_end,
        min_mask,
    );

    if result.is_null() {
        return None;
    }

    let masked = CStr::from_ptr(result).to_string_lossy().into_owned();
    shelter_free_string(result);
    Some(masked)
}

/// Safely call shelter_mask_fixed via FFI and return the result
unsafe fn ffi_mask_fixed(value: &str, mask_char: char, output_len: usize) -> Option<String> {
    let result = shelter_mask_fixed(
        value.as_ptr() as *const c_char,
        value.len(),
        mask_char as c_char,
        output_len,
    );

    if result.is_null() {
        return None;
    }

    let masked = CStr::from_ptr(result).to_string_lossy().into_owned();
    shelter_free_string(result);
    Some(masked)
}

/// Safely call shelter_mask_value via FFI and return the result
unsafe fn ffi_mask_value(value: &str, options: ShelterMaskOptions) -> Option<String> {
    let result = shelter_mask_value(value.as_ptr() as *const c_char, value.len(), options);

    if result.is_null() {
        return None;
    }

    let masked = CStr::from_ptr(result).to_string_lossy().into_owned();
    shelter_free_string(result);
    Some(masked)
}

// =============================================================================
// Full Masking Tests
// =============================================================================

#[test]
fn test_mask_full_basic() {
    assert_eq!(mask_full("secret", '*', None), "******");
    assert_eq!(mask_full("password123", '*', None), "***********");
}

#[test]
fn test_mask_full_empty_string() {
    assert_eq!(mask_full("", '*', None), "");
}

#[test]
fn test_mask_full_single_char() {
    assert_eq!(mask_full("x", '*', None), "*");
}

#[test]
fn test_mask_full_custom_char() {
    assert_eq!(mask_full("secret", '#', None), "######");
    assert_eq!(mask_full("secret", 'X', None), "XXXXXX");
    assert_eq!(mask_full("secret", '-', None), "------");
}

#[test]
fn test_mask_full_with_output_len() {
    assert_eq!(mask_full("secret", '*', Some(10)), "**********");
    assert_eq!(mask_full("secret", '*', Some(3)), "***");
    assert_eq!(mask_full("secret", '*', Some(0)), "");
}

#[test]
fn test_mask_full_unicode() {
    // mask_full uses byte length by default, not character count
    let value = "secret🔐";
    let masked = mask_full(value, '*', None);
    // "secret" = 6 bytes + 🔐 = 4 bytes = 10 bytes total
    assert_eq!(masked.len(), 10);
    assert_eq!(masked, "**********");
}

#[test]
fn test_mask_full_unicode_only() {
    let value = "🔐🔑🗝️";
    let masked = mask_full(value, '*', None);
    // Each emoji is 1 char (though may have different byte lengths)
    assert!(masked.chars().all(|c| c == '*'));
}

#[test]
fn test_mask_full_ffi() {
    unsafe {
        let result = ffi_mask_full("secret", '*');
        assert_eq!(result, Some("******".to_string()));

        let result = ffi_mask_full("test", '#');
        assert_eq!(result, Some("####".to_string()));
    }
}

#[test]
fn test_mask_full_ffi_null_input() {
    unsafe {
        let result = shelter_mask_full(std::ptr::null(), 0, '*' as c_char);
        assert!(result.is_null());
    }
}

// =============================================================================
// Partial Masking Tests
// =============================================================================

#[test]
fn test_mask_partial_basic() {
    // "secretvalue" -> "sec*****lue" (show 3 start, 3 end, mask middle)
    assert_eq!(mask_partial("secretvalue", '*', 3, 3, 3, None), "sec*****lue");
}

#[test]
fn test_mask_partial_show_start_end() {
    assert_eq!(mask_partial("abcdefghij", '*', 2, 2, 3, None), "ab******ij");
    assert_eq!(mask_partial("abcdefghij", '*', 4, 4, 1, None), "abcd**ghij");
}

#[test]
fn test_mask_partial_min_mask_enforcement() {
    // If not enough room for min_mask, fall back to full mask
    assert_eq!(mask_partial("short", '*', 3, 3, 3, None), "*****");
    assert_eq!(mask_partial("abc", '*', 2, 2, 3, None), "***");
}

#[test]
fn test_mask_partial_short_value_fallback() {
    // Value too short to show start+end, falls back to full mask
    assert_eq!(mask_partial("ab", '*', 3, 3, 3, None), "**");
    assert_eq!(mask_partial("", '*', 3, 3, 3, None), "");
}

#[test]
fn test_mask_partial_zero_show() {
    // Show nothing, mask everything
    assert_eq!(mask_partial("secret", '*', 0, 0, 3, None), "******");
}

#[test]
fn test_mask_partial_unicode_boundaries() {
    // Unicode characters at boundaries
    let value = "🔐secret🔑";
    let masked = mask_partial(value, '*', 1, 1, 3, None);
    // Should show first emoji, mask middle, show last emoji
    assert!(masked.starts_with('🔐'));
    assert!(masked.ends_with('🔑'));
    assert!(masked.contains('*'));
}

#[test]
fn test_mask_partial_with_output_len() {
    assert_eq!(mask_partial("secretvalue", '*', 3, 3, 3, Some(15)), "sec*********lue");
}

#[test]
fn test_mask_partial_ffi() {
    unsafe {
        let result = ffi_mask_partial("secretvalue", '*', 3, 3, 3);
        assert_eq!(result, Some("sec*****lue".to_string()));

        let result = ffi_mask_partial("short", '*', 3, 3, 3);
        assert_eq!(result, Some("*****".to_string()));
    }
}

// =============================================================================
// Fixed Length Masking Tests
// =============================================================================

#[test]
fn test_mask_fixed_basic() {
    assert_eq!(mask_fixed("anything", '*', 8), "********");
}

#[test]
fn test_mask_fixed_longer_than_value() {
    assert_eq!(mask_fixed("short", '*', 20), "********************");
}

#[test]
fn test_mask_fixed_shorter_than_value() {
    assert_eq!(mask_fixed("very_long_value", '*', 5), "*****");
}

#[test]
fn test_mask_fixed_zero_length() {
    assert_eq!(mask_fixed("anything", '*', 0), "");
}

#[test]
fn test_mask_fixed_custom_char() {
    assert_eq!(mask_fixed("test", '#', 10), "##########");
    assert_eq!(mask_fixed("test", 'X', 6), "XXXXXX");
}

#[test]
fn test_mask_fixed_ffi() {
    unsafe {
        let result = ffi_mask_fixed("anything", '*', 10);
        assert_eq!(result, Some("**********".to_string()));

        let result = ffi_mask_fixed("test", '#', 5);
        assert_eq!(result, Some("#####".to_string()));
    }
}

// =============================================================================
// mask_value (Options-based) Tests
// =============================================================================

#[test]
fn test_mask_value_full_mode() {
    let opts = ShelterMaskOptions {
        mask_char: b'*' as i8,
        mask_length: 0,
        mode: 0, // full
        show_start: 0,
        show_end: 0,
        min_mask: 3,
    };
    assert_eq!(mask_value("password", &opts), "********");
}

#[test]
fn test_mask_value_partial_mode() {
    let opts = ShelterMaskOptions {
        mask_char: b'*' as i8,
        mask_length: 0,
        mode: 1, // partial
        show_start: 2,
        show_end: 2,
        min_mask: 3,
    };
    assert_eq!(mask_value("password", &opts), "pa****rd");
}

#[test]
fn test_mask_value_with_fixed_length() {
    let opts = ShelterMaskOptions {
        mask_char: b'*' as i8,
        mask_length: 10,
        mode: 0, // full
        show_start: 0,
        show_end: 0,
        min_mask: 3,
    };
    assert_eq!(mask_value("short", &opts), "**********");
}

#[test]
fn test_mask_value_ffi() {
    unsafe {
        let opts = ShelterMaskOptions {
            mask_char: b'*' as i8,
            mask_length: 0,
            mode: 0,
            show_start: 0,
            show_end: 0,
            min_mask: 3,
        };
        let result = ffi_mask_value("secret", opts);
        assert_eq!(result, Some("******".to_string()));
    }
}

#[test]
fn test_mask_value_ffi_partial() {
    unsafe {
        let opts = ShelterMaskOptions {
            mask_char: b'#' as i8,
            mask_length: 0,
            mode: 1,
            show_start: 2,
            show_end: 2,
            min_mask: 3,
        };
        let result = ffi_mask_value("secretvalue", opts);
        assert_eq!(result, Some("se#######ue".to_string()));
    }
}

// =============================================================================
// mask_with_mode Tests
// =============================================================================

#[test]
fn test_mask_with_mode_full() {
    assert_eq!(mask_with_mode("secret", ShelterMaskMode::Full, '*'), "******");
}

#[test]
fn test_mask_with_mode_partial() {
    // Partial mode uses defaults: show_start=3, show_end=3, min_mask=3
    assert_eq!(
        mask_with_mode("secretvalue", ShelterMaskMode::Partial, '*'),
        "sec*****lue"
    );
}

// =============================================================================
// Edge Cases and Stress Tests
// =============================================================================

#[test]
fn test_mask_very_long_value() {
    let long_value: String = "x".repeat(100000);
    let masked = mask_full(&long_value, '*', None);
    assert_eq!(masked.len(), 100000);
    assert!(masked.chars().all(|c| c == '*'));
}

#[test]
fn test_mask_special_characters() {
    let special = "!@#$%^&*()_+-=[]{}|;':\",./<>?";
    let masked = mask_full(special, '*', None);
    assert_eq!(masked.len(), special.len());
}

#[test]
fn test_mask_newlines() {
    let multiline = "line1\nline2\nline3";
    let masked = mask_full(multiline, '*', None);
    assert_eq!(masked.len(), multiline.len());
    // Newlines are also masked
    assert!(!masked.contains('\n'));
}

#[test]
fn test_mask_tabs_and_spaces() {
    let whitespace = "  \t  value  \t  ";
    let masked = mask_full(whitespace, '*', None);
    assert_eq!(masked.len(), whitespace.len());
}

#[test]
fn test_version() {
    unsafe {
        let version = shelter_version();
        assert!(!version.is_null());
        let version_str = CStr::from_ptr(version).to_string_lossy();
        assert!(!version_str.is_empty());
        // Should be semver format
        assert!(version_str.contains('.'));
    }
}

// =============================================================================
// Consistency Tests
// =============================================================================

#[test]
fn test_rust_and_ffi_produce_same_results() {
    let test_values = vec![
        "simple",
        "with spaces",
        "special!@#$",
        "unicode🔐value",
        "",
        "x",
    ];

    for value in test_values {
        // Test full masking
        let rust_result = mask_full(value, '*', None);
        let ffi_result = unsafe { ffi_mask_full(value, '*') };
        assert_eq!(
            Some(rust_result.clone()),
            ffi_result,
            "Mismatch for full mask of '{}'",
            value
        );

        // Test partial masking
        if value.len() >= 6 {
            let rust_result = mask_partial(value, '*', 2, 2, 2, None);
            let ffi_result = unsafe { ffi_mask_partial(value, '*', 2, 2, 2) };
            assert_eq!(
                Some(rust_result),
                ffi_result,
                "Mismatch for partial mask of '{}'",
                value
            );
        }

        // Test fixed length
        let rust_result = mask_fixed(value, '*', 10);
        let ffi_result = unsafe { ffi_mask_fixed(value, '*', 10) };
        assert_eq!(
            Some(rust_result),
            ffi_result,
            "Mismatch for fixed mask of '{}'",
            value
        );
    }
}
