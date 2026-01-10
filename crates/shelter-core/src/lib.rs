//! shelter-core: Native Rust core for shelter.nvim
//!
//! Provides EDF-compliant dotenv parsing via C FFI for LuaJIT.

mod ffi;
mod types;

pub use ffi::*;
pub use types::*;
