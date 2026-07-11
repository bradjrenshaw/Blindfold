use std::fs;
use std::path::Path;

use super::detect::is_reparse_point;
use super::paths::{balatro_data_dir, mod_dir, mods_dir, LOVELY_DLL, MOD_ZIP_DIR, USER_FILES};

/// Remove Mods\Blindfold. Returns Ok(true) if it was removed, Ok(false) if it
/// wasn't there; refuses to touch a developer link.
pub fn uninstall_mod() -> Result<bool, String> {
    let dir = mod_dir();
    if !dir.exists() {
        return Ok(false);
    }
    if is_reparse_point(&dir) {
        return Err(format!(
            "'{}' is a link into a development checkout. \
             Remove it with scripts\\deploy.ps1 -Uninstall instead.",
            dir.display()
        ));
    }
    fs::remove_dir_all(&dir).map_err(|e| format!("Failed to remove mod folder: {}", e))?;
    Ok(true)
}

/// Other entries in the Mods folder — other Lovely mods that still need
/// version.dll if the user has any.
pub fn other_mods_present() -> bool {
    let mods = mods_dir();
    match fs::read_dir(&mods) {
        Ok(entries) => entries
            .flatten()
            .any(|e| e.file_name().to_string_lossy() != MOD_ZIP_DIR),
        Err(_) => false,
    }
}

/// Remove the Lovely Injector proxy from the game folder.
pub fn remove_lovely(game_path: &Path) -> Result<bool, String> {
    let dll = game_path.join(LOVELY_DLL);
    if !dll.exists() {
        return Ok(false);
    }
    fs::remove_file(&dll).map_err(|e| {
        format!(
            "Failed to remove {}: {}. You may need to re-run as administrator.",
            LOVELY_DLL, e
        )
    })?;
    Ok(true)
}

/// Remove the mod's settings, rebinds, and speech log from %APPDATA%\Balatro.
/// Game saves are never touched.
pub fn remove_user_files() -> Vec<String> {
    let data = balatro_data_dir();
    let mut removed = Vec::new();
    for f in USER_FILES {
        let fp = data.join(f);
        if fp.exists() && fs::remove_file(&fp).is_ok() {
            removed.push(f.to_string());
        }
    }
    removed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remove_lovely_missing_is_ok() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(remove_lovely(dir.path()).unwrap(), false);
    }

    #[test]
    fn remove_lovely_deletes_dll() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("version.dll"), "").unwrap();
        assert_eq!(remove_lovely(dir.path()).unwrap(), true);
        assert!(!dir.path().join("version.dll").exists());
    }
}
