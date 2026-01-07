//! shelter-core: Native Rust core for shelter.nvim
//!
//! Provides EDF-compliant dotenv parsing and masking via C FFI for LuaJIT.

mod ffi;
mod masker;
mod types;

pub use ffi::*;
pub use masker::*;
pub use types::*;
