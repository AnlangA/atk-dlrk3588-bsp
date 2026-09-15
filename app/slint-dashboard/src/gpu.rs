// SPDX-License-Identifier: GPL-3.0-only
//! Audit the actual OpenGL context; reject software or unexpected renderers.
use slint::ComponentHandle;
use std::ffi::{CStr, c_void};

fn is_mali_renderer(renderer: &str) -> bool {
    let name = renderer.to_ascii_lowercase();
    !["llvmpipe", "softpipe", "swrast", "lavapipe", "swiftshader"]
        .iter()
        .any(|s| name.contains(s))
        && ["mali", "panfrost", "panthor"]
            .iter()
            .any(|s| name.contains(s))
}

// This small boundary is the only application code that calls a native API.
#[allow(unsafe_code)]
fn gl_string(get_proc: &dyn Fn(&CStr) -> *const c_void, name: u32) -> Result<String, &'static str> {
    let address = get_proc(c"glGetString");
    if address.is_null() {
        return Err("glGetString is unavailable");
    }
    // SAFETY: Slint calls setup/before-render callbacks with its context current. The
    // symbol is glGetString with the OpenGL ABI, and each queried enum is valid.
    let query: unsafe extern "system" fn(u32) -> *const u8 =
        unsafe { std::mem::transmute(address) };
    // SAFETY: The current context is valid and name is a GL identity enum.
    let value = unsafe { query(name) };
    if value.is_null() {
        return Err("OpenGL returned a null identity string");
    }
    // SAFETY: glGetString returns a NUL-terminated string owned by the current
    // context. Copy it now so no pointer survives the rendering callback.
    Ok(unsafe { CStr::from_ptr(value.cast()) }
        .to_string_lossy()
        .into_owned())
}

pub fn install(
    ui: &super::Dashboard,
    mut after_render: impl FnMut(&super::Dashboard) + 'static,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut frames = 0u64;
    let weak = ui.as_weak();
    let mut verified = false;
    ui.window().set_rendering_notifier(move |state, api| {
        match state {
            slint::RenderingState::RenderingSetup | slint::RenderingState::BeforeRendering
                if !verified =>
            {
                let slint::GraphicsAPI::NativeOpenGL { get_proc_address } = api else {
                    eprintln!("GPU_REQUIRED: renderer did not provide an OpenGL context");
                    std::process::exit(1);
                };
                let vendor = gl_string(get_proc_address, 0x1f00);
                let renderer = gl_string(get_proc_address, 0x1f01);
                let version = gl_string(get_proc_address, 0x1f02);
                match (vendor, renderer, version) {
                    (Ok(vendor), Ok(renderer), Ok(version)) if is_mali_renderer(&renderer) => {
                        verified = true;
                        eprintln!(
                            "GPU_READY: vendor={vendor}; renderer={renderer}; version={version}"
                        );
                        let _ =
                            weak.upgrade_in_event_loop(move |ui| ui.set_gpu_info(renderer.into()));
                    }
                    identity => {
                        eprintln!(
                            "GPU_REQUIRED: refusing non-Mali or unavailable renderer: {identity:?}"
                        );
                        // Stop before drawing any scene with an unintended software context.
                        std::process::exit(1);
                    }
                }
            }
            slint::RenderingState::AfterRendering => {
                frames = frames.wrapping_add(1);
                if frames == 1 || frames.is_multiple_of(60) {
                    eprintln!("GPU_FRAME: {frames}");
                }
                // LinuxKMS renders on the UI thread. FemtoVG has flushed its
                // commands here, but has not swapped the GBM buffers yet.
                if let Some(ui) = weak.upgrade() {
                    after_render(&ui);
                }
            }
            slint::RenderingState::RenderingTeardown => verified = false,
            _ => {}
        }
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_software_contexts() {
        assert!(is_mali_renderer("Mali-G610 (Panfrost)"));
        assert!(!is_mali_renderer("llvmpipe (LLVM 21.1.8, 128 bits)"));
        assert!(!is_mali_renderer("Mali emulated by SwiftShader"));
        assert!(!is_mali_renderer(""));
    }
}
