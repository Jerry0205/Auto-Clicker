use serde::{Deserialize, Serialize};
use std::time::Duration;
use thiserror::Error;

pub const MAX_CPS: u32 = 100;
pub const MIN_INTERVAL_MS: u64 = 1_000 / MAX_CPS as u64;
pub const MAX_INTERVAL_MS: u64 = 86_400_000;
pub const MAX_REPEAT_COUNT: u64 = 10_000_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum MouseButton {
    #[default]
    Left,
    Right,
    Middle,
}

impl MouseButton {
    pub const fn evdev_code(self) -> i32 {
        match self {
            Self::Left => 0x110,
            Self::Right => 0x111,
            Self::Middle => 0x112,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum ClickType {
    #[default]
    Single,
    Double,
}

impl ClickType {
    pub const fn clicks_per_tick(self) -> u8 {
        match self {
            Self::Single => 1,
            Self::Double => 2,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RepeatMode {
    UntilStopped,
    Count,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PositionMode {
    CurrentCursor,
    Fixed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MonitorGeometry {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClickSettings {
    pub interval_ms: u64,
    pub button: MouseButton,
    pub click_type: ClickType,
    pub repeat: Option<u64>,
    pub position: Option<(u32, u32)>,
    pub monitor: Option<MonitorGeometry>,
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ValidationError {
    #[error("Das Intervall muss mindestens {MIN_INTERVAL_MS} ms betragen ({MAX_CPS} CPS).")]
    IntervalTooShort,
    #[error("Das Intervall darf höchstens 24 Stunden betragen.")]
    IntervalTooLong,
    #[error("Die Wiederholungszahl muss zwischen 1 und {MAX_REPEAT_COUNT} liegen.")]
    InvalidRepeat,
    #[error("Die festen Koordinaten liegen außerhalb des unterstützten Bereichs.")]
    InvalidCoordinates,
    #[error(
        "Die feste Position liegt außerhalb des ausgewählten Monitors oder es ist kein Monitor verfügbar."
    )]
    InvalidMonitorPosition,
}

impl ClickSettings {
    /// Validate timing, repeat limits and fixed coordinates against their monitor.
    pub fn validate(&self) -> Result<(), ValidationError> {
        validate_interval(self.interval_ms)?;
        if let Some(repeat) = self.repeat
            && !(1..=MAX_REPEAT_COUNT).contains(&repeat)
        {
            return Err(ValidationError::InvalidRepeat);
        }
        if let Some((x, y)) = self.position
            && (x > 100_000 || y > 100_000)
        {
            return Err(ValidationError::InvalidCoordinates);
        }
        if let Some((x, y)) = self.position {
            let monitor = self
                .monitor
                .ok_or(ValidationError::InvalidMonitorPosition)?;
            if monitor.width <= 0
                || monitor.height <= 0
                || x >= monitor.width as u32
                || y >= monitor.height as u32
            {
                return Err(ValidationError::InvalidMonitorPosition);
            }
        }
        Ok(())
    }

    /// Return the configured delay as a scheduler duration.
    pub const fn interval(&self) -> Duration {
        Duration::from_millis(self.interval_ms)
    }

    /// Return the number of click cycles scheduled per second.
    pub fn cps(&self) -> f64 {
        1_000.0 / self.interval_ms as f64
    }
}

/// Enforce the supported interval range and maximum click rate.
pub fn validate_interval(interval_ms: u64) -> Result<(), ValidationError> {
    if interval_ms < MIN_INTERVAL_MS {
        Err(ValidationError::IntervalTooShort)
    } else if interval_ms > MAX_INTERVAL_MS {
        Err(ValidationError::IntervalTooLong)
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_settings() -> ClickSettings {
        ClickSettings {
            interval_ms: 100,
            button: MouseButton::Left,
            click_type: ClickType::Single,
            repeat: None,
            position: None,
            monitor: None,
        }
    }

    #[test]
    fn validates_interval_and_cps_limit() {
        assert_eq!(validate_interval(0), Err(ValidationError::IntervalTooShort));
        assert_eq!(validate_interval(9), Err(ValidationError::IntervalTooShort));
        assert!(validate_interval(10).is_ok());
        assert!(validate_interval(1_000).is_ok());
        assert_eq!(
            validate_interval(MAX_INTERVAL_MS + 1),
            Err(ValidationError::IntervalTooLong)
        );
    }

    #[test]
    fn validates_repeat_count() {
        let mut settings = valid_settings();
        settings.repeat = Some(0);
        assert_eq!(settings.validate(), Err(ValidationError::InvalidRepeat));
        settings.repeat = Some(100);
        assert!(settings.validate().is_ok());
        settings.repeat = Some(MAX_REPEAT_COUNT + 1);
        assert_eq!(settings.validate(), Err(ValidationError::InvalidRepeat));
    }

    #[test]
    fn fixed_position_requires_monitor_and_stays_inside_edges() {
        let mut settings = valid_settings();
        settings.position = Some((1919, 1079));
        assert_eq!(
            settings.validate(),
            Err(ValidationError::InvalidMonitorPosition)
        );
        settings.monitor = Some(MonitorGeometry {
            x: -1920,
            y: 0,
            width: 1920,
            height: 1080,
        });
        assert!(settings.validate().is_ok());
        settings.position = Some((1920, 0));
        assert_eq!(
            settings.validate(),
            Err(ValidationError::InvalidMonitorPosition)
        );
        settings.position = Some((0, 1080));
        assert_eq!(
            settings.validate(),
            Err(ValidationError::InvalidMonitorPosition)
        );
    }

    #[test]
    fn maps_only_supported_mouse_buttons() {
        assert_eq!(MouseButton::Left.evdev_code(), 0x110);
        assert_eq!(MouseButton::Right.evdev_code(), 0x111);
        assert_eq!(MouseButton::Middle.evdev_code(), 0x112);
    }
}
