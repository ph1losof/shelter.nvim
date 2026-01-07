//! Native masking primitives for shelter.nvim
//!
//! High-performance masking operations callable via FFI.
//! Optimized for minimal allocations.

use crate::types::{ShelterMaskMode, ShelterMaskOptions};

/// Generate a full mask (all characters replaced)
///
/// Single allocation using iterator chaining.
#[inline]
pub fn mask_full(value: &str, mask_char: char, output_len: Option<usize>) -> String {
    let len = output_len.unwrap_or(value.len());
    std::iter::repeat(mask_char).take(len).collect()
}

/// Generate a fixed-length mask
///
/// Single allocation.
#[inline]
pub fn mask_fixed(_value: &str, mask_char: char, length: usize) -> String {
    std::iter::repeat(mask_char).take(length).collect()
}

/// Generate a partial mask (show start/end characters)
///
/// Pre-allocates exact capacity, extends in place.
/// Reduced from 6 allocations to 2.
pub fn mask_partial(
    value: &str,
    mask_char: char,
    show_start: usize,
    show_end: usize,
    min_mask: usize,
    output_len: Option<usize>,
) -> String {
    // Fast path: collect chars once (unavoidable for Unicode)
    let chars: Vec<char> = value.chars().collect();
    let value_len = chars.len();

    // If value is too short, just mask everything
    if value_len <= show_start + show_end {
        return mask_full(value, mask_char, output_len);
    }

    // Calculate target length
    let target_len = output_len.unwrap_or(value_len);
    let available_middle = target_len.saturating_sub(show_start).saturating_sub(show_end);

    // If not enough room for min_mask, fall back to full mask
    if available_middle < min_mask {
        return mask_full(value, mask_char, output_len);
    }

    // Pre-allocate with exact capacity (single allocation for result)
    let mut result = String::with_capacity(target_len);

    // Extend start portion in place
    result.extend(chars.iter().take(show_start));

    // Extend middle mask in place
    result.extend(std::iter::repeat(mask_char).take(available_middle));

    // Extend end portion in place
    if show_end > 0 && chars.len() > show_end {
        result.extend(chars.iter().skip(chars.len() - show_end));
    }

    result
}

/// Mask a value with the given options
#[inline]
pub fn mask_value(value: &str, options: &ShelterMaskOptions) -> String {
    let mask_char = options.mask_char as u8 as char;
    let output_len = if options.mask_length > 0 {
        Some(options.mask_length)
    } else {
        None
    };

    match options.mode {
        0 => mask_full(value, mask_char, output_len),
        1 => mask_partial(
            value,
            mask_char,
            options.show_start,
            options.show_end,
            options.min_mask,
            output_len,
        ),
        _ => mask_full(value, mask_char, output_len),
    }
}

/// Apply masking based on mode enum
#[inline]
pub fn mask_with_mode(value: &str, mode: ShelterMaskMode, mask_char: char) -> String {
    match mode {
        ShelterMaskMode::Full => mask_full(value, mask_char, None),
        ShelterMaskMode::Partial => mask_partial(value, mask_char, 3, 3, 3, None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mask_full() {
        assert_eq!(mask_full("secret", '*', None), "******");
        assert_eq!(mask_full("secret", '*', Some(10)), "**********");
        assert_eq!(mask_full("secret", '#', None), "######");
    }

    #[test]
    fn test_mask_partial() {
        assert_eq!(mask_partial("secretvalue", '*', 3, 3, 3, None), "sec*****lue");
        assert_eq!(mask_partial("short", '*', 3, 3, 3, None), "*****"); // Too short, full mask
        assert_eq!(mask_partial("abcdefghij", '*', 2, 2, 3, None), "ab******ij");
    }

    #[test]
    fn test_mask_fixed() {
        assert_eq!(mask_fixed("anything", '*', 8), "********");
        assert_eq!(mask_fixed("short", '*', 20), "********************");
    }

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
}
