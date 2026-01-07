//! FFI-safe types for shelter-core
//!
//! All types use #[repr(C)] for C ABI compatibility with LuaJIT FFI.

use std::ffi::{c_char, CString};
use std::ptr;

/// Quote type for parsed values
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShelterQuoteType {
    None = 0,
    Single = 1,
    Double = 2,
}

impl From<korni::QuoteType> for ShelterQuoteType {
    fn from(qt: korni::QuoteType) -> Self {
        match qt {
            korni::QuoteType::None => ShelterQuoteType::None,
            korni::QuoteType::Single => ShelterQuoteType::Single,
            korni::QuoteType::Double => ShelterQuoteType::Double,
        }
    }
}

/// A parsed key-value entry from an EDF file
/// Memory layout optimized: all 8-byte fields first, then 1-byte fields packed
/// Total size: 88 bytes (80 bytes data + 3 bytes flags + 5 bytes padding)
#[repr(C)]
pub struct ShelterEntry {
    // === 8-byte aligned fields (pointers and sizes) ===
    /// Key string (null-terminated)
    pub key: *mut c_char,
    /// Length of key (excluding null terminator)
    pub key_len: usize,
    /// Value string (null-terminated)
    pub value: *mut c_char,
    /// Length of value (excluding null terminator)
    pub value_len: usize,
    /// Byte offset where key starts
    pub key_start: usize,
    /// Byte offset where key ends
    pub key_end: usize,
    /// Byte offset where value starts
    pub value_start: usize,
    /// Byte offset where value ends
    pub value_end: usize,
    /// 1-based line number where key starts
    pub line_number: usize,
    /// 1-based line number where value ends (for multi-line values)
    pub value_end_line: usize,

    // === 1-byte fields (packed at end to minimize padding) ===
    /// Quote type (0=none, 1=single, 2=double)
    pub quote_type: u8,
    /// Whether entry has 'export' prefix
    pub is_exported: u8,
    /// Whether entry is inside a comment
    pub is_comment: u8,
    // Implicit 5 bytes padding to align struct to 8 bytes
}

impl ShelterEntry {
    /// Create a new entry from a korni KeyValuePair
    pub fn from_korni(kv: &korni::KeyValuePair, line_number: usize, value_end_line: usize) -> Self {
        let key_cstr = CString::new(kv.key.as_ref()).unwrap_or_default();
        let value_cstr = CString::new(kv.value.as_ref()).unwrap_or_default();

        let (key_start, key_end) = kv
            .key_span
            .map(|s| (s.start.offset, s.end.offset))
            .unwrap_or((0, 0));

        let (value_start, value_end) = kv
            .value_span
            .map(|s| (s.start.offset, s.end.offset))
            .unwrap_or((0, 0));

        ShelterEntry {
            key_len: kv.key.len(),
            key: key_cstr.into_raw(),
            value_len: kv.value.len(),
            value: value_cstr.into_raw(),
            key_start,
            key_end,
            value_start,
            value_end,
            line_number,
            value_end_line,
            quote_type: ShelterQuoteType::from(kv.quote) as u8,
            is_exported: kv.is_exported as u8,
            is_comment: kv.is_comment as u8,
        }
    }
}

/// Result of parsing an EDF file
/// Includes pre-computed line offsets for O(1) byte-to-line lookups
#[repr(C)]
pub struct ShelterResult {
    /// Array of parsed entries
    pub entries: *mut ShelterEntry,
    /// Number of entries
    pub count: usize,
    /// Array of byte offsets where each line starts (0-indexed into content)
    /// line_offsets[0] = 0 (line 1 starts at byte 0)
    /// line_offsets[1] = position after first newline (line 2 start)
    pub line_offsets: *mut usize,
    /// Number of lines (length of line_offsets array)
    pub line_count: usize,
    /// Error message (null if no error)
    pub error: *mut c_char,
}

impl ShelterResult {
    /// Create a successful result with entries and line offsets
    #[inline]
    pub fn ok(entries: Vec<ShelterEntry>, line_offsets: Vec<usize>) -> *mut Self {
        let count = entries.len();
        let line_count = line_offsets.len();

        let entries_ptr = if entries.is_empty() {
            ptr::null_mut()
        } else {
            let boxed = entries.into_boxed_slice();
            Box::into_raw(boxed) as *mut ShelterEntry
        };

        let line_offsets_ptr = if line_offsets.is_empty() {
            ptr::null_mut()
        } else {
            let boxed = line_offsets.into_boxed_slice();
            Box::into_raw(boxed) as *mut usize
        };

        Box::into_raw(Box::new(ShelterResult {
            entries: entries_ptr,
            count,
            line_offsets: line_offsets_ptr,
            line_count,
            error: ptr::null_mut(),
        }))
    }

    /// Create an error result
    #[inline]
    pub fn err(message: &str) -> *mut Self {
        let error = CString::new(message)
            .unwrap_or_else(|_| CString::new("Unknown error").unwrap())
            .into_raw();

        Box::into_raw(Box::new(ShelterResult {
            entries: ptr::null_mut(),
            count: 0,
            line_offsets: ptr::null_mut(),
            line_count: 0,
            error,
        }))
    }
}

/// Options for parsing
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ShelterParseOptions {
    /// Include comment entries
    pub include_comments: u8,
    /// Track byte positions
    pub track_positions: u8,
}

impl Default for ShelterParseOptions {
    fn default() -> Self {
        Self {
            include_comments: 1,
            track_positions: 1,
        }
    }
}

impl From<ShelterParseOptions> for korni::ParseOptions {
    fn from(opts: ShelterParseOptions) -> Self {
        korni::ParseOptions {
            include_comments: opts.include_comments != 0,
            track_positions: opts.track_positions != 0,
        }
    }
}

/// Options for masking a value
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ShelterMaskOptions {
    /// Character to use for masking (ASCII)
    pub mask_char: c_char,
    /// Fixed output length (0 = use value length)
    pub mask_length: usize,
    /// Masking mode (0=full, 1=partial)
    pub mode: u8,
    /// Characters to show at start (for partial mode)
    pub show_start: usize,
    /// Characters to show at end (for partial mode)
    pub show_end: usize,
    /// Minimum mask characters required (for partial mode)
    pub min_mask: usize,
}

impl Default for ShelterMaskOptions {
    fn default() -> Self {
        Self {
            mask_char: b'*' as c_char,
            mask_length: 0,
            mode: 0,
            show_start: 0,
            show_end: 0,
            min_mask: 3,
        }
    }
}

/// Masking mode
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShelterMaskMode {
    Full = 0,
    Partial = 1,
}
