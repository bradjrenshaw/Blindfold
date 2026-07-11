use std::path::PathBuf;

pub const GITHUB_API_URL: &str =
    "https://api.github.com/repos/bradjrenshaw/Blindfold/releases/latest";
pub const GITHUB_RELEASES_URL: &str =
    "https://api.github.com/repos/bradjrenshaw/Blindfold/releases";
pub const GAME_DIR_NAME: &str = "Balatro";
pub const USER_AGENT: &str = "BlindfoldInstaller";

/// The Lovely Injector proxy DLL, installed next to Balatro.exe.
pub const LOVELY_DLL: &str = "version.dll";

/// Top-level directory inside the release zip holding the mod payload.
/// Everything under it is extracted into the Mods folder.
pub const MOD_ZIP_DIR: &str = "Blindfold";

/// Files the mod writes into the Balatro save directory (settings, rebinds,
/// speech log). Offered for removal on uninstall; never touched otherwise.
pub const USER_FILES: &[&str] = &[
    "blindfold_settings.lua",
    "blindfold_keybinds.lua",
    "blindfold.log",
];

/// Balatro's save/config directory: %APPDATA%\Balatro. Lovely loads mods from
/// its Mods subfolder (not from the game install directory).
pub fn balatro_data_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("C:\\Users\\Default\\AppData\\Roaming"))
        .join("Balatro")
}

pub fn mods_dir() -> PathBuf {
    balatro_data_dir().join("Mods")
}

pub fn mod_dir() -> PathBuf {
    mods_dir().join(MOD_ZIP_DIR)
}

pub fn version_file() -> PathBuf {
    mod_dir().join("version")
}

/// Open the Mods folder in the file manager, creating it first so Explorer
/// doesn't fall back to Documents on a missing path.
pub fn open_mods_folder() -> Result<(), String> {
    let mods = mods_dir();
    std::fs::create_dir_all(&mods)
        .map_err(|e| format!("Failed to create Mods folder: {}", e))?;
    #[cfg(target_os = "windows")]
    let opener = "explorer";
    #[cfg(not(target_os = "windows"))]
    let opener = "xdg-open";
    std::process::Command::new(opener)
        .arg(&mods)
        .spawn()
        .map_err(|e| format!("Failed to open {}: {}", mods.display(), e))?;
    Ok(())
}

/// Steam roots to probe, best first: the registry-configured install (like
/// scripts/deploy.ps1 uses), then the stock location.
pub fn steam_defaults() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(reg) = steam_registry_path() {
        roots.push(reg);
    }
    let stock = PathBuf::from("C:\\Program Files (x86)\\Steam");
    if !roots.contains(&stock) {
        roots.push(stock);
    }
    roots
}

/// HKCU\Software\Valve\Steam\SteamPath via reg.exe (no console window).
#[cfg(target_os = "windows")]
fn steam_registry_path() -> Option<PathBuf> {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x08000000;
    let out = std::process::Command::new("reg")
        .args(["query", r"HKCU\Software\Valve\Steam", "/v", "SteamPath"])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    parse_reg_sz(&text).map(|v| PathBuf::from(v.replace('/', "\\")))
}

#[cfg(not(target_os = "windows"))]
fn steam_registry_path() -> Option<PathBuf> {
    None
}

/// Pull the value out of a `reg query` REG_SZ result line.
pub fn parse_reg_sz(output: &str) -> Option<String> {
    for line in output.lines() {
        let line = line.trim();
        if let Some(idx) = line.find("REG_SZ") {
            let val = line[idx + "REG_SZ".len()..].trim();
            if !val.is_empty() {
                return Some(val.to_string());
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mod_dir_is_under_mods() {
        assert!(mod_dir().starts_with(mods_dir()));
        assert!(mod_dir().to_string_lossy().ends_with("Blindfold"));
    }

    #[test]
    fn version_file_is_under_mod_dir() {
        assert!(version_file().starts_with(mod_dir()));
    }

    #[test]
    fn balatro_data_dir_named_balatro() {
        assert!(balatro_data_dir().to_string_lossy().contains("Balatro"));
    }

    #[test]
    fn steam_defaults_not_empty() {
        assert!(!steam_defaults().is_empty());
    }

    #[test]
    fn parse_reg_sz_typical_output() {
        let out = "\r\nHKEY_CURRENT_USER\\Software\\Valve\\Steam\r\n    SteamPath    REG_SZ    c:/program files (x86)/steam\r\n\r\n";
        assert_eq!(
            parse_reg_sz(out),
            Some("c:/program files (x86)/steam".to_string())
        );
    }

    #[test]
    fn parse_reg_sz_no_match() {
        assert_eq!(parse_reg_sz("ERROR: The system was unable to find it."), None);
    }
}
