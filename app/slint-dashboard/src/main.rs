// SPDX-License-Identifier: GPL-3.0-only
#[cfg(test)]
#[path = "../vendor/i-slint-backend-linuxkms/drmformats.rs"]
mod drm_formats_tests;
mod gpu;
mod metrics;
#[cfg(test)]
mod snapshot;

use slint::ComponentHandle;
use std::{
    fs,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

slint::include_modules!();

fn update(ui: &Dashboard) {
    let data = metrics::Metrics::read();
    ui.set_uptime(data.uptime.into());
    ui.set_temperature(data.temperature.into());
    ui.set_memory(data.memory.into());
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args == ["--metrics"] {
        println!("{:#?}", metrics::Metrics::read());
        return Ok(());
    }
    if args == ["--help"] {
        println!(
            "slint-dashboard [--metrics | --capture FILE.png | --test-pattern | --help]\nDisplay selection: SLINT_DRM_OUTPUT, SLINT_DRM_MODE.\nRendering: Mali GPU, LinuxKMS/FemtoVG/OpenGL ES. SIGUSR1 saves a GPU screenshot.\n--test-pattern displays black, red, green, blue and white for 20 seconds each."
        );
        return Ok(());
    }
    let test_pattern = args == ["--test-pattern"];
    let capture_path = match args.as_slice() {
        [flag, path] if flag == "--capture" => Some(path.clone()),
        [flag] if flag == "--test-pattern" => None,
        [] => None,
        _ => {
            return Err("unknown arguments; use --help".into());
        }
    };
    slint::BackendSelector::new()
        .backend_name("linuxkms".into())
        .renderer_name("femtovg".into())
        .require_opengl_es_with_version(3, 0)
        .select()?;
    let quit = Arc::new(AtomicBool::new(false));
    for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(signal, quit.clone())?;
    }
    let capture_request = Arc::new(AtomicBool::new(capture_path.is_some()));
    signal_hook::flag::register(signal_hook::consts::SIGUSR1, capture_request.clone())?;
    let capture_failed = Arc::new(AtomicBool::new(false));
    let capture_error = capture_failed.clone();
    let ui = create_ui()?;
    if test_pattern {
        ui.set_test_pattern(0);
        eprintln!("GPU_TEST_PATTERN: black; RGB=000000");
    }
    let render_capture = capture_request.clone();
    gpu::install(&ui, move |ui| {
        if !render_capture.swap(false, Ordering::Relaxed) {
            return;
        }
        let path = capture_path
            .clone()
            .unwrap_or_else(|| "/run/slint-dashboard/frame.png".into());
        match capture_gpu(ui.window(), &path) {
            Ok(()) => eprintln!("GPU_CAPTURE: {path}"),
            Err(error) => {
                eprintln!("GPU_CAPTURE_FAILED: {error}");
                capture_error.store(true, Ordering::Relaxed);
            }
        }
        if capture_path.is_some() {
            let _ = slint::quit_event_loop();
        }
    })?;
    let weak = ui.as_weak();
    let mut tick: u64 = 0;
    let mut pattern_tick = 0u32;
    let timer = slint::Timer::default();
    timer.start(
        slint::TimerMode::Repeated,
        Duration::from_secs(1),
        move || {
            if quit.load(Ordering::Relaxed) {
                let _ = slint::quit_event_loop();
                return;
            }
            if let Some(ui) = weak.upgrade() {
                if test_pattern {
                    pattern_tick += 1;
                    if pattern_tick.is_multiple_of(20) {
                        let index = pattern_tick / 20;
                        let colors = [
                            "black; RGB=000000",
                            "red; RGB=ff0000",
                            "green; RGB=00ff00",
                            "blue; RGB=0000ff",
                            "white; RGB=ffffff",
                        ];
                        if let Some(color) = colors.get(index as usize) {
                            ui.set_test_pattern(index as i32);
                            eprintln!("GPU_TEST_PATTERN: {color}");
                        } else {
                            let _ = slint::quit_event_loop();
                        }
                    }
                }
                if capture_request.load(Ordering::Relaxed) {
                    // Capture a fresh frame even when the dashboard is paused.
                    ui.window().request_redraw();
                }
                if !ui.get_paused() {
                    tick = tick.wrapping_add(1);
                    update(&ui);
                    ui.set_heartbeat(format!("Live sample #{tick}").into());
                }
            }
        },
    );
    eprintln!("slint-dashboard: starting display event loop");
    ui.run()?;
    eprintln!("slint-dashboard: stopped cleanly");
    if capture_failed.load(Ordering::Relaxed) {
        return Err("GPU screenshot failed".into());
    }
    Ok(())
}

fn capture_gpu(window: &slint::Window, path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let pixels = window.take_snapshot()?;
    let file = std::io::BufWriter::new(std::fs::File::create(path)?);
    let mut encoder = png::Encoder::new(file, pixels.width(), pixels.height());
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header()?;
    writer.write_image_data(pixels.as_bytes())?;
    writer.finish()?;
    Ok(())
}

fn create_ui() -> Result<Dashboard, Box<dyn std::error::Error>> {
    let ui = Dashboard::new()?;
    ui.set_kernel_version(
        format!(
            "Linux {}",
            fs::read_to_string("/proc/sys/kernel/osrelease")?.trim()
        )
        .into(),
    );
    update(&ui);
    let weak = ui.as_weak();
    ui.on_reset_counter(move || {
        if let Some(ui) = weak.upgrade() {
            ui.set_count(0);
            eprintln!("UI_ACTION: reset; count=0; paused={}", ui.get_paused());
        }
    });
    let weak = ui.as_weak();
    ui.on_action(move |action| {
        if let Some(ui) = weak.upgrade() {
            eprintln!(
                "UI_ACTION: {action}; count={}; paused={}",
                ui.get_count(),
                ui.get_paused()
            );
        }
    });
    Ok(ui)
}

#[cfg(test)]
mod ui_tests {
    use super::*;
    use slint::{
        LogicalPosition,
        platform::{PointerEventButton, WindowEvent},
    };

    #[test]
    fn pointer_input_drives_dashboard_buttons() {
        snapshot::init().unwrap();
        let ui = create_ui().unwrap();
        ui.show().unwrap();
        ui.window().set_size(slint::PhysicalSize::new(1024, 600));
        // Render once so the actual Slint layout has placed its hit targets.
        ui.window().take_snapshot().unwrap();
        let click = |x, y| {
            let position = LogicalPosition::new(x, y);
            let button = PointerEventButton::Left;
            ui.window()
                .dispatch_event(WindowEvent::PointerPressed { position, button });
            ui.window()
                .dispatch_event(WindowEvent::PointerReleased { position, button });
        };
        click(500.0, 500.0);
        assert_eq!(ui.get_count(), 1);
        click(150.0, 500.0);
        assert!(ui.get_paused());
        click(150.0, 500.0);
        assert!(!ui.get_paused());
        click(840.0, 500.0);
        assert_eq!(ui.get_count(), 0);
        ui.hide().unwrap();
    }
}
