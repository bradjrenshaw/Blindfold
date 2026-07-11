use std::io::{self, Write};
use std::path::PathBuf;

use crate::core::{detect, github, install, uninstall};

pub fn run() {
    println!("=== Blindfold Installer ===");
    println!();

    let game_path = match get_game_path() {
        Some(p) => p,
        None => {
            println!("Error: Invalid game directory.");
            return;
        }
    };

    println!();
    show_status();
    println!();

    loop {
        println!("Options:");
        println!("  1. Install / Update from GitHub");
        println!("  2. Install from local zip file");
        println!("  3. Uninstall");
        println!("  4. Exit");
        println!();

        let choice = prompt("Choose an option (1-4): ");

        println!();
        match choice.as_str() {
            "1" => install_from_github(&game_path),
            "2" => install_from_file(&game_path),
            "3" => do_uninstall(&game_path),
            "4" => return,
            _ => println!("Invalid option."),
        }
        println!();
    }
}

fn get_game_path() -> Option<PathBuf> {
    if let Some(detected) = detect::detect_game_path() {
        println!("Detected game directory: {}", detected.display());
        let response = prompt("Use this path? (Y/n): ");
        if response != "n" && response != "no" {
            return Some(detected);
        }
    }

    let input = prompt("Press B to browse for the game directory, or type the path: ");
    if input.eq_ignore_ascii_case("b") {
        let path = rfd::FileDialog::new()
            .set_title("Select the Balatro game directory")
            .pick_folder();
        match path {
            Some(p) if detect::validate_game_path(&p) => Some(p),
            Some(_) => {
                println!("Error: No Balatro.exe in the selected directory.");
                None
            }
            None => {
                println!("Browse cancelled.");
                None
            }
        }
    } else {
        let path = PathBuf::from(&input);
        if detect::validate_game_path(&path) {
            Some(path)
        } else {
            None
        }
    }
}

fn show_status() {
    if detect::is_dev_link() {
        println!("Developer install detected (Mods\\Blindfold is a link into a checkout).");
        println!("Update with 'git pull', or uninstall to remove the link (the checkout");
        println!("itself is left alone) and install a release instead.");
    } else if detect::is_mod_installed() {
        let version = install::get_installed_version().unwrap_or_else(|| "unknown".to_string());
        println!("Blindfold is installed (version: {}).", version);
    } else {
        println!("Blindfold is not currently installed.");
    }
}

fn install_from_github(game_path: &PathBuf) {
    println!("Checking for latest release...");

    let release = match github::fetch_latest_release() {
        Ok(r) => r,
        Err(e) => {
            println!("Error: {}", e);
            return;
        }
    };

    println!("Latest version: {}", release.tag_name);

    let installed = install::get_installed_version();
    if installed.as_deref() == Some(&release.tag_name) && detect::is_mod_installed() {
        let response = prompt("You already have the latest version. Reinstall anyway? (y/N): ");
        if response != "y" && response != "yes" {
            return;
        }
    }

    if !release.body.is_empty() {
        println!();
        println!("Release notes:");
        println!("{}", release.body);
        println!();
    }

    let confirm = prompt("Proceed with installation? (Y/n): ");
    if confirm == "n" || confirm == "no" {
        return;
    }

    let asset = match github::find_zip_asset(&release.assets) {
        Some(a) => a,
        None => {
            println!("Error: No .zip asset found in the release.");
            return;
        }
    };

    println!("Downloading {}...", asset.name);

    match install::download_and_extract(&asset.browser_download_url, game_path, |pct| {
        print!("\rProgress: {}%   ", pct);
        io::stdout().flush().ok();
    }) {
        Ok(_) => {
            println!();
            if let Err(e) = install::save_installed_version(&release.tag_name) {
                println!("Warning: Failed to save version: {}", e);
            }
            println!("Successfully installed version {}.", release.tag_name);
            println!("Launch Balatro through Steam — you should hear \"Blindfold loaded.\"");
        }
        Err(e) => {
            println!();
            println!("Error: {}", e);
        }
    }
}

fn install_from_file(game_path: &PathBuf) {
    let input = prompt("Press B to browse for the zip file, or type the path: ");
    let zip_path = if input.eq_ignore_ascii_case("b") {
        match rfd::FileDialog::new()
            .set_title("Select the Blindfold zip file")
            .add_filter("Zip files", &["zip"])
            .pick_file()
        {
            Some(p) => p,
            None => {
                println!("Browse cancelled.");
                return;
            }
        }
    } else {
        PathBuf::from(&input)
    };

    if !zip_path.exists() {
        println!("Error: File not found.");
        return;
    }

    match install::install_from_file(&zip_path, game_path) {
        Ok(_) => {
            println!(
                "Installed from {}.",
                zip_path.file_name().unwrap_or_default().to_string_lossy()
            );
        }
        Err(e) => println!("Error: {}", e),
    }
}

fn do_uninstall(game_path: &PathBuf) {
    if detect::is_dev_link() {
        println!("Mods\\Blindfold is a link into a development checkout: only the link");
        println!("is removed, the checkout itself is left alone.");
    }
    let confirm = prompt("Remove the Blindfold mod? (y/N): ");
    if confirm != "y" && confirm != "yes" {
        return;
    }

    match uninstall::uninstall_mod() {
        Ok(uninstall::UninstallOutcome::RemovedFolder) => println!("Removed the mod folder."),
        Ok(uninstall::UninstallOutcome::RemovedLink) => {
            println!("Removed the developer link; the checkout it pointed at is untouched.")
        }
        Ok(uninstall::UninstallOutcome::NotInstalled) => {
            println!("Mod folder not found; nothing to remove.")
        }
        Err(e) => {
            println!("Error: {}", e);
            return;
        }
    }

    if uninstall::other_mods_present() {
        println!("Other mods are still in your Mods folder; leaving the Lovely Injector in place.");
    } else {
        let remove_lovely = prompt(
            "Also remove the Lovely Injector (version.dll) from the game folder? (y/N): ",
        );
        if remove_lovely == "y" || remove_lovely == "yes" {
            match uninstall::remove_lovely(game_path) {
                Ok(true) => println!("Removed version.dll."),
                Ok(false) => println!("version.dll was not present."),
                Err(e) => println!("Error: {}", e),
            }
        }
    }

    let remove_settings =
        prompt("Also remove Blindfold's settings, keybinds, and speech log? (y/N): ");
    if remove_settings == "y" || remove_settings == "yes" {
        let removed = uninstall::remove_user_files();
        if removed.is_empty() {
            println!("No settings files found.");
        } else {
            println!("Removed: {}", removed.join(", "));
        }
    }

    println!("Uninstall complete. Game saves were not touched.");
}

fn prompt(msg: &str) -> String {
    print!("{}", msg);
    io::stdout().flush().ok();
    let mut input = String::new();
    io::stdin().read_line(&mut input).ok();
    input.trim().to_lowercase()
}
