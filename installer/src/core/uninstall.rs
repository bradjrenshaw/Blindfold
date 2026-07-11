use std::fs;
use std::path::Path;

use super::detect::is_reparse_point;
use super::paths::{balatro_data_dir, mods_dir, LOVELY_DLL, MOD_ZIP_DIR, USER_FILES};

#[derive(Debug, PartialEq)]
pub enum UninstallOutcome {
    NotInstalled,
    RemovedFolder,
    /// A deploy.ps1 junction was unlinked; the development checkout it
    /// pointed at is untouched.
    RemovedLink,
}

/// Remove Mods\Blindfold — a real folder is deleted, a developer junction is
/// just unlinked (the checkout behind it is never touched).
pub fn uninstall_mod() -> Result<UninstallOutcome, String> {
    uninstall_mod_at(&mods_dir())
}

pub fn uninstall_mod_at(mods_root: &Path) -> Result<UninstallOutcome, String> {
    let dir = mods_root.join(MOD_ZIP_DIR);
    if is_reparse_point(&dir) {
        // remove_dir on a junction deletes the link itself, never the target
        fs::remove_dir(&dir).map_err(|e| format!("Failed to remove mod link: {}", e))?;
        return Ok(UninstallOutcome::RemovedLink);
    }
    if !dir.exists() {
        return Ok(UninstallOutcome::NotInstalled);
    }
    fs::remove_dir_all(&dir).map_err(|e| format!("Failed to remove mod folder: {}", e))?;
    Ok(UninstallOutcome::RemovedFolder)
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

    #[test]
    fn uninstall_missing_reports_not_installed() {
        let mods = tempfile::tempdir().unwrap();
        assert_eq!(
            uninstall_mod_at(mods.path()).unwrap(),
            UninstallOutcome::NotInstalled
        );
    }

    #[test]
    fn uninstall_removes_real_folder() {
        let mods = tempfile::tempdir().unwrap();
        let dir = mods.path().join("Blindfold");
        fs::create_dir_all(dir.join("loc")).unwrap();
        fs::write(dir.join("lovely.toml"), "").unwrap();

        assert_eq!(
            uninstall_mod_at(mods.path()).unwrap(),
            UninstallOutcome::RemovedFolder
        );
        assert!(!dir.exists());
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn uninstall_unlinks_junction_without_touching_checkout() {
        let mods = tempfile::tempdir().unwrap();
        let checkout = mods.path().join("checkout");
        fs::create_dir(&checkout).unwrap();
        fs::write(checkout.join("core.lua"), "-- kept").unwrap();
        let link = mods.path().join("Blindfold");
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&link)
            .arg(&checkout)
            .status()
            .unwrap();
        assert!(status.success());

        assert_eq!(
            uninstall_mod_at(mods.path()).unwrap(),
            UninstallOutcome::RemovedLink
        );
        assert!(!link.exists());
        // The checkout and its contents survive
        assert_eq!(fs::read(checkout.join("core.lua")).unwrap(), b"-- kept");
    }
}
