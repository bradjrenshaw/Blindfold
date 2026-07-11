use std::fs;
use std::io::{Cursor, Read};
use std::path::Path;

use super::detect::is_reparse_point;
use super::paths::{mod_dir, mods_dir, version_file, LOVELY_DLL, MOD_ZIP_DIR};

pub fn get_installed_version() -> Option<String> {
    let vf = version_file();
    fs::read_to_string(vf).ok().map(|s| s.trim().to_string())
}

pub fn save_installed_version(version: &str) -> Result<(), String> {
    let dir = mod_dir();
    fs::create_dir_all(&dir).map_err(|e| format!("Failed to create directory: {}", e))?;
    fs::write(version_file(), version).map_err(|e| format!("Failed to write version: {}", e))
}

pub fn download(url: &str, progress: impl Fn(u32)) -> Result<Vec<u8>, String> {
    let client = reqwest::blocking::Client::builder()
        .user_agent(super::paths::USER_AGENT)
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {}", e))?;

    let resp = client
        .get(url)
        .send()
        .map_err(|e| format!("Download failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("Download returned status {}", resp.status()));
    }

    let total = resp.content_length().unwrap_or(0);
    let mut reader = resp;
    let mut buffer = Vec::new();
    let mut downloaded: u64 = 0;
    let mut buf = [0u8; 8192];

    loop {
        let n = reader
            .read(&mut buf)
            .map_err(|e| format!("Read error: {}", e))?;
        if n == 0 {
            break;
        }
        buffer.extend_from_slice(&buf[..n]);
        downloaded += n as u64;
        if total > 0 {
            progress((downloaded * 100 / total) as u32);
        }
    }

    Ok(buffer)
}

pub fn download_and_extract(
    url: &str,
    game_path: &Path,
    progress: impl Fn(u32),
) -> Result<(), String> {
    let data = download(url, progress)?;
    install_zip(&data, game_path)
}

/// Download and install the latest commit on main (GitHub branch zipball).
pub fn download_and_install_repo(
    url: &str,
    game_path: &Path,
    progress: impl Fn(u32),
) -> Result<(), String> {
    let data = download(url, progress)?;
    install_repo_zip(&data, game_path)
}

pub fn install_from_file(zip_path: &Path, game_path: &Path) -> Result<(), String> {
    let data = fs::read(zip_path).map_err(|e| format!("Failed to read zip: {}", e))?;
    install_zip(&data, game_path)
}

/// Where a zip entry belongs.
enum Route {
    /// The Lovely Injector proxy -> next to Balatro.exe
    LovelyDll,
    /// A mod file -> Mods\Blindfold\<path>
    Mod(String),
    Skip,
}

/// A release zip (scripts\build_release.ps1): version.dll at the root,
/// payload under Blindfold/.
fn route_release(name: &str) -> Route {
    if name == LOVELY_DLL {
        Route::LovelyDll
    } else if let Some(rest) = name.strip_prefix("Blindfold/") {
        Route::Mod(rest.to_string())
    } else {
        Route::Skip
    }
}

/// A GitHub branch zipball: everything under one top-level folder
/// (e.g. Blindfold-main/), with the mod at src/ and Lovely at
/// third_party/lovely/version.dll — the same layout scripts/deploy.ps1
/// installs from.
fn route_repo(name: &str) -> Route {
    let Some((_top, rest)) = name.split_once('/') else {
        return Route::Skip;
    };
    if rest == "third_party/lovely/version.dll" {
        Route::LovelyDll
    } else if let Some(mod_path) = rest.strip_prefix("src/") {
        Route::Mod(mod_path.to_string())
    } else {
        Route::Skip
    }
}

pub fn install_zip(data: &[u8], game_path: &Path) -> Result<(), String> {
    extract_routed(data, game_path, &mods_dir(), route_release, "a Blindfold release")
}

pub fn install_repo_zip(data: &[u8], game_path: &Path) -> Result<(), String> {
    extract_routed(data, game_path, &mods_dir(), route_repo, "a Blindfold repository")
}

#[cfg(test)]
pub fn install_zip_to(data: &[u8], game_path: &Path, mods_root: &Path) -> Result<(), String> {
    extract_routed(data, game_path, mods_root, route_release, "a Blindfold release")
}

#[cfg(test)]
pub fn install_repo_zip_to(data: &[u8], game_path: &Path, mods_root: &Path) -> Result<(), String> {
    extract_routed(data, game_path, mods_root, route_repo, "a Blindfold repository")
}

/// Extract a zip, sending each entry where its route says. The existing
/// Blindfold folder is replaced wholesale so updates never leave stale files
/// behind; user settings live outside it (%APPDATA%\Balatro) and are
/// untouched. An identical version.dll is skipped: rewriting it needs write
/// access to the game folder (Program Files on some machines), so don't
/// demand elevation for a no-op.
fn extract_routed(
    data: &[u8],
    game_path: &Path,
    mods_root: &Path,
    route: impl Fn(&str) -> Route,
    expected: &str,
) -> Result<(), String> {
    let cursor = Cursor::new(data);
    let mut archive =
        zip::ZipArchive::new(cursor).map_err(|e| format!("Failed to open zip: {}", e))?;

    let has_payload = (0..archive.len()).any(|i| {
        archive
            .by_index(i)
            .map(|f| matches!(route(&f.name().replace('\\', "/")), Route::Mod(_)))
            .unwrap_or(false)
    });
    if !has_payload {
        return Err(format!("This zip doesn't look like {}.", expected));
    }

    let target_mod_dir = mods_root.join(MOD_ZIP_DIR);
    if is_reparse_point(&target_mod_dir) {
        return Err(format!(
            "'{}' is a link into a development checkout (scripts\\deploy.ps1). \
             Update with 'git pull' instead, or Uninstall first to remove the \
             link (the checkout is left alone).",
            target_mod_dir.display()
        ));
    }
    if target_mod_dir.exists() {
        fs::remove_dir_all(&target_mod_dir)
            .map_err(|e| format!("Failed to remove old mod folder: {}", e))?;
    }

    for i in 0..archive.len() {
        let mut file = archive
            .by_index(i)
            .map_err(|e| format!("Failed to read zip entry: {}", e))?;

        let name = file.name().replace('\\', "/");
        if file.enclosed_name().is_none() {
            return Err(format!("Unsafe path in zip: {}", name));
        }

        let (dest, is_dll) = match route(&name) {
            Route::LovelyDll => (game_path.join(LOVELY_DLL), true),
            Route::Mod(rest) => {
                if rest.is_empty() {
                    continue;
                }
                (target_mod_dir.join(&rest), false)
            }
            Route::Skip => continue,
        };

        if name.ends_with('/') {
            fs::create_dir_all(&dest)
                .map_err(|e| format!("Failed to create dir {}: {}", name, e))?;
            continue;
        }

        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create parent dir: {}", e))?;
        }

        let mut contents = Vec::new();
        file.read_to_end(&mut contents)
            .map_err(|e| format!("Failed to read {}: {}", name, e))?;

        if is_dll {
            if let Ok(existing) = fs::read(&dest) {
                if existing == contents {
                    continue;
                }
            }
        }

        fs::write(&dest, &contents).map_err(|e| {
            if is_dll {
                format!(
                    "Couldn't write {} into the game folder: {}. \
                     Re-run this installer as administrator (the game may live \
                     under Program Files).",
                    LOVELY_DLL, e
                )
            } else {
                format!("Failed to write file {}: {}", name, e)
            }
        })?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn make_zip(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let mut zip_buf = Vec::new();
        {
            let cursor = Cursor::new(&mut zip_buf);
            let mut writer = zip::ZipWriter::new(cursor);
            let options = zip::write::SimpleFileOptions::default();
            for (name, data) in entries {
                writer.start_file(*name, options).unwrap();
                writer.write_all(data).unwrap();
            }
            writer.finish().unwrap();
        }
        zip_buf
    }

    #[test]
    fn install_routes_dll_and_payload() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();

        let zip = make_zip(&[
            ("version.dll", b"lovely"),
            ("Blindfold/lovely.toml", b"[manifest]"),
            ("Blindfold/core.lua", b"-- core"),
            ("Blindfold/lib/Tolk.dll", b"tolk"),
        ]);

        install_zip_to(&zip, game.path(), mods.path()).unwrap();

        assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely");
        let md = mods.path().join("Blindfold");
        assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
        assert_eq!(fs::read(md.join("lib").join("Tolk.dll")).unwrap(), b"tolk");
        // Nothing but the DLL lands in the game folder
        assert!(!game.path().join("Blindfold").exists());
    }

    #[test]
    fn install_handles_backslash_entry_names() {
        // PowerShell's Compress-Archive (scripts\build_release.ps1) writes
        // entry names with backslashes; routing must still work.
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[
            ("version.dll", b"lovely"),
            ("Blindfold\\lovely.toml", b"[manifest]"),
            ("Blindfold\\lib\\Tolk.dll", b"tolk"),
        ]);

        install_zip_to(&zip, game.path(), mods.path()).unwrap();

        assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely");
        let md = mods.path().join("Blindfold");
        assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
        assert_eq!(fs::read(md.join("lib").join("Tolk.dll")).unwrap(), b"tolk");
    }

    #[test]
    fn install_repo_zip_routes_src_and_lovely() {
        // GitHub zipball layout: one top-level folder named <repo>-<branch>
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[
            ("Blindfold-main/README.md", b"docs"),
            ("Blindfold-main/src/lovely.toml", b"[manifest]"),
            ("Blindfold-main/src/core.lua", b"-- core"),
            ("Blindfold-main/src/lib/Tolk.dll", b"tolk"),
            ("Blindfold-main/third_party/lovely/version.dll", b"lovely"),
            ("Blindfold-main/scripts/deploy.ps1", b"# script"),
        ]);

        install_repo_zip_to(&zip, game.path(), mods.path()).unwrap();

        assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely");
        let md = mods.path().join("Blindfold");
        assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
        assert_eq!(fs::read(md.join("core.lua")).unwrap(), b"-- core");
        assert_eq!(fs::read(md.join("lib").join("Tolk.dll")).unwrap(), b"tolk");
        // Repo files outside src/ stay out of the install
        assert!(!md.join("README.md").exists());
        assert!(!md.join("scripts").exists());
        assert!(!mods.path().join("README.md").exists());
    }

    #[test]
    fn install_repo_zip_rejects_non_repo() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[("Blindfold-main/README.md", b"no src here")]);
        let err = install_repo_zip_to(&zip, game.path(), mods.path()).unwrap_err();
        assert!(err.contains("repository"));
    }

    #[test]
    fn install_replaces_old_mod_folder() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let old = mods.path().join("Blindfold");
        fs::create_dir_all(old.join("stale")).unwrap();
        fs::write(old.join("stale").join("gone.lua"), "old").unwrap();

        let zip = make_zip(&[("Blindfold/lovely.toml", b"new")]);
        install_zip_to(&zip, game.path(), mods.path()).unwrap();

        assert!(!old.join("stale").exists());
        assert_eq!(fs::read(old.join("lovely.toml")).unwrap(), b"new");
    }

    #[test]
    fn install_rejects_zip_without_payload() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[("readme.txt", b"hi")]);
        let err = install_zip_to(&zip, game.path(), mods.path()).unwrap_err();
        assert!(err.contains("Blindfold"));
    }

    #[test]
    fn install_ignores_unrelated_entries() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[
            ("Blindfold/lovely.toml", b"ok"),
            ("stray.txt", b"ignored"),
        ]);
        install_zip_to(&zip, game.path(), mods.path()).unwrap();
        assert!(!game.path().join("stray.txt").exists());
        assert!(!mods.path().join("stray.txt").exists());
    }

    #[test]
    fn install_skips_identical_dll() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        fs::write(game.path().join("version.dll"), b"lovely").unwrap();
        let zip = make_zip(&[
            ("version.dll", b"lovely"),
            ("Blindfold/lovely.toml", b"ok"),
        ]);
        install_zip_to(&zip, game.path(), mods.path()).unwrap();
        assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely");
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn install_refuses_dev_link() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let target = mods.path().join("checkout");
        fs::create_dir(&target).unwrap();
        let link = mods.path().join("Blindfold");
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&link)
            .arg(&target)
            .status()
            .unwrap();
        assert!(status.success());

        let zip = make_zip(&[("Blindfold/lovely.toml", b"ok")]);
        let err = install_zip_to(&zip, game.path(), mods.path()).unwrap_err();
        assert!(err.contains("git pull"));
        // The link target is untouched
        assert!(target.exists());
    }

    #[test]
    fn version_roundtrip_format() {
        let dir = tempfile::tempdir().unwrap();
        let vf = dir.path().join("version");
        fs::write(&vf, "v0.1.0\n").unwrap();
        let content = fs::read_to_string(&vf).unwrap().trim().to_string();
        assert_eq!(content, "v0.1.0");
    }
}
