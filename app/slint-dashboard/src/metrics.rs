// SPDX-License-Identifier: GPL-3.0-only
use std::{fs, path::Path};

#[derive(Debug)]
pub struct Metrics {
    pub uptime: String,
    pub temperature: String,
    pub memory: String,
}

fn uptime(text: &str) -> Option<String> {
    let seconds = text
        .split_whitespace()
        .next()?
        .split('.')
        .next()?
        .parse::<u64>()
        .ok()?;
    Some(format!(
        "{:02}:{:02}:{:02}",
        seconds / 3600,
        seconds / 60 % 60,
        seconds % 60
    ))
}

fn memory(text: &str) -> Option<String> {
    let field = |name: &str| {
        text.lines().find_map(|line| {
            let mut fields = line.split_whitespace();
            (fields.next()? == name)
                .then(|| fields.next()?.parse::<u64>().ok())
                .flatten()
        })
    };
    let total = field("MemTotal:")?;
    let available = field("MemAvailable:")?;
    if total == 0 || available > total {
        return None;
    }
    Some(format!(
        "{:.0}%",
        (total - available) as f64 / total as f64 * 100.0
    ))
}

fn temperature(sys: &Path) -> Option<String> {
    // Thermal zone numbers are not an ABI. Select the RK3588 SoC zone by type.
    for entry in fs::read_dir(sys.join("class/thermal")).ok()?.flatten() {
        let path = entry.path();
        let Ok(kind) = fs::read_to_string(path.join("type")) else {
            continue;
        };
        if !matches!(kind.trim(), "package-thermal" | "soc-thermal") {
            continue;
        }
        let value = fs::read_to_string(path.join("temp"))
            .ok()?
            .trim()
            .parse::<i32>()
            .ok()?;
        return Some(format!("{:.1} °C", f64::from(value) / 1000.0));
    }
    None
}

impl Metrics {
    pub fn read() -> Self {
        Self {
            uptime: fs::read_to_string("/proc/uptime")
                .ok()
                .and_then(|s| uptime(&s))
                .unwrap_or_else(|| "N/A".into()),
            memory: fs::read_to_string("/proc/meminfo")
                .ok()
                .and_then(|s| memory(&s))
                .unwrap_or_else(|| "N/A".into()),
            temperature: temperature(Path::new("/sys")).unwrap_or_else(|| "N/A".into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uptime_handles_long_running_and_invalid_systems() {
        assert_eq!(uptime("90061.25 20.00"), Some("25:01:01".into()));
        assert_eq!(uptime(""), None);
        assert_eq!(uptime("-1.0"), None);
    }

    #[test]
    fn memory_uses_available_including_reclaimable_cache() {
        assert_eq!(
            memory("MemFree: 100 kB\nMemTotal: 1000 kB\nMemAvailable: 600 kB\n"),
            Some("40%".into())
        );
        assert_eq!(memory("MemTotal: 0 kB\nMemAvailable: 0 kB"), None);
        assert_eq!(memory("MemTotal: 10 kB\nMemAvailable: 11 kB"), None);
        assert_eq!(memory("MemTotal: 1000 kB\n"), None);
    }
}
