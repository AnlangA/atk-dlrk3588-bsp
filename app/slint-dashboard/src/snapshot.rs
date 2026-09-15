// SPDX-License-Identifier: GPL-3.0-only
use slint::platform::{
    Platform, WindowAdapter,
    software_renderer::{MinimalSoftwareWindow, RepaintBufferType},
};
use std::rc::Rc;

struct Offscreen(Rc<MinimalSoftwareWindow>);

impl Platform for Offscreen {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, slint::PlatformError> {
        Ok(self.0.clone())
    }
}

pub fn init() -> Result<(), slint::platform::SetPlatformError> {
    slint::platform::set_platform(Box::new(Offscreen(MinimalSoftwareWindow::new(
        RepaintBufferType::NewBuffer,
    ))))
}
