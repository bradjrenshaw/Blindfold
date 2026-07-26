use regex::Regex;
use std::path::{Path, PathBuf};

use super::paths::{mod_dir, steam_defaults, GAME_DIR_NAME};

#[cfg(target_os = "macos")]
const VALIDATION_MARKERS: &[&str] = &["Balatro.app"];

#[cfg(not(target_os = "macos"))]
const VALIDATION_MARKERS: &[&str] = &["Balatro.exe"];

pub fn detect_game_path() -> Option<PathBuf> {
    for steam_dir in steam_defaults() {
        // Try libraryfolders.vdf (lists every Steam library, any drive)
        let vdf_path = steam_dir.join("steamapps").join("libraryfolders.vdf");
        if vdf_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&vdf_path) {
                for lib_path in parse_vdf_library_paths(&content) {
                    let game_path = lib_path.join("steamapps").join("common").join(GAME_DIR_NAME);
                    if validate_game_path(&game_path) {
                        return Some(game_path);
                    }
                }
            }
        }

        // Try the library at the Steam root itself
        let default_path = steam_dir.join("steamapps").join("common").join(GAME_DIR_NAME);
        if validate_game_path(&default_path) {
            return Some(default_path);
        }
    }
    None
}

pub fn parse_vdf_library_paths(content: &str) -> Vec<PathBuf> {
    let re = Regex::new(r#""path"\s+"([^"]+)""#).unwrap();
    re.captures_iter(content)
        .map(|cap| {
            let raw = cap[1].replace("\\\\", "\\");
            PathBuf::from(raw)
        })
        .collect()
}

pub fn validate_game_path(path: &Path) -> bool {
    VALIDATION_MARKERS.iter().any(|m| path.join(m).exists())
}

/// The mod lives in %APPDATA%\Balatro\Mods\Blindfold, not the game folder.
pub fn is_mod_installed() -> bool {
    mod_dir().join("lovely.toml").exists()
}

/// True when Mods\Blindfold is a junction/symlink — a developer install made
/// by scripts/deploy.ps1. The installer must not delete or overwrite it.
pub fn is_dev_link() -> bool {
    is_reparse_point(&mod_dir())
}

/// Reparse-point check that catches both junctions and symlinks (Rust's
/// is_symlink() misses junctions on some toolchains).
pub fn is_reparse_point(path: &Path) -> bool {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        std::fs::symlink_metadata(path)
            .map(|m| m.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0)
            .unwrap_or(false)
    }
    #[cfg(not(target_os = "windows"))]
    {
        std::fs::symlink_metadata(path)
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn parse_vdf_empty_content() {
        let paths = parse_vdf_library_paths("");
        assert!(paths.is_empty());
    }

    #[test]
    fn parse_vdf_single_path() {
        let content = r#"
        "0"
        {
            "path"		"C:\\Program Files (x86)\\Steam"
            "label"		""
        }
        "#;
        let paths = parse_vdf_library_paths(content);
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0], PathBuf::from("C:\\Program Files (x86)\\Steam"));
    }

    #[test]
    fn parse_vdf_multiple_paths() {
        let content = r#"
        "0"
        {
            "path"		"C:\\Program Files (x86)\\Steam"
        }
        "1"
        {
            "path"		"D:\\SteamLibrary"
        }
        "#;
        let paths = parse_vdf_library_paths(content);
        assert_eq!(paths.len(), 2);
        assert_eq!(paths[1], PathBuf::from("D:\\SteamLibrary"));
    }

    #[test]
    fn parse_vdf_malformed_content() {
        let paths = parse_vdf_library_paths("this is not valid vdf content at all");
        assert!(paths.is_empty());
    }

    #[test]
    fn validate_game_path_with_marker() {
        let dir = tempfile::tempdir().unwrap();
        let marker = VALIDATION_MARKERS[0];
        fs::write(dir.path().join(marker), "").unwrap();
        assert!(validate_game_path(dir.path()));
    }

    #[test]
    fn validate_game_path_empty_dir() {
        let dir = tempfile::tempdir().unwrap();
        assert!(!validate_game_path(dir.path()));
    }

    #[test]
    fn reparse_point_false_for_real_dir() {
        let dir = tempfile::tempdir().unwrap();
        assert!(!is_reparse_point(dir.path()));
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn reparse_point_true_for_junction() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("target");
        fs::create_dir(&target).unwrap();
        let link = dir.path().join("link");
        // Make a junction with mklink (no admin needed for junctions)
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&link)
            .arg(&target)
            .status()
            .unwrap();
        assert!(status.success());
        assert!(is_reparse_point(&link));
    }
}
