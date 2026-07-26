use std::fs;
use std::io::{Cursor, Read};
use std::path::Path;

use super::detect::is_reparse_point;
use super::paths::{mod_dir, mods_dir, version_file, MOD_ZIP_DIR};

pub fn get_installed_version() -> Option<String> {
    let vf = version_file();
    fs::read_to_string(vf).ok().map(|s| s.trim().to_string())
}

/// Installed-version strings are either a release tag (vX.Y.Z, compared by
/// semver against GitHub releases) or a dev build from main ("main@<sha>",
/// compared by commit against the tip of main).
pub fn is_dev_version(v: &str) -> bool {
    v == "main" || v.starts_with("main@")
}

pub fn dev_sha(v: &str) -> Option<&str> {
    v.strip_prefix("main@")
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

fn should_skip_mod_file(rest: &str) -> bool {
    use super::paths::EXCLUDED_MOD_FILES;
    let normalized = rest.replace('\\', "/");
    EXCLUDED_MOD_FILES.iter().any(|&excluded| normalized == excluded)
}

/// Where a zip entry belongs.
enum Route {
    /// The Lovely Injector proxy -> next to Balatro.exe
    LovelyFile(String),
    /// A mod file -> Mods\Blindfold\<path>
    Mod(String),
    Skip,
}

/// A release zip (scripts\build_release.ps1): version.dll/liblovely.dylib/run_lovely_macos.sh at the root,
/// payload under Blindfold/.
fn route_release(name: &str) -> Route {
    use super::paths::LOVELY_FILES;
    if LOVELY_FILES.contains(&name) {
        Route::LovelyFile(name.to_string())
    } else if let Some(rest) = name.strip_prefix("Blindfold/") {
        if should_skip_mod_file(rest) {
            Route::Skip
        } else {
            Route::Mod(rest.to_string())
        }
    } else {
        Route::Skip
    }
}

/// A GitHub branch zipball: everything under one top-level folder
/// (e.g. Blindfold-main/), with the mod at src/ and Lovely at
/// third_party/lovely/version.dll — the same layout scripts/deploy.ps1
/// installs from.
fn route_repo(name: &str) -> Route {
    use super::paths::LOVELY_FILES;
    let Some((_top, rest)) = name.split_once('/') else {
        return Route::Skip;
    };
    if let Some(filename) = rest.strip_prefix("third_party/lovely/") {
        if LOVELY_FILES.contains(&filename) {
            return Route::LovelyFile(filename.to_string());
        }
    }
    if let Some(mod_path) = rest.strip_prefix("src/") {
        if should_skip_mod_file(mod_path) {
            Route::Skip
        } else {
            Route::Mod(mod_path.to_string())
        }
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
/// untouched. An existing version.dll is never overwritten (see below).
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
            Route::LovelyFile(filename) => (game_path.join(filename), true),
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

        // An existing Lovely injector file is left alone entirely: the user may run
        // other Lovely mods with a newer injector than our bundled one, and
        // overwriting would downgrade their whole setup. Only a missing file
        // is written (also keeps updates elevation-free).
        if is_dll && dest.exists() {
            continue;
        }

        fs::write(&dest, &contents).map_err(|e| {
            if is_dll {
                format!(
                    "Couldn't write {} into the game folder: {}. \
                     Re-run this installer as administrator (the game may live \
                     under Program Files).",
                    dest.file_name().unwrap_or_default().to_string_lossy(), e
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
            ("version.dll", b"lovely dll"),
            ("liblovely.dylib", b"lovely dylib"),
            ("run_lovely_macos.sh", b"lovely sh"),
            ("Blindfold/lovely.toml", b"[manifest]"),
            ("Blindfold/core.lua", b"-- core"),
            ("Blindfold/lib/prism.dll", b"prism dll"),
            ("Blindfold/lib/libprism.dylib", b"prism dylib"),
        ]);

        install_zip_to(&zip, game.path(), mods.path()).unwrap();

        #[cfg(target_os = "windows")]
        {
            assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely dll");
            assert!(!game.path().join("liblovely.dylib").exists());
            assert!(!game.path().join("run_lovely_macos.sh").exists());
            let md = mods.path().join("Blindfold");
            assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
            assert_eq!(fs::read(md.join("lib").join("prism.dll")).unwrap(), b"prism dll");
            assert!(!md.join("lib").join("libprism.dylib").exists());
        }

        #[cfg(target_os = "macos")]
        {
            assert!(!game.path().join("version.dll").exists());
            assert_eq!(fs::read(game.path().join("liblovely.dylib")).unwrap(), b"lovely dylib");
            assert_eq!(fs::read(game.path().join("run_lovely_macos.sh")).unwrap(), b"lovely sh");
            let md = mods.path().join("Blindfold");
            assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
            assert!(!md.join("lib").join("prism.dll").exists());
            assert_eq!(fs::read(md.join("lib").join("libprism.dylib")).unwrap(), b"prism dylib");
        }
        
        assert!(!game.path().join("Blindfold").exists());
    }

    #[test]
    fn install_handles_backslash_entry_names() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[
            ("version.dll", b"lovely dll"),
            ("liblovely.dylib", b"lovely dylib"),
            ("run_lovely_macos.sh", b"lovely sh"),
            ("Blindfold\\lovely.toml", b"[manifest]"),
            ("Blindfold\\lib\\prism.dll", b"prism dll"),
            ("Blindfold\\lib\\libprism.dylib", b"prism dylib"),
        ]);

        install_zip_to(&zip, game.path(), mods.path()).unwrap();

        #[cfg(target_os = "windows")]
        {
            assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely dll");
            let md = mods.path().join("Blindfold");
            assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
            assert_eq!(fs::read(md.join("lib").join("prism.dll")).unwrap(), b"prism dll");
            assert!(!md.join("lib").join("libprism.dylib").exists());
        }

        #[cfg(target_os = "macos")]
        {
            assert_eq!(fs::read(game.path().join("liblovely.dylib")).unwrap(), b"lovely dylib");
            let md = mods.path().join("Blindfold");
            assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
            assert!(!md.join("lib").join("prism.dll").exists());
            assert_eq!(fs::read(md.join("lib").join("libprism.dylib")).unwrap(), b"prism dylib");
        }
    }

    #[test]
    fn install_repo_zip_routes_src_and_lovely() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[
            ("Blindfold-main/README.md", b"docs"),
            ("Blindfold-main/src/lovely.toml", b"[manifest]"),
            ("Blindfold-main/src/core.lua", b"-- core"),
            ("Blindfold-main/src/lib/prism.dll", b"prism dll"),
            ("Blindfold-main/src/lib/libprism.dylib", b"prism dylib"),
            ("Blindfold-main/third_party/lovely/version.dll", b"lovely dll"),
            ("Blindfold-main/third_party/lovely/liblovely.dylib", b"lovely dylib"),
            ("Blindfold-main/third_party/lovely/run_lovely_macos.sh", b"lovely sh"),
            ("Blindfold-main/scripts/deploy.ps1", b"# script"),
        ]);

        install_repo_zip_to(&zip, game.path(), mods.path()).unwrap();

        #[cfg(target_os = "windows")]
        {
            assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely dll");
            let md = mods.path().join("Blindfold");
            assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
            assert_eq!(fs::read(md.join("core.lua")).unwrap(), b"-- core");
            assert_eq!(fs::read(md.join("lib").join("prism.dll")).unwrap(), b"prism dll");
            assert!(!md.join("lib").join("libprism.dylib").exists());
        }

        #[cfg(target_os = "macos")]
        {
            assert_eq!(fs::read(game.path().join("liblovely.dylib")).unwrap(), b"lovely dylib");
            assert_eq!(fs::read(game.path().join("run_lovely_macos.sh")).unwrap(), b"lovely sh");
            let md = mods.path().join("Blindfold");
            assert_eq!(fs::read(md.join("lovely.toml")).unwrap(), b"[manifest]");
            assert_eq!(fs::read(md.join("core.lua")).unwrap(), b"-- core");
            assert!(!md.join("lib").join("prism.dll").exists());
            assert_eq!(fs::read(md.join("lib").join("libprism.dylib")).unwrap(), b"prism dylib");
        }

        let md = mods.path().join("Blindfold");
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
    fn install_leaves_existing_dll_alone() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        
        let primary_file = if cfg!(target_os = "macos") { "liblovely.dylib" } else { "version.dll" };
        
        fs::write(game.path().join(primary_file), b"newer lovely").unwrap();
        let zip = make_zip(&[
            ("version.dll", b"bundled lovely dll"),
            ("liblovely.dylib", b"bundled lovely dylib"),
            ("run_lovely_macos.sh", b"bundled lovely sh"),
            ("Blindfold/lovely.toml", b"ok"),
        ]);
        install_zip_to(&zip, game.path(), mods.path()).unwrap();
        assert_eq!(
            fs::read(game.path().join(primary_file)).unwrap(),
            b"newer lovely"
        );
    }

    #[test]
    fn install_writes_missing_dll() {
        let game = tempfile::tempdir().unwrap();
        let mods = tempfile::tempdir().unwrap();
        let zip = make_zip(&[
            ("version.dll", b"lovely dll"),
            ("liblovely.dylib", b"lovely dylib"),
            ("run_lovely_macos.sh", b"lovely sh"),
            ("Blindfold/lovely.toml", b"ok"),
        ]);
        install_zip_to(&zip, game.path(), mods.path()).unwrap();
        
        #[cfg(target_os = "windows")]
        assert_eq!(fs::read(game.path().join("version.dll")).unwrap(), b"lovely dll");
        
        #[cfg(target_os = "macos")]
        {
            assert_eq!(fs::read(game.path().join("liblovely.dylib")).unwrap(), b"lovely dylib");
            assert_eq!(fs::read(game.path().join("run_lovely_macos.sh")).unwrap(), b"lovely sh");
        }
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
    fn dev_version_detection() {
        assert!(is_dev_version("main"));
        assert!(is_dev_version("main@abc1234"));
        assert!(!is_dev_version("v0.1.0"));
        assert_eq!(dev_sha("main@abc1234"), Some("abc1234"));
        assert_eq!(dev_sha("main"), None);
        assert_eq!(dev_sha("v0.1.0"), None);
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
