use crate::model::{ClickType, MouseButton, PositionMode, RepeatMode};
use serde::{Deserialize, Serialize};
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
use std::{
    env,
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};
use thiserror::Error;

const APP_DIR: &str = "klickmeister";
const CONFIG_FILE: &str = "config.toml";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct AppConfig {
    pub interval_ms: u64,
    pub mouse_button: MouseButton,
    pub click_type: ClickType,
    pub repeat_mode: RepeatMode,
    pub repeat_count: u64,
    pub position_mode: PositionMode,
    pub fixed_x: u32,
    pub fixed_y: u32,
    pub hotkey: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            interval_ms: 100,
            mouse_button: MouseButton::Left,
            click_type: ClickType::Single,
            repeat_mode: RepeatMode::UntilStopped,
            repeat_count: 100,
            position_mode: PositionMode::CurrentCursor,
            fixed_x: 0,
            fixed_y: 0,
            hotkey: "F6".to_owned(),
        }
    }
}

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("HOME und XDG_CONFIG_HOME sind nicht gesetzt")]
    MissingHome,
    #[error("Konfiguration konnte nicht gelesen werden: {0}")]
    Read(#[source] io::Error),
    #[error("Konfiguration ist ungültig: {0}")]
    Parse(#[source] toml::de::Error),
    #[error("Konfiguration konnte nicht gespeichert werden: {0}")]
    Write(#[source] io::Error),
    #[error("Konfiguration konnte nicht serialisiert werden: {0}")]
    Serialize(#[source] toml::ser::Error),
}

pub fn config_path() -> Result<PathBuf, ConfigError> {
    if let Some(base) = env::var_os("XDG_CONFIG_HOME").filter(|value| !value.is_empty()) {
        return Ok(PathBuf::from(base).join(APP_DIR).join(CONFIG_FILE));
    }
    env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(|home| {
            PathBuf::from(home)
                .join(".config")
                .join(APP_DIR)
                .join(CONFIG_FILE)
        })
        .ok_or(ConfigError::MissingHome)
}

pub fn load() -> Result<AppConfig, ConfigError> {
    let path = config_path()?;
    load_from(&path)
}

pub fn load_from(path: &Path) -> Result<AppConfig, ConfigError> {
    match fs::read_to_string(path) {
        Ok(contents) => toml::from_str(&contents).map_err(ConfigError::Parse),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(AppConfig::default()),
        Err(error) => Err(ConfigError::Read(error)),
    }
}

pub fn save(config: &AppConfig) -> Result<(), ConfigError> {
    let path = config_path()?;
    save_to(&path, config)
}

pub fn save_to(path: &Path, config: &AppConfig) -> Result<(), ConfigError> {
    let parent = path.parent().ok_or_else(|| {
        ConfigError::Write(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Konfigurationspfad hat kein Elternverzeichnis",
        ))
    })?;
    fs::create_dir_all(parent).map_err(ConfigError::Write)?;

    let serialized = toml::to_string_pretty(config).map_err(ConfigError::Serialize)?;
    let temp_path = parent.join(format!(".{CONFIG_FILE}.tmp-{}", std::process::id()));
    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    options.mode(0o600);
    let result = (|| -> io::Result<()> {
        let mut file = options.open(&temp_path)?;
        file.write_all(serialized.as_bytes())?;
        file.sync_all()?;
        fs::rename(&temp_path, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result.map_err(ConfigError::Write)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_ID: AtomicU64 = AtomicU64::new(0);

    fn test_path(name: &str) -> PathBuf {
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        env::temp_dir().join(format!(
            "klickmeister-test-{}-{id}-{name}.toml",
            std::process::id()
        ))
    }

    #[test]
    fn missing_config_uses_defaults() {
        let path = test_path("missing");
        assert_eq!(load_from(&path).ok(), Some(AppConfig::default()));
    }

    #[test]
    fn config_round_trip() {
        let path = test_path("roundtrip");
        let config = AppConfig {
            interval_ms: 250,
            mouse_button: MouseButton::Right,
            click_type: ClickType::Double,
            repeat_mode: RepeatMode::Count,
            repeat_count: 42,
            position_mode: PositionMode::Fixed,
            fixed_x: 640,
            fixed_y: 480,
            hotkey: "F8".to_owned(),
        };
        assert!(save_to(&path, &config).is_ok());
        assert_eq!(load_from(&path).ok(), Some(config));
        let _ = fs::remove_file(path);
    }

    #[test]
    fn rejects_unknown_or_wrongly_typed_fields() {
        let unknown = toml::from_str::<AppConfig>("interval_ms = 100\nsecret = true\n");
        assert!(unknown.is_err());
        let wrong_type = toml::from_str::<AppConfig>("interval_ms = \"fast\"\n");
        assert!(wrong_type.is_err());
    }
}
